//
//  OrchardApp.swift
//  Orchard
//
//  Created by David Amouzou on 15/10/2026.
//

import SwiftData
import SwiftUI

@main
struct OrchardApp: App {
    @State private var marketData = MarketData()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(marketData)
                .environment(\.locale, .app)
        }
        .modelContainer(for: [Stock.self, Trade.self, PricePoint.self, DailyClose.self, PortfolioSnapshot.self, AutopilotPlan.self])
    }
}
