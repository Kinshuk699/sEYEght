//
//  HapticButton.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import AVFoundation

/// Blind-first button:
///   - Single tap → vibrates + speaks the label aloud
///   - Double tap → vibrates + executes the action
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
        Text(title)
            .font(SeyeghtTheme.bodyBold)
            .foregroundColor(isEnabled ? SeyeghtTheme.buttonText : SeyeghtTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: SeyeghtTheme.buttonHeight)
            .background(isEnabled ? SeyeghtTheme.buttonBackground : SeyeghtTheme.cardBackground)
            .cornerRadius(SeyeghtTheme.cardCornerRadius)
            .accessibilityLabel(title)
            .accessibilityHint(isEnabled ? "Double tap to \(title.lowercased())" : "Button disabled")
            .onTapGesture(count: 2) {
                guard isEnabled else { return }
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                Narrator.shared.stop()
                print("[HapticButton] Double-tap executed: \(title)")
                action()
            }
            .onTapGesture(count: 1) {
                guard isEnabled else { return }
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                Narrator.shared.speak(title)
                print("[HapticButton] Single-tap read: \(title)")
            }
    }
}
