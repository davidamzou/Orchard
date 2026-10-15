//
//  DashboardView.swift
//  Orchard
//

import SwiftData
import SwiftUI

enum AppTab: CaseIterable, Identifiable {
    case home, markets, plans, me
    var id: Self { self }

    var title: String {
        switch self {
        case .home: "HOME"
        case .markets: "MARKETS"
        case .plans: "PLANS"
        case .me: "ME"
        }
    }

    var icon: String {
        switch self {
        case .home: "nav-home"
        case .markets: "nav-markets"
        case .plans: "nav-plans"
        case .me: "nav-me"
        }
    }
}

/// What the trade sheet should open with.
struct TradeRequest: Identifiable {
    var kind: Trade.Kind
    var ticker: String?
    let id = UUID()
}

struct DashboardView: View {
    @Environment(MarketData.self) private var marketData
    @Environment(\.modelContext) private var context
    @State private var tab: AppTab = .home
    @State private var tradeRequest: TradeRequest?

    var body: some View {
        // The bar sits below the content rather than over it, so every tab's
        // last row stays reachable.
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home:
                    NavigationStack {
                        HomeView(onTrade: { tradeRequest = TradeRequest(kind: $0) }, onAutopilot: { tab = .plans })
                            .stockDestination(onTrade: { tradeRequest = $0 })
                    }
                case .markets:
                    NavigationStack {
                        MarketsView()
                            .stockDestination(onTrade: { tradeRequest = $0 })
                    }
                case .plans:
                    PlansView()
                case .me:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.paper)
            // The + button rises above the bar; keep scroll content clear of it.
            .safeAreaPadding(.bottom, BottomBar.addButtonOverhang)
            BottomBar(selection: $tab, onAdd: { tradeRequest = TradeRequest(kind: .buy) })
        }
        .background(Palette.paper)
        // Keep the tab bar at the bottom while typing in Markets search.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(item: $tradeRequest) { request in
            TradeSheet(request: request)
        }
        .task {
            await marketData.refreshAll(in: context, minimumInterval: 300)
        }
    }
}

private extension View {
    func stockDestination(onTrade: @escaping (TradeRequest) -> Void) -> some View {
        navigationDestination(for: Stock.self) { stock in
            StockDetailView(stock: stock, onTrade: onTrade)
        }
        .navigationDestination(for: StockLookup.self) { lookup in
            ResolvedStockView(lookup: lookup, onTrade: onTrade)
        }
    }
}

/// A search result the user opened; it becomes a followed `Stock` only once pushed.
struct StockLookup: Hashable {
    let ticker: String
    let name: String
}

private struct ResolvedStockView: View {
    let lookup: StockLookup
    let onTrade: (TradeRequest) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        StockDetailView(stock: context.stock(ticker: lookup.ticker, name: lookup.name), onTrade: onTrade)
    }
}

// MARK: - Home

private enum HoldingsFilter: CaseIterable, Identifiable {
    case holdings, watchlist
    var id: Self { self }
    var title: String { self == .holdings ? "Holdings" : "Watchlist" }
}

private struct HomeView: View {
    var onTrade: (Trade.Kind) -> Void
    var onAutopilot: () -> Void

    @Environment(MarketData.self) private var marketData
    @Environment(\.modelContext) private var context
    @Query(sort: \Stock.ticker) private var stocks: [Stock]
    @Query(sort: \PortfolioSnapshot.day) private var snapshots: [PortfolioSnapshot]
    @Query private var trades: [Trade]
    @AppStorage(Portfolio.startingCashKey) private var startingCash = Portfolio.defaultStartingCash
    @State private var filter: HoldingsFilter = .holdings

    private struct Holding: Identifiable {
        let stock: Stock
        let position: Position
        var value: Double { position.shares * stock.markPrice(for: position) }
        var id: String { stock.ticker }
    }

    private var holdings: [Holding] {
        stocks
            .map { Holding(stock: $0, position: $0.position()) }
            .filter { $0.position.shares > 0 }
            .sorted { $0.value > $1.value }
    }

    private var watchlist: [Stock] { stocks.filter(\.isWatched) }

    var body: some View {
        let holdings = holdings
        let cash = Portfolio.cash(startingCash: startingCash, trades: trades)
        let total = cash + holdings.reduce(0) { $0 + $1.value }
        let dayGain = holdings.reduce(0) { $0 + ($1.stock.dayChange ?? 0) * $1.position.shares }
        let previousTotal = total - dayGain

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                accountControls(cash: cash)
                    .padding(.horizontal, 18)
                    .padding(.top, 28)
                portfolioOverview(total: total, dayGain: dayGain,
                                  dayChange: previousTotal > 0 ? dayGain / previousTotal * 100 : 0)
                    .padding(.top, 26)
                investmentActions
                holdingsSection(holdings)
                    .padding(.horizontal, 18)
                    .padding(.top, 27)
            }
            .foregroundStyle(Palette.ink)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await marketData.refreshAll(in: context) }
        .buttonStyle(.plain)
        .background(Palette.paper)
        .hidesNavigationBar()
    }

    private var brandHeader: some View {
        HStack {
            Text("Orchard")
                .font(.serif(29, relativeTo: .title))
                .overlay(alignment: .topTrailing) {
                    Image("brand-accent").offset(x: 7, y: 11)
                }
            Spacer()
            if marketData.isRefreshing {
                ProgressView().controlSize(.small).tint(Palette.ink)
            } else {
                Button {
                    Task { await marketData.refreshAll(in: context) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Refresh prices")
            }
        }
        .frame(height: 34)
    }

    private func accountControls(cash: Double) -> some View {
        HStack {
            HStack(spacing: 7) {
                Rectangle().fill(Palette.lime).frame(width: 6, height: 6)
                Text("Practice account")
                    .font(.inter(12, weight: .medium))
                    .foregroundStyle(Palette.paper)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("VIRTUAL")
                    .font(.inter(8, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(Palette.lime)
            }
            .padding(.horizontal, 12)
            .frame(width: 198, height: 41)
            .background(Palette.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("CASH")
                    .font(.inter(8.5, weight: .medium, relativeTo: .caption2))
                    .foregroundStyle(Palette.muted)
                Text(cash.currency)
                    .font(.inter(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Gain or loss on everything since the practice account was opened.
    private func totalReturn(_ total: Double) -> some View {
        let gain = total - startingCash
        let percent = startingCash > 0 ? gain / startingCash * 100 : 0
        return HStack(spacing: 6) {
            Text("SINCE START")
                .font(.inter(8.5, weight: .medium, relativeTo: .caption2))
                .foregroundStyle(Palette.muted)
            Text("\(gain >= 0 ? "+" : "−")\(abs(gain).currency) · \(percent.signedPercent())")
                .font(.inter(10, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(gain >= 0 ? Palette.ink : Palette.loss)
        }
        .frame(height: 20)
    }

    private func portfolioOverview(total: Double, dayGain: Double, dayChange: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOTAL VALUE")
                Spacer()
                Text("USD")
            }
            .font(.inter(9.5, weight: .medium, relativeTo: .caption2))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 18)

            balance(total)
                .padding(.horizontal, 18)
                .padding(.top, 7)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text(dayGain >= 0 ? "↗" : "↘")
                    Text("\(abs(dayGain).currency) · \(abs(dayChange).decimal(2))%")
                        .fontWeight(.semibold)
                }
                .font(.inter(10, relativeTo: .caption))
                .foregroundStyle(dayGain >= 0 ? Palette.ink : Palette.paper)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(dayGain >= 0 ? Palette.lime : Palette.loss)
                Text(statusLine)
                    .font(.inter(9, relativeTo: .caption2))
                    .foregroundStyle(marketData.lastError == nil ? Palette.muted : Palette.loss)
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            totalReturn(total)
                .padding(.horizontal, 18)
                .padding(.top, 8)

            AreaLineChart(
                points: snapshots.map { .init(date: $0.day, value: $0.value) },
                fill: Palette.lavender.opacity(0.55),
                line: Palette.ink,
                emptyMessage: "Your growth curve appears after a second day of tracking."
            )
            .frame(height: 104)
            .padding(.top, 7)
        }
    }

    private var statusLine: String {
        if let error = marketData.lastError { return error }
        if let last = marketData.lastRefresh {
            return "today · updated \(last.formatted(date: .omitted, time: .shortened))"
        }
        return "today · change since last close"
    }

    private func balance(_ total: Double) -> some View {
        let whole = Int(total)
        let cents = Int((total * 100).rounded()) % 100
        let wholeText = Text("$\(whole, format: .number)").font(.serif(79))
        let centsText = Text(".\(cents, format: .number.precision(.integerLength(2)))")
            .font(.serif(36))
            .foregroundStyle(Palette.faint)
        return Text("\(wholeText)\(centsText)")
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityLabel(total.currency)
    }

    private var investmentActions: some View {
        HStack(spacing: 0) {
            ActionTile(symbol: "action-invest", title: "Buy", detail: "LIVE PRICES",
                       background: Palette.lime, foreground: Palette.ink, span: 149) { onTrade(.buy) }
            ActionTile(symbol: "action-cash-out", title: "Sell", detail: "LOCK IN GAINS",
                       background: Palette.lavender, foreground: Palette.ink, span: 123) { onTrade(.sell) }
            ActionTile(symbol: "action-autopilot", title: "Autopilot", detail: "SET & GROW",
                       background: Palette.ink, foreground: Palette.lime, span: 118, action: onAutopilot)
        }
    }

    private func holdingsSection(_ holdings: [Holding]) -> some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack(spacing: 17) {
                ForEach(HoldingsFilter.allCases) { option in
                    Button { filter = option } label: {
                        Text(option.title)
                            .font(.inter(10, weight: filter == option ? .medium : .regular, relativeTo: .caption))
                            .foregroundStyle(filter == option ? Palette.paper : Palette.muted)
                            .padding(.horizontal, filter == option ? 12 : 0)
                            .frame(height: 36)
                            .background(filter == option ? Palette.ink : .clear)
                    }
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
                Spacer()
                Text(filter == .holdings
                     ? "\(holdings.count) position\(holdings.count == 1 ? "" : "s")"
                     : "\(watchlist.count) followed")
                    .font(.inter(9, relativeTo: .caption2))
                    .foregroundStyle(Palette.muted)
            }

            switch filter {
            case .holdings:
                if holdings.isEmpty {
                    emptyState(
                        "You have \(startingCash.money(decimals: 0)) of practice money. Buy your first stock or ETF at today's real price. No real money involved.",
                        button: "Make my first trade"
                    ) { onTrade(.buy) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                            NavigationLink(value: holding.stock) {
                                StockRow(stock: holding.stock,
                                         subtitle: "\(holding.position.shares.shareCount) shares",
                                         value: holding.value.money(holding.stock.currency),
                                         isAccent: index.isMultiple(of: 2))
                            }
                        }
                    }
                }
            case .watchlist:
                if watchlist.isEmpty {
                    Text("Tap the star on any stock to follow it here. Find stocks in Markets.")
                        .font(.inter(12))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(watchlist.enumerated()), id: \.element.ticker) { index, stock in
                            NavigationLink(value: stock) {
                                StockRow(stock: stock, subtitle: stock.exchange,
                                         value: stock.price?.money(stock.currency) ?? "—",
                                         isAccent: index.isMultiple(of: 2))
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func emptyState(_ message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.inter(13))
                .foregroundStyle(Palette.muted)
            PrimaryButton(title: button, action: action)
        }
    }
}

private struct ActionTile: View {
    let symbol: String
    let title: String
    let detail: String
    let background: Color
    let foreground: Color
    /// Width share out of the 390pt mockup.
    let span: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(symbol)
                Spacer(minLength: 8)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.serif(27, relativeTo: .title))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.inter(8, weight: .medium, relativeTo: .caption2))
                }
            }
            .foregroundStyle(foreground)
            .padding(.top, 16)
            .padding(.bottom, 15)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 134)
            .background(background)
            .contentShape(.rect)
        }
        .containerRelativeFrame(.horizontal, count: 390, span: span, spacing: 0)
    }
}

/// Row for a held or watched stock.
struct StockRow: View {
    let stock: Stock
    let subtitle: String
    let value: String
    let isAccent: Bool

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                TickerMark(ticker: stock.ticker, isAccent: isAccent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(stock.displayName)
                        .font(.inter(13, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: 136, alignment: .leading)
                Spacer(minLength: 0)
                Sparkline(points: stock.sortedHistory)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(value)
                        .font(.inter(12, weight: .semibold, relativeTo: .callout))
                    if let change = stock.dayChangePercent {
                        Text(change.signedPercent())
                            .font(.inter(10, relativeTo: .caption))
                            .foregroundStyle(change >= 0 ? Palette.gain : Palette.loss)
                    } else {
                        Text("no quote yet")
                            .font(.inter(10, relativeTo: .caption))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .trailing)
            }
            .frame(height: 44)
            Rectangle().fill(Palette.divider).frame(height: 1)
        }
        .padding(.bottom, 10)
        .foregroundStyle(Palette.ink)
        .contentShape(.rect)
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    static let addButtonOverhang: CGFloat = 17

    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.markets)
            Color.clear.frame(width: 72)
            item(.plans)
            item(.me)
        }
        .frame(height: 65)
        .background { Palette.ink.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Button(action: onAdd) {
                Image("add-investment")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New practice order")
            .offset(y: -Self.addButtonOverhang)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button { selection = tab } label: {
            VStack(spacing: 8) {
                Image(tab.icon)
                Text(tab.title)
                    .font(.inter(8, weight: .medium, relativeTo: .caption2))
            }
            .foregroundStyle(isSelected ? Palette.ink : Palette.muted)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { (isSelected ? Palette.lime : Palette.ink).ignoresSafeArea(edges: .bottom) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
