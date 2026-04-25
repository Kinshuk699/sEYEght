//
//  PermissionCard.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import AVFoundation

/// A single permission row: icon, name, description, and grant/check status.
/// Grant button uses blind-first pattern (tap to read, double-tap to grant) when
/// VoiceOver is OFF. When VoiceOver is ON, becomes a standard Button so VoiceOver
/// gestures activate it correctly.
struct PermissionCard: View {
    let iconName: String
    let title: String
    let description: String
    let isGranted: Bool
    let onGrant: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var grantPill: some View {
        Text("Grant")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(SeyeghtTheme.buttonText)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(SeyeghtTheme.buttonBackground)
            .cornerRadius(12)
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 28))
                .foregroundColor(SeyeghtTheme.accent)
                .frame(width: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SeyeghtTheme.bodyBold)
                    .foregroundColor(SeyeghtTheme.primaryText)
                Text(description)
                    .font(SeyeghtTheme.caption)
                    .foregroundColor(SeyeghtTheme.secondaryText)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(SeyeghtTheme.success)
                    .accessibilityLabel("\(title) granted")
            } else if voiceOverEnabled {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                    generator.impactOccurred()
                    Narrator.shared.stop()
                    onGrant()
                } label: {
                    grantPill
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Grant \(title)")
                .accessibilityHint("Activates \(title.lowercased()) permission")
            } else {
                grantPill
                    .onTapGesture(count: 2) {
                        let generator = UIImpactFeedbackGenerator(style: .heavy)
                        generator.impactOccurred()
                        Narrator.shared.stop()
                        onGrant()
                    }
                    .onTapGesture(count: 1) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        Narrator.shared.speak("Grant \(title)")
                    }
                    .accessibilityLabel("Grant \(title)")
                    .accessibilityHint("Double tap to grant \(title.lowercased()) permission")
            }
        }
        .padding(20)
        .background(SeyeghtTheme.cardBackground)
        .cornerRadius(SeyeghtTheme.cardCornerRadius)
        .readable("\(title). \(description). \(isGranted ? "Granted" : "Not yet granted, double tap Grant to allow")")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description). \(isGranted ? "Granted" : "Not yet granted")")
    }
}
