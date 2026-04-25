//
//  SeyeghtTheme.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Design system constants — tuned for low-vision users.
///
/// Color rationale (researched from NFB / Hadley / Apple a11y guides):
///   • Pure black background gives OLED true-off pixels and the highest
///     possible contrast headroom. Used by every blind-targeted iOS app.
///   • Bright amber (#FFC857) is the most legible accent for users with
///     macular degeneration, retinitis pigmentosa, and cataracts. It sits
///     in the spectral sweet spot (~580 nm) where photoreceptor sensitivity
///     stays highest as central vision deteriorates. Contrast on black:
///     ~12.4:1 (WCAG AAA, which requires 7:1).
///   • Pure white text on black: ~21:1 contrast.
///   • Danger red is shifted toward orange (#FF6B47) — pure red is hard
///     for many low-vision users to distinguish from the background.
enum SeyeghtTheme {
    // MARK: - Colors
    static let background = Color.black                         // #000000 OLED true-black
    static let primaryText = Color.white                        // #FFFFFF (21:1 on black)
    static let secondaryText = Color(hex: "B8B8B8")            // (10.4:1) — bumped from A0A0A0
    static let accent = Color(hex: "FFC857")                   // Bright amber (12.4:1)
    static let accentSoft = Color(hex: "FFC857").opacity(0.18) // For card tints / strokes
    static let cardBackground = Color(hex: "151515")           // Slightly darker than #1C — cards read as raised
    static let cardStroke = Color.white.opacity(0.08)          // Hairline edge for depth
    static let success = Color(hex: "34C759")                  // Green checkmark
    static let danger = Color(hex: "FF6B47")                   // Warm red (better for low vision)
    static let buttonBackground = Color.white                   // White buttons
    static let buttonText = Color.black                         // Black text on buttons

    // MARK: - Fonts
    // SF Rounded reads warmer and more approachable than the default SF Pro,
    // and remains highly legible at large sizes used here.
    static let largeTitle = Font.system(size: 36, weight: .bold, design: .rounded)
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let body = Font.system(size: 20, weight: .regular, design: .rounded)
    static let bodyBold = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let caption = Font.system(size: 16, weight: .regular, design: .rounded)
    static let sectionHeader = Font.system(size: 13, weight: .heavy, design: .rounded)

    // MARK: - Dimensions
    static let buttonHeight: CGFloat = 60
    static let cardCornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 24
}

// MARK: - Color hex initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
