//
//  HapticButton.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Reusable button that fires UIImpactFeedbackGenerator on every tap.
/// Used globally across all screens per the accessibility design rule.
struct HapticButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button {
            if isEnabled {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                print("[HapticButton] Tapped: \(title)")
                action()
            }
        } label: {
            Text(title)
                .font(SeyeghtTheme.bodyBold)
                .foregroundColor(isEnabled ? SeyeghtTheme.buttonText : SeyeghtTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: SeyeghtTheme.buttonHeight)
                .background(isEnabled ? SeyeghtTheme.buttonBackground : SeyeghtTheme.cardBackground)
                .cornerRadius(SeyeghtTheme.cardCornerRadius)
                .accessibilityLabel(title)
                .accessibilityHint(isEnabled ? "Double tap to \(title.lowercased())" : "Button disabled")
        }
        .disabled(!isEnabled)
    }
}
