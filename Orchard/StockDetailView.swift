//
//  StockDetailView.swift
//  Orchard
//

import SwiftData
import SwiftUI

struct StockDetailView: View {
    @Bindable var stock: Stock
    var onTrade: (TradeRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(MarketData.self) private var marketData
    @State private var range: TimeRange = .month

    var body: some View {
        let position = stock.position()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                overview
                priceHistory
                if position.shares > 0 || !stock.trades.isEmpty {
                    positionSection(position)
                }
                keyStats
                tradesSection
            }
            .foregroundStyle(Palette.ink)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await marketData.refresh([stock], in: context) }
        .buttonStyle(.plain)
        // Lime behind the top overscroll, paper behind the bottom.
        .background {
            VStack(spacing: 0) {
                Palette.lime
                Palette.paper
            }
            .ignoresSafeArea()
        }
        .hidesNavigationBar()
        .task { await marketData.refresh([stock], in: context) }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image("chevron-left")
                        .frame(width: 44, height: 44)
                        .background(Palette.deepInk)
                }
                .accessibilityLabel("Back")
                Spacer()
                Text(stock.exchange.isEmpty ? stock.ticker : "\(stock.ticker) · \(stock.exchange)")
                    .font(.inter(9, weight: .medium, relativeTo: .caption2))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 130, minHeight: 30)
                    .overlay(Rectangle().strokeBorder(Palette.limeBorder))
                Spacer()
                Button { stock.isWatched.toggle() } label: {
                    Image(systemName: stock.isWatched ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .light))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Palette.limeBorder))
                        .contentShape(.circle)
                }
                .accessibilityLabel(stock.isWatched ? "Remove from watchlist" : "Add to watchlist")
            }
            .frame(height: 46)
            .padding(.top, 4)

            Text(stock.displayName)
                .font(.serif(41, italic: true, relativeTo: .title))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 13)
            Text(stock.price?.money(stock.currency) ?? "—")
                .font(.serif(83))
                .foregroundStyle(Palette.deepInk)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(height: 83)

            HStack(spacing: 8) {
                if let change = stock.dayChangePercent {
                    HStack(spacing: 5) {
                        Text(change >= 0 ? "▲" : "▼").font(.inter(9, relativeTo: .caption2))
                        Text(change.signedPercent()).font(.inter(10, weight: .semibold, relativeTo: .caption))
                    }
                    .foregroundStyle(change >= 0 ? Palette.lime : Palette.paper)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(change >= 0 ? Palette.deepInk : Palette.loss)
                }
                Text(quoteStatus)
                    .font(.inter(10, relativeTo: .caption))
                    .lineLimit(2)
            }
            .frame(minHeight: 28)
            .padding(.top, 17)
            .padding(.bottom, 7)
        }
        .padding(.horizontal, 18)
        .background(Palette.lime)
    }

    private var quoteStatus: String {
        if marketData.isRefreshing && stock.price == nil { return "Loading quote…" }
        if let updated = stock.quoteUpdatedAt {
            let calendar = Calendar.current
            let style: Date.FormatStyle = calendar.isDateInToday(updated)
                ? .dateTime.hour().minute()
                : .dateTime.month(.abbreviated).day().hour().minute()
            return "As of \(updated.formatted(style))"
        }
        return marketData.lastError ?? "No quote yet"
    }

    // MARK: Price history

    private var priceHistory: some View {
        VStack(spacing: 0) {
            AreaLineChart(
                points: stock.sortedHistory
                    .filter { $0.date >= range.start }
                    .map { .init(date: $0.date, value: $0.price) },
                fill: Palette.limeBorder.opacity(0.45),
                line: Palette.ink,
                showsMarker: true,
                emptyMessage: "Orchard records a price each time you check in. The chart fills in as you keep tracking."
            )
            .frame(height: 130)
            .padding(.top, 12)

            HStack(spacing: 0) {
                ForEach(TimeRange.allCases) { option in
                    Button { range = option } label: {
                        Text(option.rawValue)
                            .font(.inter(9.5, weight: .medium, relativeTo: .caption2))
                            .foregroundStyle(range == option ? Palette.lime : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(range == option ? Palette.deepInk : Palette.lime)
                            .contentShape(.rect)
                    }
                    .accessibilityAddTraits(range == option ? .isSelected : [])
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.ink).frame(height: 1)
            }
        }
        .background(Palette.lime)
    }

    // MARK: Position

    private func positionSection(_ position: Position) -> some View {
        let price = stock.markPrice(for: position)
        let value = position.shares * price
        let unrealized = position.shares * (price - position.averageCost)
        let returnPercent = position.costBasis > 0 ? unrealized / position.costBasis * 100 : 0
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("YOUR POSITION")
                .frame(height: 44)
                .padding(.horizontal, 18)
            HStack(spacing: 0) {
                metric("SHARES", position.shares.shareCount, detail: "avg \(position.averageCost.money(stock.currency))", span: 117,
                       background: Palette.lavender, label: Palette.ink, value: Palette.ink)
                metric("VALUE", value.money(stock.currency, decimals: value >= 10_000 ? 0 : 2),
                       detail: "cost \(position.costBasis.money(stock.currency, decimals: 0))", span: 156,
                       background: Palette.deepInk, label: Palette.lime, value: Palette.paper)
                metric("RETURN", position.shares > 0 ? returnPercent.signedPercent(1) : "—",
                       detail: (unrealized + position.realizedGain).money(stock.currency, decimals: 0), span: 117,
                       background: returnPercent >= 0 ? Palette.forest : Palette.loss, label: Palette.lime, value: Palette.lime)
            }
        }
    }

    private func metric(_ title: String, _ value: String, detail: String, span: Int,
                        background: Color, label: Color, value valueColor: Color) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.inter(8.5, weight: .medium, relativeTo: .caption2))
                .foregroundStyle(label)
            Spacer()
            Text(value)
                .font(.serif(34, relativeTo: .title))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(detail)
                .font(.inter(8.5, relativeTo: .caption2))
                .foregroundStyle(label.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 113)
        .background(background)
        .containerRelativeFrame(.horizontal, count: 390, span: span, spacing: 0)
        .accessibilityElement(children: .combine)
    }

    // MARK: Key stats

    private var keyStats: some View {
        let stats: [(String, String)] = [
            ("Market cap", stock.marketCap.map(\.compactMillions) ?? "—"),
            ("P/E ratio", stock.peRatio.map { $0.decimal(1) } ?? "—"),
            ("Div yield", stock.dividendYield.map { $0.decimal(2) + "%" } ?? "—"),
            ("Avg volume", stock.averageVolume.map(\.compactMillions) ?? "—"),
            ("52w high", stock.high52Week.map { $0.decimal(2) } ?? "—"),
            ("52w low", stock.low52Week.map { $0.decimal(2) } ?? "—"),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("KEY STATS")
                .padding(.bottom, 10)
            Rectangle().fill(Palette.ink).frame(height: 1)
            ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                HStack(spacing: 14) {
                    stat(stats[index])
                    stat(stats[index + 1])
                }
                .frame(height: 48)
                Rectangle().fill(Palette.divider).frame(height: 1)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 18)
    }

    private func stat(_ stat: (label: String, value: String)) -> some View {
        HStack {
            Text(stat.label).foregroundStyle(Palette.muted)
            Spacer()
            Text(stat.value).fontWeight(.medium)
        }
        .font(.inter(10.5, relativeTo: .caption))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Trades

    private var tradesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("YOUR PRACTICE TRADES")
                .padding(.bottom, 10)
            Rectangle().fill(Palette.ink).frame(height: 1)
            ForEach(stock.trades.sorted { $0.date > $1.date }) { trade in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(trade.kind == .buy ? "Bought" : "Sold") \(trade.shares.shareCount) @ \(trade.price.money(stock.currency))")
                            .font(.inter(11, weight: .medium, relativeTo: .caption))
                        Text("\(trade.date.formatted(date: .abbreviated, time: .omitted)) · \(trade.account)")
                            .font(.inter(9.5, relativeTo: .caption2))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Text((trade.shares * trade.price).money(stock.currency))
                        .font(.inter(11, relativeTo: .caption))
                        .foregroundStyle(trade.kind == .buy ? Palette.ink : Palette.gain)
                }
                .frame(minHeight: 52)
                .contentShape(.rect)
                .contextMenu {
                    Button("Delete trade", systemImage: "trash", role: .destructive) {
                        context.delete(trade)
                        try? context.save()
                    }
                }
                Rectangle().fill(Palette.divider).frame(height: 1)
            }
            HStack(spacing: 0) {
                tradeButton("Buy", kind: .buy, background: Palette.ink, foreground: Palette.lime)
                tradeButton("Sell", kind: .sell, background: Palette.lavender, foreground: Palette.ink)
                    .disabled(stock.position().shares <= 0)
            }
            .padding(.top, 16)
            if !stock.trades.isEmpty {
                Text("Touch and hold a trade to delete it.")
                    .font(.inter(9.5, relativeTo: .caption2))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 8)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
    }

    private func tradeButton(_ title: String, kind: Trade.Kind, background: Color, foreground: Color) -> some View {
        Button { onTrade(TradeRequest(kind: kind, ticker: stock.ticker)) } label: {
            Text(title)
                .font(.inter(12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(background)
                .contentShape(.rect)
        }
    }
}
