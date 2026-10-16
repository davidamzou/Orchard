//
//  SettingsView.swift
//  Orchard
//

import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(MarketData.self) private var marketData
    @Environment(\.modelContext) private var context
    @AppStorage("hasOnboarded") private var hasOnboarded = true

    @State private var key = ""
    @State private var isChecking = false
    @State private var keyMessage: String?
    @State private var keyIsValid = false
    @State private var isConfirmingErase = false
    @State private var isConfirmingReset = false
    @State private var resetAmount = Portfolio.defaultStartingCash
    @AppStorage(Portfolio.startingCashKey) private var startingCash = Portfolio.defaultStartingCash

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Me")
                    .padding(.top, 8)
                practiceSection
                apiKeySection
                dataSection
                about
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .foregroundStyle(Palette.ink)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Palette.paper)
        .buttonStyle(.plain)
        .confirmationDialog("Start over with \(resetAmount.money(decimals: 0)) of practice money? Your trades and history will be cleared.",
                            isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset practice portfolio", role: .destructive, action: resetPortfolio)
        }
        .onAppear { resetAmount = startingCash }
        .confirmationDialog("Erase every trade, plan and price Orchard has recorded?",
                            isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button("Erase all data", role: .destructive, action: eraseAll)
        }
    }

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("PRACTICE MONEY")
            Text("Orchard is a simulator. You started with \(startingCash.money(decimals: 0)) of virtual cash; no real money is ever used.")
                .font(.inter(12))
                .foregroundStyle(Palette.muted)
            Picker("Starting cash", selection: $resetAmount) {
                ForEach(Portfolio.startingCashOptions, id: \.self) { Text($0.compactMoney).tag($0) }
            }
            .pickerStyle(.segmented)
            Button { isConfirmingReset = true } label: {
                row("Start over with \(resetAmount.money(decimals: 0))")
            }
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("LIVE PRICES")
            HStack(spacing: 8) {
                Circle()
                    .fill(marketData.hasKey ? Palette.gain : Palette.loss)
                    .frame(width: 8, height: 8)
                Text(!marketData.hasKey ? "No API key yet: prices won't update"
                     : marketData.hasSavedKey ? "Connected to Finnhub with your key"
                     : "Connected to Finnhub with the built-in key")
                    .font(.inter(13, weight: .medium))
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(marketData.hasHistoryKey && marketData.historyError == nil ? Palette.gain : Palette.loss)
                    .frame(width: 8, height: 8)
                Text(marketData.historyError
                     ?? (marketData.hasHistoryKey ? "Price history from Tiingo" : "No Tiingo key: charts use Orchard's own records"))
                    .font(.inter(13, weight: .medium))
            }
            Text("Orchard gets prices from Finnhub. Create a free key at finnhub.io, then paste it here. It's stored in your device's keychain.")
                .font(.inter(12))
                .foregroundStyle(Palette.muted)
            Link(destination: URL(string: "https://finnhub.io/register")!) {
                Text("Get a free key at finnhub.io ↗")
                    .font(.inter(12, weight: .medium))
                    .underline()
            }
            SecureField(marketData.hasSavedKey ? "Replace API key" : "Paste your own API key", text: $key)
                .font(.inter(14))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(Rectangle().strokeBorder(Palette.ink))
            if let keyMessage {
                Text(keyMessage)
                    .font(.inter(11))
                    .foregroundStyle(keyIsValid ? Palette.gain : Palette.loss)
            }
            HStack(spacing: 0) {
                Button(action: saveKey) {
                    HStack {
                        if isChecking { ProgressView().controlSize(.small).tint(Palette.lime) }
                        Text(isChecking ? "Checking…" : "Save key")
                    }
                    .font(.inter(12, weight: .medium))
                    .foregroundStyle(Palette.lime)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.ink)
                    .contentShape(.rect)
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
                if marketData.hasSavedKey {
                    Button {
                        marketData.setAPIKey(nil)
                        keyMessage = "Your key was removed."
                        keyIsValid = false
                    } label: {
                        Text("Remove key")
                            .font(.inter(12, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.lavender)
                            .contentShape(.rect)
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("YOUR DATA")
            Text("Your practice trades, plans and price history stay on this device. Nothing is sent anywhere except the tickers you look up, to Finnhub.")
                .font(.inter(12))
                .foregroundStyle(Palette.muted)
            Button { hasOnboarded = false } label: {
                row("Show the welcome screen again")
            }
            Button { isConfirmingErase = true } label: {
                row("Erase all data", color: Palette.loss)
            }
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("ABOUT")
            Text("Orchard is for learning only. Practice results don't predict real returns, and nothing here is financial advice. Prices come from Finnhub and cover US stocks and ETFs.")
                .font(.inter(11))
                .foregroundStyle(Palette.muted)
        }
    }

    private func row(_ title: String, color: Color = Palette.ink) -> some View {
        HStack {
            Text(title).font(.inter(13, weight: .medium)).foregroundStyle(color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Palette.muted)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.divider).frame(height: 1) }
        .contentShape(.rect)
    }

    private func saveKey() {
        let candidate = key
        isChecking = true
        Task {
            let error = await marketData.validate(key: candidate)
            isChecking = false
            if let error {
                keyMessage = error
                keyIsValid = false
            } else {
                marketData.setAPIKey(candidate)
                key = ""
                keyMessage = "Key saved. Prices are updating."
                keyIsValid = true
                await marketData.refreshAll(in: context)
            }
        }
    }

    private func resetPortfolio() {
        try? context.delete(model: Trade.self)
        try? context.delete(model: PortfolioSnapshot.self)
        for plan in (try? context.fetch(FetchDescriptor<AutopilotPlan>())) ?? [] {
            plan.lastRun = .now
        }
        try? context.save()
        startingCash = resetAmount
    }

    private func eraseAll() {
        try? context.delete(model: Trade.self)
        try? context.delete(model: PricePoint.self)
        try? context.delete(model: PortfolioSnapshot.self)
        try? context.delete(model: AutopilotPlan.self)
        try? context.delete(model: Stock.self)
        try? context.save()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

