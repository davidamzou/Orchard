//
//  ContentView.swift
//  Orchard
//
//  Created by David Amouzou on 15/10/2026.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(MarketData.self) private var marketData
    /// Once shown, setup stays up until the user moves on, so both keys can be entered.
    @State private var isInSetup = false
    /// Set when the user leaves setup; asked again at the next launch if keys are missing.
    @State private var finishedSetup = false

    var body: some View {
        if !hasOnboarded {
            WelcomeView { hasOnboarded = true }
        } else if isInSetup || (!marketData.hasKey && !finishedSetup) {
            ConnectDataView {
                isInSetup = false
                finishedSetup = true
            }
            .onAppear { isInSetup = true }
        } else {
            DashboardView()
        }
    }
}

extension View {
    /// The mockups draw their own top chrome, so the system navigation bar stays hidden.
    func hidesNavigationBar() -> some View {
        #if os(iOS)
        toolbarVisibility(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden()
        #else
        self
        #endif
    }
}

#Preview {
    ContentView()
        .environment(MarketData())
        .modelContainer(for: [Stock.self, Trade.self, PricePoint.self, DailyClose.self, PortfolioSnapshot.self, AutopilotPlan.self], inMemory: true)
}
