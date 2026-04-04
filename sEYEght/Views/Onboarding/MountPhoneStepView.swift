//
//  MountPhoneStepView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Onboarding Step 2: Instructions to mount phone on chest.
struct MountPhoneStepView: View {
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    print("[MountPhoneStepView] Back tapped")
                    onBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(SeyeghtTheme.primaryText)
                }
                .accessibilityLabel("Go back")
                .accessibilityHint("Returns to the previous step")
                Spacer()
            }
            .padding(.top, 16)

            Text("Mount Your\nPhone")
                .font(SeyeghtTheme.largeTitle)
                .foregroundColor(SeyeghtTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Text("Attach your iPhone to your chest using a lanyard or clip. The camera should face forward.")
                .font(SeyeghtTheme.body)
                .foregroundColor(SeyeghtTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Attach your iPhone to your chest using a lanyard or clip. The camera should face forward.")

            Spacer()

            // Chest mount illustration
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(SeyeghtTheme.cardBackground)
                    .frame(width: 200, height: 240)
                VStack(spacing: 12) {
                    Circle()
                        .stroke(SeyeghtTheme.secondaryText, lineWidth: 2)
                        .frame(width: 40, height: 40)
                    ZStack {
                        RoundedRectangle(cornerRadius: 40)
                            .stroke(SeyeghtTheme.secondaryText, lineWidth: 2)
                            .frame(width: 120, height: 100)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SeyeghtTheme.background)
                            .frame(width: 40, height: 60)
                            .overlay(
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(SeyeghtTheme.accent)
                            )
                    }
                }
            }
            .accessibilityLabel("Illustration showing phone mounted on chest with camera facing forward")

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(SeyeghtTheme.accent)
                Text("Voice guidance is active")
                    .font(SeyeghtTheme.caption)
                    .foregroundColor(SeyeghtTheme.secondaryText)
            }
            .accessibilityLabel("Voice guidance is active")
            .padding(.bottom, 16)

            HapticButton("Next") {
                print("[MountPhoneStepView] Next tapped")
                onNext()
            }
        }
        .padding(.horizontal, SeyeghtTheme.horizontalPadding)
        .background(SeyeghtTheme.background)
    }
}
