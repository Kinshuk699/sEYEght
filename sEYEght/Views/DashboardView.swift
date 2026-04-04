//
//  DashboardView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// S-003: Main active dashboard. The user spends 99% of their time here.
struct DashboardView: View {
    @State private var navigateToSettings = false

    // Placeholder state — will be replaced with real managers in Phase 5
    @State private var currentDestination: String? = "Central Park"
    @State private var nextInstruction: String? = "In 200 feet, turn right on 5th Ave"
    @State private var isSeyeghtActive = true

    var body: some View {
        ZStack {
            SeyeghtTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SeyeghtTheme.accent)
                            .frame(width: 8, height: 8)
                        Text("Seyeght Active")
                            .font(SeyeghtTheme.caption)
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                    .accessibilityLabel("Seyeght is active")
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.horizontal, SeyeghtTheme.horizontalPadding)

                // Destination display
                if let destination = currentDestination {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(destination)
                            .font(SeyeghtTheme.title)
                            .foregroundColor(SeyeghtTheme.primaryText)
                            .accessibilityLabel("Destination: \(destination)")

                        if let instruction = nextInstruction {
                            Text(instruction)
                                .font(SeyeghtTheme.body)
                                .foregroundColor(SeyeghtTheme.secondaryText)
                                .accessibilityLabel("Next: \(instruction)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.horizontal, SeyeghtTheme.horizontalPadding)
                }

                Spacer()

                // Center mic icon + hint
                VStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(SeyeghtTheme.accent)
                    Text("Tap anywhere to describe scene")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                }
                .accessibilityLabel("Tap anywhere or say Hey Seyeght to describe scene")

                Spacer()

                // Bottom: settings gear
                HStack {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        print("[DashboardView] Settings tapped")
                        navigateToSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 24))
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Double tap to open settings")
                    Spacer()
                }
                .padding(.horizontal, SeyeghtTheme.horizontalPadding)
                .padding(.bottom, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            print("[DashboardView] Full-screen tap — triggering scene description")
            // TODO: Wire to VisionManager.captureAndAnalyze() in Phase 5
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingsView()
        }
    }
}
