//
//  MarketsView.swift
//  Orchard
//

import SwiftData
import SwiftUI

/// Search any US stock or ETF and keep a watchlist.
struct MarketsView: View {
    @Environment(\.modelContext) private var context
    @Environment(MarketData.self) private var marketData
    @Query(filter: #Predicate<Stock> { $0.isWatched }, sort: \Stock.ticker) private var watchlist: [Stock]

    @State private var query = ""
    @State private var results: [FinnhubClient.SearchResult] = []
    @State private var searchError: String?
    @State private var isSearching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Markets", subtitle: "Search US stocks and ETFs, then star the ones to follow.")
                    .padding(.top, 8)

                searchField

                if !query.isEmpty {
                    searchResults
                } else {
                    watchlistSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .foregroundStyle(Palette.ink)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await marketData.refresh(watchlist, in: context) }
        .buttonStyle(.plain)
        .background(Palette.paper)
        .hidesNavigationBar()
        .task(id: query) { await search() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
            TextField("Company or ticker", text: $query)
                .font(.inter(14))
                .autocorrectionDisabled()
                .submitLabel(.search)
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .overlay(Rectangle().strokeBorder(Palette.ink))
    }

    @ViewBuilder
    private var searchResults: some View {
        if let searchError {
            Text(searchError)
                .font(.inter(12))
                .foregroundStyle(Palette.loss)
        } else if results.isEmpty, !isSearching {
            Text("No US stock or ETF matches “\(query)”.")
                .font(.inter(12))
                .foregroundStyle(Palette.muted)
        }
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                NavigationLink(value: StockLookup(ticker: result.symbol, name: result.description.capitalized)) {
                    HStack(spacing: 11) {
                        TickerMark(ticker: result.symbol, isAccent: index.isMultiple(of: 2))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.description.capitalized)
                                .font(.inter(13, weight: .medium))
                                .lineLimit(1)
                            Text(result.type.isEmpty ? result.symbol : "\(result.symbol) · \(result.type)")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Palette.divider).frame(height: 1)
                    }
                    .contentShape(.rect)
                }
            }
        }
    }

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("WATCHLIST")
            if watchlist.isEmpty {
                Text("Nothing here yet. Search a company above and tap its star.")
                    .font(.inter(12))
                    .foregroundStyle(Palette.muted)
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

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { results = []; searchError = nil; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = Array(try await marketData.search(term).prefix(15))
            searchError = nil
        } catch {
            results = []
            searchError = error.localizedDescription
        }
    }
}
