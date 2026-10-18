//
//  WelcomeView.swift
//  Orchard
//

import SwiftUI

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 8)
                marketStrip
                    .padding(.top, 35)
                headline
                    .padding(.top, 45)
                Text("Practice investing with $10,000 of virtual money. Real market prices, zero real risk.")
                    .font(.inter(16.4))
                    .lineSpacing(3)
                    .padding(.top, 24)
                    .padding(.trailing, 8)
                GrowingOrchard()
                    .overlay(alignment: .topLeading) { growthAssumption.padding(.top, 13) }
                    .padding(.top, 8)
                projections
                    .padding(.top, 19)
                startButton
                    .padding(.top, 36)
                Text("A simulator for learning · No real money is ever used")
                    .font(.inter(12))
                    .foregroundStyle(Palette.welcomeMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
            .foregroundStyle(Palette.welcomeInk)
            .padding(.horizontal, 23)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.welcomeBackground)
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            Text("Orchard")
                .font(.serif(29, relativeTo: .title))
            Spacer()
        }
        .frame(height: 34)
    }

    private var marketStrip: some View {
        HStack(spacing: 12) {
            ForEach(["VIRTUAL CASH", "LIVE PRICES", "NO RISK", "AUTOPILOT"], id: \.self) { feature in
                HStack(spacing: 5) {
                    Text("↗").foregroundStyle(Palette.marketUp)
                    Text(feature)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.welcomeMuted)
                }
            }
        }
        .font(.inter(8.7, relativeTo: .caption2))
        .lineLimit(1)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Small sums,")
                .font(.serif(65))
                .frame(height: 61)
            Text("long roots.")
                .font(.serif(65, italic: true))
                .padding(.horizontal, 2)
                .frame(height: 62)
                .background(Palette.welcomeLime)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var growthAssumption: some View {
        HStack(spacing: 8) {
            Text("↗").font(.inter(13))
            Text("$150/MO · 7%").font(.inter(10, weight: .medium, relativeTo: .caption2))
        }
        .foregroundStyle(Palette.welcomeLime)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: 128, alignment: .leading)
        .background(Palette.welcomeInk, in: .rect(cornerRadius: 2))
    }

    private var projections: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach([1, 5, 10], id: \.self) { year in
                VStack(alignment: .leading, spacing: 3) {
                    Text("YEAR \(year, format: .number.precision(.integerLength(2)))")
                        .font(.inter(9.5, weight: .medium, relativeTo: .caption2))
                        .foregroundStyle(Palette.welcomeMuted)
                    Text(Projection.futureValue(monthly: 150, annualRate: 7, years: year).compactMoney)
                        .font(.serif(22, relativeTo: .title2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var startButton: some View {
        Button(action: onStart) {
            HStack {
                Text("Start practicing")
                    .font(.inter(16, weight: .medium))
                Spacer()
                Image("forward-arrow")
            }
            .foregroundStyle(Palette.welcomeLime)
            .padding(.horizontal, 21)
            .frame(height: 59)
            .background(Palette.welcomeInk)
            .contentShape(.rect)
        }
    }
}

/// Decorative illustration: a sapling growing into a mature tree along the 7% curve.
private struct GrowingOrchard: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            sprite("growth-trajectory", x: 18.35, y: 11.26, width: 297, height: 178.5)
            sprite("ground-shoots", x: 42.37, y: 169.87, width: 264.21, height: 20.41)
            sprite("mature-canopy", x: 185, y: 22, width: 149, height: 137)
            sprite("fruit-0", x: 236, y: 126, width: 11, height: 11)
            sprite("fruit-1", x: 278, y: 78, width: 16, height: 16)
            sprite("fruit-2", x: 218, y: 75, width: 12, height: 12)
            sprite("fruit-2", x: 247, y: 38, width: 12, height: 12)
            trunk(x: 262, y: 153, height: 35)
            sprite("canopy", x: 84, y: 48, width: 100, height: 100)
            sprite("fruit-3", x: 95, y: 102, width: 10, height: 10)
            sprite("fruit-4", x: 151, y: 89, width: 12, height: 12)
            sprite("fruit-5", x: 119, y: 67, width: 13, height: 13)
            trunk(x: 133, y: 148, height: 40)
            Image("leaf-0").rotationEffect(.degrees(28)).position(x: 45.28, y: 144.44)
            Image("leaf-1").rotationEffect(.degrees(-21)).position(x: 61.59, y: 155.9)
            Image("leaf-2").rotationEffect(.degrees(15)).position(x: 22.36, y: 158.42)
            sprite("sapling", x: 8.64, y: 119.49, width: 77.67, height: 69.51)
            sprite("ground", x: 0, y: 186.5, width: 344, height: 1)
        }
        .frame(width: 344, height: 189, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func sprite(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Image(name).position(x: x + width / 2, y: y + height / 2)
    }

    private func trunk(x: CGFloat, y: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.welcomeInk)
            .frame(width: 1.5, height: height)
            .position(x: x + 0.75, y: y + height / 2)
    }
}

#Preview {
    WelcomeView {}
}
