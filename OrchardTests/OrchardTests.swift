//
//  OrchardTests.swift
//  OrchardTests
//
//  Created by David Amouzou on 15/10/2026.
//

import Foundation
import SwiftData
import Testing
@testable import Orchard

@MainActor
struct PositionTests {
    private func makeStock() throws -> (Stock, ModelContext) {
        let container = try ModelContainer(
            for: Stock.self, Trade.self, PricePoint.self, DailyClose.self, PortfolioSnapshot.self, AutopilotPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let stock = Stock(ticker: "aapl")
        context.insert(stock)
        return (stock, context)
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    @Test func tickerIsUppercased() throws {
        let (stock, _) = try makeStock()
        #expect(stock.ticker == "AAPL")
    }

    @Test func buysAverageTheirCostIncludingFees() throws {
        let (stock, _) = try makeStock()
        stock.trades.append(Trade(kind: .buy, shares: 10, price: 100, fees: 10, date: day(1), account: "PEA"))
        stock.trades.append(Trade(kind: .buy, shares: 10, price: 200, date: day(2), account: "PEA"))

        let position = stock.position()
        #expect(position.shares == 20)
        #expect(abs(position.averageCost - 150.5) < 1e-9)
        #expect(position.realizedGain == 0)
    }

    @Test func saleRealizesGainAgainstAverageCost() throws {
        let (stock, _) = try makeStock()
        stock.trades.append(Trade(kind: .buy, shares: 10, price: 100, date: day(1), account: "A"))
        stock.trades.append(Trade(kind: .sell, shares: 4, price: 150, fees: 2, date: day(2), account: "A"))

        let position = stock.position()
        #expect(position.shares == 6)
        #expect(position.averageCost == 100)
        #expect(abs(position.realizedGain - 198) < 1e-9) // 4 × (150 − 100) − 2
    }

    @Test func tradesApplyInDateOrderNotInsertionOrder() throws {
        let (stock, _) = try makeStock()
        stock.trades.append(Trade(kind: .sell, shares: 5, price: 120, date: day(3), account: "A"))
        stock.trades.append(Trade(kind: .buy, shares: 5, price: 100, date: day(1), account: "A"))

        let position = stock.position()
        #expect(position.shares == 0)
        #expect(position.averageCost == 0)
        #expect(abs(position.realizedGain - 100) < 1e-9)
    }

    @Test func accountsAreTrackedSeparately() throws {
        let (stock, _) = try makeStock()
        stock.trades.append(Trade(kind: .buy, shares: 3, price: 10, date: day(1), account: "PEA"))
        stock.trades.append(Trade(kind: .buy, shares: 7, price: 20, date: day(1), account: "CTO"))

        #expect(stock.position(account: "PEA").shares == 3)
        #expect(stock.position(account: "CTO").shares == 7)
        #expect(stock.position().shares == 10)
    }

    @Test func markPriceFallsBackToAverageCostWithoutQuote() throws {
        let (stock, _) = try makeStock()
        stock.trades.append(Trade(kind: .buy, shares: 2, price: 50, date: day(1), account: "A"))
        let position = stock.position()
        #expect(stock.markPrice(for: position) == 50)
        stock.price = 60
        #expect(stock.markPrice(for: position) == 60)
    }

    @Test func dayChangeUsesPreviousClose() throws {
        let (stock, _) = try makeStock()
        stock.price = 110
        stock.previousClose = 100
        #expect(stock.dayChange == 10)
        #expect(stock.dayChangePercent == 10)
    }
}

@MainActor
struct PracticePortfolioTests {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    @Test func cashMovesWithTrades() {
        let trades = [
            Trade(kind: .buy, shares: 10, price: 100, fees: 1, date: day(1), account: "Manual"),
            Trade(kind: .sell, shares: 4, price: 120, date: day(2), account: "Manual"),
        ]
        #expect(Portfolio.cash(startingCash: 10_000, trades: trades) == 10_000 - 1_001 + 480)
    }

    @Test func autopilotRunsOnItsDayFromCreation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let created = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 10))!
        let plan = AutopilotPlan(ticker: "VOO", amount: 50, dayOfMonth: 15)
        plan.createdAt = created

        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let dates = MarketData.dueDates(for: plan, now: now, calendar: calendar)
        let days = dates.map { calendar.dateComponents([.month, .day], from: $0) }
        #expect(days.map(\.month) == [1, 2, 3])
        #expect(days.allSatisfy { $0.day == 15 })
    }

    @Test func valueHistoryFollowsDailyCloses() throws {
        let container = try ModelContainer(
            for: Stock.self, Trade.self, PricePoint.self, DailyClose.self, PortfolioSnapshot.self, AutopilotPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let stock = Stock(ticker: "VOO")
        context.insert(stock)
        let day1 = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400))
        let day2 = day1.addingTimeInterval(86_400)
        stock.dailyCloses = [DailyClose(date: day1, close: 100), DailyClose(date: day2, close: 110)]
        // Bought 10 shares at 100 during day 1, before its close.
        stock.trades.append(Trade(kind: .buy, shares: 10, price: 100, date: day1.addingTimeInterval(15 * 3600), account: "Manual"))
        stock.price = 120

        let now = day2.addingTimeInterval(30 * 3600)
        let history = Portfolio.valueHistory(stocks: [stock], trades: stock.trades, startingCash: 10_000, now: now)
        #expect(history.map(\.value) == [10_000, 10_000, 10_100, 10_200])
        #expect(history.last?.date == now)
    }

    @Test func autopilotDoesNotRepeatAfterLastRun() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let plan = AutopilotPlan(ticker: "VOO", amount: 50, dayOfMonth: 1)
        plan.lastRun = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 30))!
        #expect(MarketData.dueDates(for: plan, now: now, calendar: calendar).isEmpty)
    }
}

@MainActor
struct FormattingTests {
    @Test func projectionWithoutGrowthIsPlainSaving() {
        #expect(Projection.futureValue(monthly: 100, annualRate: 0, years: 2) == 2_400)
    }

    @Test func projectionCompoundsMonthly() {
        let value = Projection.futureValue(monthly: 150, annualRate: 7, years: 10)
        #expect(abs(value - 25_962.72) < 0.01)
    }

    @Test func compactMoney() {
        #expect(1_860.0.compactMoney == "$1.9k")
        #expect(950.0.compactMoney == "$950")
        #expect(2_500_000.0.compactMoney == "$2.5M")
    }

    @Test func historyKeepsOnePointPerFiveMinutes() {
        let base = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 300))
        #expect(MarketData.historyBucket(base) == MarketData.historyBucket(base.addingTimeInterval(299)))
        #expect(MarketData.historyBucket(base) != MarketData.historyBucket(base.addingTimeInterval(300)))
    }

    @Test func exchangeNamesAreShortened() {
        #expect(MarketData.shortExchange("NASDAQ NMS - GLOBAL MARKET") == "NASDAQ")
        #expect(MarketData.shortExchange("NEW YORK STOCK EXCHANGE, INC.") == "NYSE")
    }
}
