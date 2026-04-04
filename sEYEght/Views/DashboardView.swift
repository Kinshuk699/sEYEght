//
//  DashboardView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// S-003: Main active dashboard. The user spends 99% of their time here.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(LiDARManager.self) private var lidarManager
    @Environment(HapticsManager.self) private var hapticsManager
    @Environment(SpeechManager.self) private var speechManager
    @Environment(VisionManager.self) private var visionManager
    @Environment(NavigationManager.self) private var navigationManager
    @Environment(SubscriptionManager.self) private var subscriptionManager

    @State private var navigateToSettings = false
    @State private var navigateToSubscription = false
    @State private var isAnalyzingScene = false

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

                // Destination display from NavigationManager
                if let destination = navigationManager.currentDestination {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(destination)
                            .font(SeyeghtTheme.title)
                            .foregroundColor(SeyeghtTheme.primaryText)
                            .accessibilityLabel("Destination: \(destination)")

                        if let instruction = navigationManager.nextInstruction {
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
                    Image(systemName: isAnalyzingScene ? "eye.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(SeyeghtTheme.accent)
                        .symbolEffect(.pulse, isActive: isAnalyzingScene)
                    Text(isAnalyzingScene ? "Describing scene…" : "Tap anywhere to describe scene")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                }
                .accessibilityLabel(isAnalyzingScene ? "Describing scene" : "Tap anywhere or say Hey Seyeght to describe scene")

                Spacer()

                // Bottom: settings gear
                HStack {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
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
            handleSceneTap()
        }
        .onAppear {
            lidarManager.start()
            speechManager.onWakeWordDetected = { handleSceneTap() }
            speechManager.startListening()
        }
        .onDisappear {
            lidarManager.stop()
            speechManager.stopListening()
        }
        .onChange(of: lidarManager.closestDistance) { _, distance in
            hapticsManager.updateForDistance(distance)
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingsView()
        }
        .navigationDestination(isPresented: $navigateToSubscription) {
            SubscriptionView()
        }
    }

    private func handleSceneTap() {
        guard !isAnalyzingScene else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        guard subscriptionManager.isSubscribed else {
            // Not subscribed — route to paywall
            navigateToSubscription = true
            return
        }

        isAnalyzingScene = true
        Task {
            await visionManager.captureAndAnalyze(from: lidarManager.session)
            isAnalyzingScene = false
        }
    }
}
