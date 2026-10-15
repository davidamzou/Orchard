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

    var body: some View {
        if hasOnboarded {
            DashboardView()
        } else {
            WelcomeView { hasOnboarded = true }
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
        .modelContainer(for: [Stock.self, Trade.self, PricePoint.self, PortfolioSnapshot.self, AutopilotPlan.self], inMemory: true)
}
