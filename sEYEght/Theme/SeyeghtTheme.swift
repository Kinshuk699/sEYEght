//
//  SeyeghtTheme.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Design system constants matching approved mockups (soft gold + white on black)
enum SeyeghtTheme {
    // MARK: - Colors
    static let background = Color.black                         // #000000
    static let primaryText = Color.white                        // #FFFFFF
    static let secondaryText = Color(hex: "A0A0A0")            // Light gray
    static let accent = Color(hex: "E8D5A3")                   // Muted gold
    static let cardBackground = Color(hex: "1C1C1E")           // Dark gray cards
    static let success = Color(hex: "34C759")                  // Green checkmark
    static let buttonBackground = Color.white                   // White buttons
    static let buttonText = Color.black                         // Black text on buttons

    // MARK: - Fonts
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
    static let title = Font.system(size: 28, weight: .bold, design: .default)
    static let body = Font.system(size: 22, weight: .regular, design: .default)
    static let bodyBold = Font.system(size: 22, weight: .bold, design: .default)
    static let caption = Font.system(size: 18, weight: .regular, design: .default)
    static let sectionHeader = Font.system(size: 16, weight: .bold, design: .default)

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
