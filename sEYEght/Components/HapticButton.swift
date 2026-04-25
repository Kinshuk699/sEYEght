//
//  HapticButton.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import AVFoundation

/// Blind-first button:
///   - VoiceOver ON: standard Button (VoiceOver focus + double-tap activate)
///   - VoiceOver OFF: Single tap → vibrates + speaks label; Double tap → executes action
struct HapticButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    private var labelView: some View {
        Text(title)
            .font(SeyeghtTheme.bodyBold)
            .foregroundColor(isEnabled ? SeyeghtTheme.buttonText : SeyeghtTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: SeyeghtTheme.buttonHeight)
            .background(isEnabled ? SeyeghtTheme.buttonBackground : SeyeghtTheme.cardBackground)
            .cornerRadius(SeyeghtTheme.cardCornerRadius)
    }

    var body: some View {
        Group {
            if voiceOverEnabled {
                Button {
                    guard isEnabled else { return }
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    Narrator.shared.stop()
                    action()
                } label: {
                    labelView
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            } else {
                labelView
                    .onTapGesture(count: 2) {
                        guard isEnabled else { return }
                        let generator = UIImpactFeedbackGenerator(style: .heavy)
                        generator.impactOccurred()
                        Narrator.shared.stop()
                        action()
                    }
                    .onTapGesture(count: 1) {
                        guard isEnabled else { return }
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.prepare()
                        generator.impactOccurred()
                        Narrator.shared.speak(title)
                    }
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? "Double tap to \(title.lowercased())" : "Button disabled")
    }
}
