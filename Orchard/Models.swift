//
//  Models.swift
//  Orchard
//

import Foundation
import SwiftData

/// A stock or ETF the user follows: either held (has trades) or only on the watchlist.
@Model
final class Stock {
    @Attribute(.unique) var ticker: String
    var name: String
    var exchange: String
    var currency: String
    var isWatched: Bool
    var addedAt: Date

    // Latest quote
    var price: Double?
    var previousClose: Double?
    var quoteUpdatedAt: Date?

    // Fundamentals
    var marketCap: Double?          // in millions, quote currency
    var peRatio: Double?
    var dividendYield: Double?      // percent
    var averageVolume: Double?      // millions of shares, 10-day average
    var high52Week: Double?
    var low52Week: Double?
    var fundamentalsUpdatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Trade.stock) var trades: [Trade] = []
    @Relationship(deleteRule: .cascade, inverse: \PricePoint.stock) var history: [PricePoint] = []
    @Relationship(deleteRule: .cascade, inverse: \DailyClose.stock) var dailyCloses: [DailyClose] = []
    /// When daily history was last fetched from Tiingo.
    var dailyUpdatedAt: Date?

    init(ticker: String, name: String = "", exchange: String = "", currency: String = "USD", isWatched: Bool = false) {
        self.ticker = ticker.uppercased()
        self.name = name
        self.exchange = exchange
        self.currency = currency
        self.isWatched = isWatched
        self.addedAt = .now
    }
}

@Model
final class Trade {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case buy, sell
        var id: Self { self }
    }

    var kindRaw: String
    var shares: Double
    var price: Double
    var fees: Double
    var date: Date
    var account: String
    var stock: Stock?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .buy }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: Kind, shares: Double, price: Double, fees: Double = 0, date: Date = .now, account: String) {
        self.kindRaw = kind.rawValue
        self.shares = shares
        self.price = price
        self.fees = fees
        self.date = date
        self.account = account
    }
}

/// One recorded price per stock per refresh, used for the price chart and sparklines.
@Model
final class PricePoint {
    var date: Date
    var price: Double
    var stock: Stock?

    init(date: Date, price: Double) {
        self.date = date
        self.price = price
    }
}

/// End-of-day closing price (split- and dividend-adjusted) from Tiingo, one per trading day.
@Model
final class DailyClose {
    var date: Date
    var close: Double
    var stock: Stock?

    init(date: Date, close: Double) {
        self.date = date
        self.close = close
    }
}

/// Portfolio value, one row per day (latest refresh wins), for the dashboard chart.
@Model
final class PortfolioSnapshot {
    @Attribute(.unique) var day: Date
    var value: Double

    init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

/// A monthly reminder to invest a fixed amount in one stock.
@Model
final class AutopilotPlan {
    var ticker: String
    var amount: Double
    var dayOfMonth: Int
    var isEnabled: Bool
    var createdAt: Date
    var notificationID: String
    /// Last monthly due date the plan bought for; nil until its first run.
    var lastRun: Date?

    init(ticker: String, amount: Double, dayOfMonth: Int) {
        self.ticker = ticker.uppercased()
        self.amount = amount
        self.dayOfMonth = dayOfMonth
        self.isEnabled = true
        self.createdAt = .now
        self.notificationID = UUID().uuidString
    }
}

// MARK: - Practice portfolio

/// Orchard is a paper-trading app: every trade spends or returns virtual cash.
enum Portfolio {
    static let startingCashKey = "startingCash"
    static let defaultStartingCash = 10_000.0
    static let startingCashOptions: [Double] = [1_000, 10_000, 100_000]
    static let manualAccount = "Manual"
    static let autopilotAccount = "Autopilot"

    static var startingCash: Double {
        let stored = UserDefaults.standard.double(forKey: startingCashKey)
        return stored > 0 ? stored : defaultStartingCash
    }

    /// Tiingo dates a daily bar at midnight UTC; the US close is at 16:00 New York time.
    static func closeTime(of barDate: Date) -> Date {
        barDate.addingTimeInterval(21 * 3600)
    }

    /// Value of the practice account over time: starting cash just before the first trade,
    /// then every daily close since, then today with live prices.
    static func valueHistory(stocks: [Stock], trades: [Trade], startingCash: Double,
                             now: Date = .now) -> [(date: Date, value: Double)] {
        let ordered = trades.sorted { $0.date < $1.date }
        guard let first = ordered.first else { return [] }

        // Closing prices per ticker, oldest first.
        var closes: [String: [(date: Date, close: Double)]] = [:]
        for stock in stocks {
            closes[stock.ticker] = stock.dailyCloses
                .map { (date: closeTime(of: $0.date), close: $0.close) }
                .sorted { $0.date < $1.date }
        }
        let closeTimes = Set(closes.values.flatMap { $0.map(\.date) })
            .filter { $0 > first.date && $0 < now }
            .sorted()

        var points: [(date: Date, value: Double)] = [(first.date.addingTimeInterval(-1), startingCash)]
        for time in closeTimes {
            var cash = startingCash
            var shares: [String: Double] = [:]
            for trade in ordered where trade.date <= time {
                let ticker = trade.stock?.ticker ?? ""
                let sign: Double = trade.kind == .buy ? 1 : -1
                shares[ticker, default: 0] += sign * trade.shares
                cash -= sign * trade.shares * trade.price + trade.fees
            }
            var value = cash
            for (ticker, count) in shares where count > 0 {
                // Latest close on or before this day; skip the day if a holding has none yet.
                guard let close = closes[ticker]?.last(where: { $0.date <= time })?.close else { value = .nan; break }
                value += count * close
            }
            if value.isFinite { points.append((time, value)) }
        }

        let holdings = stocks.reduce(0) { total, stock in
            let position = stock.position()
            return total + position.shares * stock.markPrice(for: position)
        }
        points.append((now, cash(startingCash: startingCash, trades: trades) + holdings))
        return points
    }

    /// Cash left after every trade so far.
    static func cash(startingCash: Double, trades: [Trade]) -> Double {
        trades.reduce(startingCash) { cash, trade in
            switch trade.kind {
            case .buy: cash - trade.shares * trade.price - trade.fees
            case .sell: cash + trade.shares * trade.price - trade.fees
            }
        }
    }
}

// MARK: - Position maths

struct Position {
    let shares: Double
    /// Average cost per share of the shares still held (fees included).
    let averageCost: Double
    /// Gains already locked in by sales.
    let realizedGain: Double

    var costBasis: Double { shares * averageCost }
}

extension Stock {
    func position(account: String? = nil) -> Position {
        var shares = 0.0, cost = 0.0, realized = 0.0
        let ordered = trades
            .filter { account == nil || $0.account == account }
            .sorted { $0.date < $1.date }
        for trade in ordered {
            switch trade.kind {
            case .buy:
                cost += trade.shares * trade.price + trade.fees
                shares += trade.shares
            case .sell:
                let sold = min(trade.shares, shares)
                guard sold > 0 else { continue }
                let average = cost / shares
                realized += sold * trade.price - trade.fees - sold * average
                cost -= sold * average
                shares -= sold
            }
        }
        if shares < 1e-9 { shares = 0; cost = 0 }
        return Position(shares: shares, averageCost: shares > 0 ? cost / shares : 0, realizedGain: realized)
    }

    var displayName: String { name.isEmpty ? ticker : name }

    /// Price to value the position with: the live quote, or the average cost until a quote arrives.
    func markPrice(for position: Position) -> Double {
        price ?? position.averageCost
    }

    var dayChange: Double? {
        guard let price, let previousClose, previousClose > 0 else { return nil }
        return price - previousClose
    }

    var dayChangePercent: Double? {
        guard let dayChange, let previousClose, previousClose > 0 else { return nil }
        return dayChange / previousClose * 100
    }

    var sortedHistory: [PricePoint] { history.sorted { $0.date < $1.date } }

    /// Prices to chart for a range: Orchard's own intraday records for 1D, Tiingo's
    /// daily closes otherwise (falling back to the intraday records), ending on the live price.
    @MainActor
    func chartSeries(for range: TimeRange, now: Date = .now) -> [(date: Date, value: Double)] {
        let intraday = sortedHistory.map { (date: $0.date, value: $0.price) }
        if range == .day {
            guard let latest = intraday.last?.date else { return [] }
            return intraday.filter { latest.timeIntervalSince($0.date) <= 86_400 }
        }
        let closes = dailyCloses
            .map { (date: Portfolio.closeTime(of: $0.date), value: $0.close) }
            .filter { $0.date >= range.start }
            .sorted { $0.date < $1.date }
        guard !closes.isEmpty else { return intraday.filter { $0.date >= range.start } }
        var series = closes
        let updated = quoteUpdatedAt ?? now
        if let price, let last = series.last, updated > last.date {
            series.append((date: updated, value: price))
        }
        return series
    }
}

extension Double {
    /// Share counts can be fractional; show up to 4 decimals without trailing zeros.
    var shareCount: String { formatted(.number.precision(.fractionLength(0...4)).locale(.app)) }
}
