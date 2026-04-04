//
//  PermissionCard.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import AVFoundation

/// A single permission row: icon, name, description, and grant/check status.
/// Grant button uses blind-first pattern: first tap reads aloud, second tap grants.
struct PermissionCard: View {
    let iconName: String
    let title: String
    let description: String
    let isGranted: Bool
    let onGrant: () -> Void

    @State private var synth = AVSpeechSynthesizer()

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
            } else {
                Text("Grant")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SeyeghtTheme.buttonText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(SeyeghtTheme.buttonBackground)
                    .cornerRadius(12)
                    .onTapGesture(count: 2) {
                        let generator = UIImpactFeedbackGenerator(style: .heavy)
                        generator.impactOccurred()
                        synth.stopSpeaking(at: .immediate)
                        print("[PermissionCard] Grant confirmed: \(title)")
                        onGrant()
                    }
                    .onTapGesture(count: 1) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        let utterance = AVSpeechUtterance(string: "Grant \(title)")
                        utterance.rate = 0.5
                        utterance.volume = 0.9
                        synth.stopSpeaking(at: .immediate)
                        synth.speak(utterance)
                    }
                    .accessibilityLabel("Grant \(title)")
                    .accessibilityHint("Double tap to grant \(title.lowercased()) permission")
            }
        }
        .padding(20)
        .background(SeyeghtTheme.cardBackground)
        .cornerRadius(SeyeghtTheme.cardCornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description). \(isGranted ? "Granted" : "Not yet granted")")
    }
}
