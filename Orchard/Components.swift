//
//  Components.swift
//  Orchard
//

import Charts
import SwiftData
import SwiftUI

/// Mini price line for list rows.
struct Sparkline: View {
    let points: [PricePoint]

    var body: some View {
        let recent = Array(points.suffix(30))
        let isUp = (recent.last?.price ?? 0) >= (recent.first?.price ?? 0)
        Chart(recent) { point in
            LineMark(x: .value("Date", point.date), y: .value("Price", point.price))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
        }
        .foregroundStyle(isUp ? Palette.gain : Palette.loss)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(width: 58, height: 26)
        .opacity(recent.count > 1 ? 1 : 0)
        .accessibilityHidden(true)
    }
}

/// Full-bleed area chart used on the dashboard and stock pages.
struct AreaLineChart: View {
    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let points: [Point]
    var fill: Color
    var line: Color
    var showsMarker = false
    var emptyMessage: String

    var body: some View {
        if points.count < 2 {
            Text(emptyMessage)
                .font(.inter(10, relativeTo: .caption))
                .foregroundStyle(line.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(alignment: .bottom) {
                    Rectangle().fill(fill).frame(height: 24)
                }
        } else {
            let low = points.map(\.value).min() ?? 0
            let high = points.map(\.value).max() ?? 1
            let padding = max((high - low) * 0.1, high * 0.002)
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Date", point.date),
                             yStart: .value("Base", low - padding * 3),
                             yEnd: .value("Value", point.value))
                        .foregroundStyle(fill)
                    LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .foregroundStyle(line)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
                if showsMarker, let last = points.last {
                    PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                        .symbol {
                            Circle()
                                .fill(.white)
                                .stroke(line, lineWidth: 1.2)
                                .frame(width: 10, height: 10)
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: (low - padding * 3)...(high + padding))
            .chartPlotStyle { $0.clipped(antialiased: true) }
            .accessibilityHidden(true)
        }
    }
}

/// Square ticker badge used in lists.
struct TickerMark: View {
    let ticker: String
    let isAccent: Bool

    var body: some View {
        Text(ticker)
            .font(.inter(ticker.count > 4 ? 8 : 10, weight: .semibold, relativeTo: .caption))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .foregroundStyle(isAccent ? Palette.lime : Palette.ink)
            .frame(width: 40, height: 42)
            .background(isAccent ? Palette.ink : Palette.lavender)
    }
}

/// Page title used by the secondary tabs, in the dashboard's brand style.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.serif(41, relativeTo: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.inter(12))
                    .foregroundStyle(Palette.muted)
            }
        }
        .foregroundStyle(Palette.ink)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small uppercase label above a section.
struct SectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.inter(9, weight: .medium, relativeTo: .caption2))
            .foregroundStyle(Palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Full-width dark button in the welcome screen's style.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.inter(15, weight: .medium))
                Spacer()
                Image("forward-arrow")
            }
            .foregroundStyle(Palette.lime)
            .padding(.horizontal, 21)
            .frame(height: 54)
            .background(Palette.ink)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension ModelContext {
    /// Returns the stock for `ticker`, creating it when it isn't followed yet.
    func stock(ticker: String, name: String = "") -> Stock {
        let symbol = ticker.uppercased()
        let existing = try? fetch(FetchDescriptor<Stock>(predicate: #Predicate { $0.ticker == symbol })).first
        if let existing {
            if existing.name.isEmpty, !name.isEmpty { existing.name = name }
            return existing
        }
        let stock = Stock(ticker: symbol, name: name)
        insert(stock)
        return stock
    }
}
