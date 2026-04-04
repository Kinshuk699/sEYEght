//
//  WelcomeStepView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Onboarding Step 1: Welcome screen with app logo and tagline.
struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(SeyeghtTheme.cardBackground)
                    .frame(width: 160, height: 160)
                Image(systemName: "eye.fill")
                    .font(.system(size: 64))
                    .foregroundColor(SeyeghtTheme.accent)
            }
            .readable("Seyeght app icon")
            .padding(.bottom, 32)

            Text("Welcome to\nSeyeght")
                .font(SeyeghtTheme.largeTitle)
                .foregroundColor(SeyeghtTheme.primaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readable("Welcome to Seyeght")
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)

            Text("GPS. LiDAR. AI Vision. All in one.")
                .font(SeyeghtTheme.body)
                .foregroundColor(SeyeghtTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readable("GPS, LiDAR, AI Vision, all in one")

            Spacer()

            HStack(spacing: 8) {
                Circle().fill(SeyeghtTheme.primaryText).frame(width: 8, height: 8)
                Circle().fill(SeyeghtTheme.secondaryText.opacity(0.4)).frame(width: 8, height: 8)
                Circle().fill(SeyeghtTheme.secondaryText.opacity(0.4)).frame(width: 8, height: 8)
            }
            .accessibilityHidden(true)
            .padding(.bottom, 24)

            HapticButton("Next") {
                print("[WelcomeStepView] Next tapped")
                onNext()
            }
            .padding(.bottom, 8)

            Text("STEP 1 OF 3")
                .font(SeyeghtTheme.caption)
                .foregroundColor(SeyeghtTheme.secondaryText)
                .readable("Step 1 of 3")
        }
        .padding(.horizontal, SeyeghtTheme.horizontalPadding)
        .background(SeyeghtTheme.background)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Narrator.shared.speak("Welcome to Seyeght. GPS, LiDAR, AI Vision, all in one. Tap the Next button at the bottom to continue. Step 1 of 3.")
            }
        }
        .onDisappear {
            Narrator.shared.stop()
        }
    }
}
