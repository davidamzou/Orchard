//
//  APIKeysView.swift
//  Orchard
//

import SwiftData
import SwiftUI

/// The two market-data services the user connects with their own free keys.
enum DataProvider: CaseIterable, Identifiable {
    case finnhub, tiingo
    var id: Self { self }

    var label: String {
        switch self {
        case .finnhub: "FINNHUB API KEY · LIVE PRICES"
        case .tiingo: "TIINGO TOKEN · PRICE HISTORY"
        }
    }

    var purpose: String {
        switch self {
        case .finnhub: "Required. Live quotes and search, so you can buy and sell at real prices."
        case .tiingo: "Optional. Past prices for the charts. Without it, charts only show what Orchard records."
        }
    }

    var signUp: (title: String, url: URL) {
        switch self {
        case .finnhub: ("Get a free key at finnhub.io ↗", URL(string: "https://finnhub.io/register")!)
        case .tiingo: ("Get a free token at tiingo.com ↗", URL(string: "https://www.tiingo.com/account/api/token")!)
        }
    }
}

/// Status, sign-up link and entry field for one provider's key.
struct APIKeyField: View {
    let provider: DataProvider

    @Environment(MarketData.self) private var marketData
    @Environment(\.modelContext) private var context
    @State private var key = ""
    @State private var isChecking = false
    @State private var message: String?
    @State private var isValid = false

    private var isConnected: Bool {
        switch provider {
        case .finnhub: marketData.hasKey
        case .tiingo: marketData.hasHistoryKey
        }
    }

    private var status: String {
        switch provider {
        case .finnhub:
            return isConnected ? "Connected" : "Not connected: prices won't load"
        case .tiingo:
            if let error = marketData.historyError { return error }
            return isConnected ? "Connected" : "Not connected"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(provider.label)
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected && (provider == .finnhub || marketData.historyError == nil) ? Palette.gain : Palette.loss)
                    .frame(width: 8, height: 8)
                Text(status).font(.inter(13, weight: .medium))
            }
            Text(provider.purpose)
                .font(.inter(12))
                .foregroundStyle(Palette.muted)
            Link(destination: provider.signUp.url) {
                Text(provider.signUp.title)
                    .font(.inter(12, weight: .medium))
                    .underline()
            }
            SecureField(isConnected ? "Paste a new key to replace it" : "Paste your key", text: $key)
                .font(.inter(14))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(Rectangle().strokeBorder(Palette.ink))
            if let message {
                Text(message)
                    .font(.inter(11))
                    .foregroundStyle(isValid ? Palette.gain : Palette.loss)
            }
            HStack(spacing: 0) {
                Button(action: save) {
                    HStack {
                        if isChecking { ProgressView().controlSize(.small).tint(Palette.lime) }
                        Text(isChecking ? "Checking…" : "Save")
                    }
                    .font(.inter(12, weight: .medium))
                    .foregroundStyle(Palette.lime)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Palette.ink)
                    .contentShape(.rect)
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
                if isConnected {
                    Button(action: remove) {
                        Text("Remove")
                            .font(.inter(12, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Palette.lavender)
                            .contentShape(.rect)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.ink)
    }

    /// Checks the key with the provider before keeping it in the keychain.
    private func save() {
        let candidate = key
        isChecking = true
        Task {
            let error = switch provider {
            case .finnhub: await marketData.validate(key: candidate)
            case .tiingo: await marketData.validateHistory(key: candidate)
            }
            isChecking = false
            if let error {
                message = error
                isValid = false
                return
            }
            switch provider {
            case .finnhub: marketData.setAPIKey(candidate)
            case .tiingo: marketData.setHistoryKey(candidate)
            }
            key = ""
            message = "Saved in your keychain."
            isValid = true
            await marketData.refreshAll(in: context)
        }
    }

    private func remove() {
        switch provider {
        case .finnhub: marketData.setAPIKey(nil)
        case .tiingo: marketData.setHistoryKey(nil)
        }
        message = "Removed."
        isValid = false
    }
}

/// Shown at launch until a Finnhub key is saved: Orchard can't price trades without it.
struct ConnectDataView: View {
    var onContinue: () -> Void
    @Environment(MarketData.self) private var marketData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Connect prices",
                           subtitle: "Orchard uses real market prices from two free services. Create your own free keys and paste them below. They stay in this device's keychain.")
                    .padding(.top, 8)
                APIKeyField(provider: .finnhub)
                APIKeyField(provider: .tiingo)
                if marketData.hasKey {
                    PrimaryButton(title: "Start practicing", action: onContinue)
                } else {
                    Button("Skip for now", action: onContinue)
                        .font(.inter(13, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Palette.paper)
    }
}
