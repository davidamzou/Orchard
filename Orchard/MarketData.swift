//
//  MarketData.swift
//  Orchard
//

import Foundation
import SwiftData

/// Pulls quotes and fundamentals from Finnhub into the SwiftData store.
@Observable
final class MarketData {
    /// Seconds between automatic refreshes. Finnhub's free plan allows 60 calls a minute,
    /// so this leaves room for a few dozen followed stocks.
    static let refreshInterval: TimeInterval = 60
    /// Tiingo's free plan allows 50 requests an hour; each refresh loads at most this many histories.
    static let historyFetchesPerRefresh = 5
    /// Years of daily history loaded the first time a stock is opened.
    static let historyYears = 5

    /// Price points closer together than this are merged, to keep history small.
    static let historyResolution: TimeInterval = 5 * 60

    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    var lastError: String?
    /// Last problem loading daily history, shown in Me.
    private(set) var historyError: String?

    var hasHistoryKey: Bool {
        _ = keyVersion
        return TiingoClient() != nil
    }

    func setHistoryKey(_ key: String?) {
        Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: TiingoClient.keychainAccount)
        keyVersion += 1
        historyError = nil
    }

    /// Checks a Tiingo token without saving it.
    func validateHistory(key: String) async -> String? {
        guard let client = TiingoClient(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "Paste your Tiingo token."
        }
        do {
            _ = try await client.dailyCloses("SPY", since: .now.addingTimeInterval(-7 * 86_400))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// What Autopilot did on the last refresh, shown on the Plans tab.
    private(set) var autopilotLog: [String] = []

    /// Bumped when the API key changes so views re-evaluate `hasKey`.
    private(set) var keyVersion = 0

    var hasKey: Bool {
        _ = keyVersion
        return FinnhubClient() != nil
    }


    func setAPIKey(_ key: String?) {
        Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: FinnhubClient.keychainAccount)
        keyVersion += 1
        lastError = nil
    }

    /// Checks a key against Finnhub without saving it.
    func validate(key: String) async -> String? {
        guard let client = FinnhubClient(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return FinnhubClient.Failure.missingKey.localizedDescription
        }
        do {
            _ = try await client.quote("AAPL")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func search(_ query: String) async throws -> [FinnhubClient.SearchResult] {
        guard let client = FinnhubClient() else { throw FinnhubClient.Failure.missingKey }
        return try await client.search(query)
    }

    /// Refreshes every followed stock, unless the last refresh is more recent than `minimumInterval`.
    func refreshAll(in context: ModelContext, minimumInterval: TimeInterval = 0) async {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < minimumInterval { return }
        if lastRefresh == nil { pruneUnfollowed(in: context) }
        let stocks = (try? context.fetch(FetchDescriptor<Stock>())) ?? []
        await refresh(stocks, in: context)
        runAutopilot(in: context)

        // Held stocks first, then the watchlist; each needs at most one fetch a day.
        let needingHistory = stocks
            .filter { Self.needsHistory($0) && ($0.position().shares > 0 || $0.isWatched) }
            .sorted { ($0.position().shares > 0 ? 0 : 1) < ($1.position().shares > 0 ? 0 : 1) }
        for stock in needingHistory.prefix(Self.historyFetchesPerRefresh) {
            await loadHistory(for: stock, in: context)
        }
    }

    static func needsHistory(_ stock: Stock, now: Date = .now) -> Bool {
        guard let updated = stock.dailyUpdatedAt else { return true }
        return !Calendar.current.isDate(updated, inSameDayAs: now)
    }

    /// Loads daily closes from Tiingo: five years the first time, then only the new days.
    func loadHistory(for stock: Stock, in context: ModelContext) async {
        guard let client = TiingoClient(), Self.needsHistory(stock) else { return }
        let last = stock.dailyCloses.map(\.date).max()
        let start = last?.addingTimeInterval(86_400)
            ?? Calendar.current.date(byAdding: .year, value: -Self.historyYears, to: .now)!
        do {
            let bars = try await client.dailyCloses(stock.ticker, since: start)
            let known = Set(stock.dailyCloses.map(\.date))
            for bar in bars where !known.contains(bar.date) {
                stock.dailyCloses.append(DailyClose(date: bar.date, close: bar.adjClose))
            }
            stock.dailyUpdatedAt = .now
            historyError = nil
            try? context.save()
        } catch TiingoClient.Failure.unknownSymbol {
            stock.dailyUpdatedAt = .now   // don't retry until tomorrow
        } catch {
            historyError = error.localizedDescription
        }
    }

    /// Fetches a fresh quote for an order. Throws when no price can be had.
    func livePrice(for stock: Stock, in context: ModelContext) async throws -> Double {
        guard let client = FinnhubClient() else { throw FinnhubClient.Failure.missingKey }
        try await update(stock, with: client)
        try? context.save()
        guard let price = stock.price, price > 0 else { throw FinnhubClient.Failure.unknownSymbol(stock.ticker) }
        return price
    }

    func refresh(_ stocks: [Stock], in context: ModelContext) async {
        guard !isRefreshing else { return }
        guard let client = FinnhubClient() else {
            lastError = FinnhubClient.Failure.missingKey.localizedDescription
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        for stock in stocks {
            do {
                try await update(stock, with: client)
            } catch FinnhubClient.Failure.rateLimited {
                lastError = FinnhubClient.Failure.rateLimited.localizedDescription
                break
            } catch {
                lastError = error.localizedDescription
            }
        }
        recordSnapshot(in: context)
        try? context.save()
        lastRefresh = .now
    }

    private func update(_ stock: Stock, with client: FinnhubClient) async throws {
        let quote = try await client.quote(stock.ticker)
        stock.price = quote.c
        stock.previousClose = quote.pc
        stock.quoteUpdatedAt = Date(timeIntervalSince1970: quote.t)

        // Finnhub's free plan has no price history, so the app builds its own,
        // one point per quote time (several minutes apart at most).
        let quoteTime = Date(timeIntervalSince1970: quote.t)
        let last = stock.history.max { $0.date < $1.date }
        if let last, quoteTime <= last.date {
            // Same quote as last time (market closed): nothing new.
        } else if let last, Self.historyBucket(quoteTime) == Self.historyBucket(last.date) {
            last.date = quoteTime
            last.price = quote.c
        } else {
            stock.history.append(PricePoint(date: quoteTime, price: quote.c))
        }

        let isStale = stock.fundamentalsUpdatedAt.map { Date.now.timeIntervalSince($0) > 86_400 } ?? true
        guard isStale else { return }
        if let profile = try? await client.profile(stock.ticker) {
            if let name = profile.name, !name.isEmpty { stock.name = name }
            if let exchange = profile.exchange { stock.exchange = Self.shortExchange(exchange) }
            if let currency = profile.currency { stock.currency = currency }
            stock.marketCap = profile.marketCapitalization
        }
        if let metrics = try? await client.metrics(stock.ticker).metric {
            stock.peRatio = metrics.peTTM
            stock.dividendYield = metrics.dividendYield
            stock.averageVolume = metrics.averageVolume
            stock.high52Week = metrics.high52Week
            stock.low52Week = metrics.low52Week
        }
        stock.fundamentalsUpdatedAt = .now
    }

    /// Stocks opened from search but never traded, starred or planned are dropped at launch.
    private func pruneUnfollowed(in context: ModelContext) {
        let planned = Set(((try? context.fetch(FetchDescriptor<AutopilotPlan>())) ?? []).map(\.ticker))
        for stock in (try? context.fetch(FetchDescriptor<Stock>())) ?? []
        where stock.trades.isEmpty && !stock.isWatched && !planned.contains(stock.ticker) {
            context.delete(stock)
        }
        try? context.save()
    }

    // MARK: Autopilot

    /// Buys each enabled plan's amount for every monthly due date reached since its last run,
    /// at the current price, with the practice cash.
    func runAutopilot(in context: ModelContext, now: Date = .now) {
        let plans = ((try? context.fetch(FetchDescriptor<AutopilotPlan>())) ?? []).filter(\.isEnabled)
        guard !plans.isEmpty else { return }
        var log: [String] = []
        for plan in plans {
            for due in Self.dueDates(for: plan, now: now) {
                plan.lastRun = due
                let stock = context.stock(ticker: plan.ticker)
                let trades = (try? context.fetch(FetchDescriptor<Trade>())) ?? []
                let cash = Portfolio.cash(startingCash: Portfolio.startingCash, trades: trades)
                guard let price = stock.price, price > 0 else {
                    log.append("Skipped \(plan.ticker) on \(due.formatted(date: .abbreviated, time: .omitted)): no price yet.")
                    continue
                }
                guard cash >= plan.amount else {
                    log.append("Skipped \(plan.ticker) on \(due.formatted(date: .abbreviated, time: .omitted)): not enough cash.")
                    continue
                }
                stock.trades.append(Trade(kind: .buy, shares: plan.amount / price, price: price,
                                          date: now, account: Portfolio.autopilotAccount))
                log.append("Bought \(plan.amount.money(decimals: 0)) of \(plan.ticker) at \(price.currency).")
            }
        }
        if !log.isEmpty {
            autopilotLog = log
            recordSnapshot(in: context)
            try? context.save()
        }
    }

    /// Monthly due dates after the plan's last run, up to `now` (at most a year of catch-up).
    static func dueDates(for plan: AutopilotPlan, now: Date, calendar: Calendar = .current) -> [Date] {
        // A new plan whose day is today runs today.
        let after = plan.lastRun ?? calendar.startOfDay(for: plan.createdAt).addingTimeInterval(-1)
        var month = calendar.dateComponents([.year, .month], from: after)
        var dates: [Date] = []
        for _ in 0..<13 {
            month.day = plan.dayOfMonth
            guard let due = calendar.date(from: month) else { break }
            if due > now { break }
            if due > after { dates.append(due) }
            month.day = nil
            guard let next = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: month)!) else { break }
            month = calendar.dateComponents([.year, .month], from: next)
        }
        return dates
    }

    private func recordSnapshot(in context: ModelContext) {
        let stocks = (try? context.fetch(FetchDescriptor<Stock>())) ?? []
        let trades = (try? context.fetch(FetchDescriptor<Trade>())) ?? []
        let holdings = stocks.reduce(0) { total, stock in
            let position = stock.position()
            return total + position.shares * stock.markPrice(for: position)
        }
        let value = holdings + Portfolio.cash(startingCash: Portfolio.startingCash, trades: trades)
        guard value > 0 else { return }
        let day = Calendar.current.startOfDay(for: .now)
        let existing = try? context.fetch(FetchDescriptor<PortfolioSnapshot>(predicate: #Predicate { $0.day == day })).first
        if let existing {
            existing.value = value
        } else {
            context.insert(PortfolioSnapshot(day: day, value: value))
        }
    }

    /// Index of the fixed 5-minute window a date falls in; one price point is kept per window.
    static func historyBucket(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / historyResolution)
    }

    /// "NASDAQ NMS - GLOBAL MARKET" → "NASDAQ", "NEW YORK STOCK EXCHANGE, INC." → "NYSE".
    static func shortExchange(_ name: String) -> String {
        let upper = name.uppercased()
        if upper.contains("NASDAQ") { return "NASDAQ" }
        if upper.contains("NEW YORK") { return "NYSE" }
        if upper.contains("ARCA") { return "NYSE ARCA" }
        return upper.components(separatedBy: CharacterSet(charactersIn: ",-")).first?
            .trimmingCharacters(in: .whitespaces) ?? upper
    }
}
