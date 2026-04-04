//
//  PermissionsIntroStepView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// Onboarding Step 3: Preview of permissions to be requested.
struct PermissionsIntroStepView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    private let permissionItems: [(icon: String, label: String)] = [
        ("camera.fill", "Camera for object recognition"),
        ("location.fill", "Location for spatial awareness"),
        ("mic.fill", "Microphone for voice commands")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    Narrator.shared.stop()
                    print("[PermissionsIntroStepView] Back tapped")
                    onBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(SeyeghtTheme.primaryText)
                }
                .readable("Go back")
                Spacer()
            }
            .padding(.top, 16)

            Text("Let's Get\nStarted")
                .font(SeyeghtTheme.largeTitle)
                .foregroundColor(SeyeghtTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .readable("Let's Get Started")
                .padding(.top, 24)
                .padding(.bottom, 16)

            Text("We'll ask for a few permissions next — Camera, Location, and Microphone.")
                .font(SeyeghtTheme.body)
                .foregroundColor(SeyeghtTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readable("We'll ask for a few permissions next. Camera, Location, and Microphone.")
                .padding(.bottom, 32)

            HStack(spacing: 16) {
                ForEach(permissionItems, id: \.label) { item in
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(SeyeghtTheme.cardBackground)
                            .frame(width: 80, height: 80)
                        Image(systemName: item.icon)
                            .font(.system(size: 28))
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                    .readable(item.label)
                }
            }
            .padding(.bottom, 32)

            VStack(spacing: 20) {
                ForEach(permissionItems, id: \.label) { item in
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(SeyeghtTheme.accent)
                            .frame(width: 3, height: 40)
                            .accessibilityHidden(true)
                        Text(item.label)
                            .font(SeyeghtTheme.body)
                            .foregroundColor(SeyeghtTheme.primaryText)
                        Spacer()
                    }
                    .readable(item.label)
                }
            }

            Spacer()

            HapticButton("Continue") {
                print("[PermissionsIntroStepView] Continue tapped")
                onContinue()
            }
        }
        .padding(.horizontal, SeyeghtTheme.horizontalPadding)
        .background(SeyeghtTheme.background)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Narrator.shared.speak("Step 3. Let's get started. We'll ask for Camera, Location, Microphone, and Speech Recognition permissions next. Tap Continue at the bottom.")
            }
        }
        .onDisappear {
            Narrator.shared.stop()
        }
    }
}
