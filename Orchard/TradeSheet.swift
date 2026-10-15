//
//  TradeSheet.swift
//  Orchard
//

import SwiftData
import SwiftUI

/// Places a practice order: filled instantly at the live price, paid with virtual cash.
struct TradeSheet: View {
    let request: TradeRequest

    private enum Mode: String, CaseIterable, Identifiable {
        case amount = "Dollars", shares = "Shares"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(MarketData.self) private var marketData
    @AppStorage(Portfolio.startingCashKey) private var startingCash = Portfolio.defaultStartingCash
    @Query private var trades: [Trade]

    @State private var kind: Trade.Kind = .buy
    @State private var ticker = ""
    @State private var name = ""
    @State private var mode: Mode = .amount
    @State private var quantity: Double?
    @State private var price: Double?
    @State private var priceError: String?
    @State private var isPlacing = false
    @State private var results: [FinnhubClient.SearchResult] = []
    @FocusState private var isTickerFocused: Bool

    private var symbol: String { ticker.trimmingCharacters(in: .whitespaces).uppercased() }

    private var existingStock: Stock? {
        let symbol = symbol
        return try? context.fetch(FetchDescriptor<Stock>(predicate: #Predicate { $0.ticker == symbol })).first
    }

    private var cash: Double { Portfolio.cash(startingCash: startingCash, trades: trades) }
    private var heldShares: Double { existingStock?.position().shares ?? 0 }

    private var shares: Double {
        guard let quantity, quantity > 0 else { return 0 }
        switch mode {
        case .shares: return quantity
        case .amount: return price.map { quantity / $0 } ?? 0
        }
    }

    private var total: Double { shares * (price ?? 0) }

    private var validationMessage: String? {
        if symbol.isEmpty { return "Choose a stock or ETF." }
        if price == nil { return priceError ?? "Waiting for the live price…" }
        guard shares > 0 else { return mode == .amount ? "Enter an amount." : "Enter a number of shares." }
        switch kind {
        case .buy where total > cash + 0.005:
            return "You have \(cash.currency) of practice cash."
        case .sell where shares > heldShares + 1e-6:
            return heldShares > 0 ? "You hold \(heldShares.shareCount) shares." : "You don't own \(symbol) yet."
        default:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Order", selection: $kind) {
                        Text("Buy").tag(Trade.Kind.buy)
                        Text("Sell").tag(Trade.Kind.sell)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Ticker, e.g. AAPL or VOO", text: $ticker)
                        .focused($isTickerFocused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .onSubmit { isTickerFocused = false }
                    if isTickerFocused {
                        ForEach(results) { result in
                            Button { select(result) } label: {
                                HStack {
                                    Text(result.symbol).fontWeight(.semibold)
                                    Text(result.description).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    } else if !symbol.isEmpty {
                        LabeledContent(name.isEmpty ? "Live price" : name) {
                            if let price {
                                Text(price.currency).monospacedDigit()
                            } else if let priceError {
                                Text(priceError).foregroundStyle(Palette.loss).font(.footnote)
                            } else {
                                ProgressView()
                            }
                        }
                    }
                } header: {
                    Text("Stock or ETF")
                }

                Section {
                    Picker("Order by", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(mode == .amount ? "Amount" : "Shares") {
                        Group {
                            if mode == .amount {
                                TextField("$0", value: $quantity, format: .currency(code: "USD"))
                            } else {
                                TextField("0", value: $quantity, format: .number.precision(.fractionLength(0...4)))
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
                    }
                    Button(kind == .buy ? "Use all my cash" : "Sell everything") { fillMax() }
                        .disabled(price == nil || (kind == .sell && heldShares <= 0))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if shares > 0, price != nil {
                            Text("\(kind == .buy ? "Buy" : "Sell") \(shares.shareCount) shares for \(total.currency)")
                        }
                        Text(kind == .buy
                             ? "Practice cash available: \(cash.currency)"
                             : "Shares you hold: \(heldShares.shareCount)")
                    }
                }

                if let validationMessage, !symbol.isEmpty, quantity != nil {
                    Section {
                        Text(validationMessage).foregroundStyle(Palette.loss)
                    }
                }

                Section {
                    Text("Practice order: filled instantly at the latest price with virtual money. Outside market hours, that's the last close.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(kind == .buy ? "Practice buy" : "Practice sale")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kind == .buy ? "Buy" : "Sell", systemImage: "checkmark") {
                        Task { await place() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .disabled(validationMessage != nil || isPlacing)
                }
            }
            .task(id: ticker) { await searchTickers() }
            .task(id: isTickerFocused ? "" : symbol) { await loadPrice() }
        }
        .onAppear {
            kind = request.kind
            if let preset = request.ticker {
                ticker = preset
                name = existingStock?.name ?? ""
                if request.kind == .sell { mode = .shares }
            } else {
                isTickerFocused = true
            }
        }
    }

    private func select(_ result: FinnhubClient.SearchResult) {
        ticker = result.symbol
        name = result.description.capitalized
        results = []
        isTickerFocused = false
    }

    private func fillMax() {
        guard let price else { return }
        switch (kind, mode) {
        case (.buy, .amount): quantity = (cash * 100).rounded(.down) / 100
        case (.buy, .shares): quantity = ((cash / price) * 10_000).rounded(.down) / 10_000
        case (.sell, .amount): quantity = heldShares * price
        case (.sell, .shares): quantity = heldShares
        }
    }

    private func searchTickers() async {
        let query = ticker.trimmingCharacters(in: .whitespaces)
        guard isTickerFocused, !query.isEmpty else { results = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        results = Array(((try? await marketData.search(query)) ?? []).prefix(6))
    }

    private func loadPrice() async {
        price = nil
        priceError = nil
        guard !isTickerFocused, !symbol.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let stock = context.stock(ticker: symbol, name: name)
        do {
            price = try await marketData.livePrice(for: stock, in: context)
            if name.isEmpty { name = stock.name }
        } catch {
            priceError = error.localizedDescription
        }
    }

    /// Re-quotes right before filling so the order uses the freshest price.
    private func place() async {
        guard validationMessage == nil else { return }
        isPlacing = true
        defer { isPlacing = false }
        let stock = context.stock(ticker: symbol, name: name)
        let fillPrice = (try? await marketData.livePrice(for: stock, in: context)) ?? price ?? 0
        guard fillPrice > 0 else { return }
        var fillShares = mode == .shares ? (quantity ?? 0) : (quantity ?? 0) / fillPrice
        switch kind {
        case .buy: fillShares = min(fillShares, cash / fillPrice)
        case .sell: fillShares = min(fillShares, heldShares)
        }
        guard fillShares > 0 else { return }
        stock.trades.append(Trade(kind: kind, shares: fillShares, price: fillPrice, account: Portfolio.manualAccount))
        try? context.save()
        dismiss()
        await marketData.refreshAll(in: context)
    }
}

extension View {
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
