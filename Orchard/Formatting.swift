//
//  Formatting.swift
//  Orchard
//

import Foundation

extension Locale {
    /// Amounts are shown in US format to match the English copy, whatever the device region.
    static let app = Locale(identifier: "en_US")
}

extension Double {
    func money(_ currency: String = "USD", decimals: Int = 2) -> String {
        formatted(.currency(code: currency).precision(.fractionLength(decimals)).locale(.app))
    }

    var currency: String { money() }

    /// `38.71` → "38.7" with one digit, always with a dot decimal separator.
    func decimal(_ digits: Int) -> String {
        formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(.app))
    }

    /// `1.32` → "+1.32%".
    func signedPercent(_ digits: Int = 2) -> String {
        (self >= 0 ? "+" : "−") + abs(self).decimal(digits) + "%"
    }

    /// Market cap and volume come in millions: `3_470_000` → "3.47T".
    var compactMillions: String {
        (self * 1_000_000).formatted(.number.notation(.compactName).precision(.fractionLength(0...2)).locale(.app))
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case day = "1D", week = "1W", month = "1M", year = "1Y", fiveYears = "5Y"
    var id: Self { self }

    var start: Date {
        let calendar = Calendar.current
        switch self {
        case .day: return calendar.date(byAdding: .day, value: -1, to: .now)!
        case .week: return calendar.date(byAdding: .day, value: -7, to: .now)!
        case .month: return calendar.date(byAdding: .month, value: -1, to: .now)!
        case .year: return calendar.date(byAdding: .year, value: -1, to: .now)!
        case .fiveYears: return calendar.date(byAdding: .year, value: -5, to: .now)!
        }
    }
}

extension Double {
    /// `18_400` → "$18.4k", `950` → "$950".
    var compactMoney: String {
        let number: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1)).locale(.app)) }
        switch abs(self) {
        case 1_000_000...: return "$\(number(self / 1_000_000))M"
        case 1_000...: return "$\(number(self / 1_000))k"
        default: return "$\(number(self))"
        }
    }
}

enum Projection {
    /// Value after `years` of monthly contributions, compounded monthly.
    static func futureValue(initial: Double = 0, monthly: Double, annualRate: Double, years: Int) -> Double {
        let months = Double(years * 12)
        let rate = annualRate / 100 / 12
        guard rate > 0 else { return initial + monthly * months }
        let growth = pow(1 + rate, months)
        return initial * growth + monthly * (growth - 1) / rate
    }
}
