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
                    print("[PermissionsIntroStepView] Back tapped")
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

            Text("Let's Get\nStarted")
                .font(SeyeghtTheme.largeTitle)
                .foregroundColor(SeyeghtTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Text("We'll ask for a few permissions next — Camera, Location, and Microphone.")
                .font(SeyeghtTheme.body)
                .foregroundColor(SeyeghtTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .accessibilityHidden(true)
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
                            .accessibilityLabel(item.label)
                        Spacer()
                    }
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
    }
}
