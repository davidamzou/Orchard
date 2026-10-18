//
//  Theme.swift
//  Orchard
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Orchard palette, taken from the Figma mockups.
enum Palette {
    // Welcome
    static let welcomeBackground = Color(hex: 0xCFC2F0)
    static let welcomeInk = Color(hex: 0x233515)
    static let welcomeLime = Color(hex: 0xD9F57A)
    static let welcomeMuted = Color(hex: 0x615970)
    static let marketUp = Color(hex: 0x576A2D)
    static let marketDown = Color(hex: 0xA76679)

    // App
    static let paper = Color(hex: 0xF6F5EF)
    static let ink = Color(hex: 0x263C30)
    static let deepInk = Color(hex: 0x192A21)
    static let forest = Color(hex: 0x294735)
    static let lime = Color(hex: 0xE1F77B)
    static let limeBorder = Color(hex: 0xB8CA68)
    static let lavender = Color(hex: 0xCEC2F0)
    static let muted = Color(hex: 0x9B9E94)
    static let faint = Color(hex: 0xB4B6AD)
    static let gain = Color(hex: 0x8AA58A)
    static let divider = Color(hex: 0xEAE9E2)
    static let loss = Color(hex: 0xA76679)
}

extension Font {
    /// Instrument Serif, used for display type.
    static func serif(_ size: CGFloat, italic: Bool = false, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", size: size, relativeTo: style)
    }

    /// Inter (variable), used for UI text.
    static func inter(_ size: CGFloat, weight: Weight = .regular, relativeTo style: TextStyle = .body) -> Font {
        .custom("Inter", size: size, relativeTo: style).weight(weight)
    }
}
