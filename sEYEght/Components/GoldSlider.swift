//
//  GoldSlider.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Styled slider with gold accent track matching the design system.
struct GoldSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let lowLabel: String
    let highLabel: String
    var displayValue: String? = nil
    @State private var lastHapticValue: Double = -1

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(label)
                    .font(SeyeghtTheme.bodyBold)
                    .foregroundColor(SeyeghtTheme.primaryText)
                Spacer()
                if let display = displayValue {
                    Text(display)
                        .font(SeyeghtTheme.bodyBold)
                        .foregroundColor(SeyeghtTheme.accent)
                }
            }

            HStack(spacing: 12) {
                Text(lowLabel)
                    .font(SeyeghtTheme.caption)
                    .foregroundColor(SeyeghtTheme.secondaryText)
                Slider(value: $value, in: range)
                    .tint(SeyeghtTheme.accent)
                    .onChange(of: value) { _, newValue in
                        // Throttle haptics: only fire when value changes by at least 5% of range
                        let step = (range.upperBound - range.lowerBound) * 0.05
                        if abs(newValue - lastHapticValue) >= step {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            lastHapticValue = newValue
                        }
                    }
                Text(highLabel)
                    .font(SeyeghtTheme.caption)
                    .foregroundColor(SeyeghtTheme.secondaryText)
            }
        }
        .padding(20)
        .background(SeyeghtTheme.cardBackground)
        .cornerRadius(SeyeghtTheme.cardCornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), currently \(displayValue ?? String(format: "%.1f", value))")
        .accessibilityValue(String(format: "%.1f", value))
    }
}
