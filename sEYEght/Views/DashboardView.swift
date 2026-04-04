//
//  DashboardView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import AVFoundation

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
    @State private var speechSynth = AVSpeechSynthesizer()

    /// Tracks the last spoken distance threshold to avoid repeating
    @State private var lastSpokenThreshold: Float = Float.greatestFiniteMagnitude
    /// Cooldown so we don't speak distance more than once every 3 seconds
    @State private var lastDistanceSpeechTime: Date = .distantPast

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
                            .accessibilityHidden(true)
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
        .onTapGesture(count: 3) {
            handleEmergencyTripleTap()
        }
        .onTapGesture {
            handleSceneTap()
        }
        .onAppear {
            appState.hasCompletedOnboarding = true
            // Defer hardware init slightly so the app is fully active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hapticsManager.ensureEngine()
                lidarManager.start()
                speechManager.onWakeWordDetected = { handleSceneTap() }
                speechManager.onWhereAmIDetected = { navigationManager.speakCurrentLocation() }
                speechManager.startListening()

                // Spoken welcome so blind users know the app is working
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let utterance = AVSpeechUtterance(string: "Seyeght ready. LiDAR scanning. Tap anywhere or say Hey Seyeght to describe your scene.")
                    utterance.rate = 0.45
                    utterance.volume = 0.8
                    speechSynth.speak(utterance)
                }
            }
        }
        .onDisappear {
            // Only stop the tone, NOT LiDAR or speech — those should keep running
            // when user is in Settings/Subscription screens
            hapticsManager.stopTone()
        }
        .onChange(of: lidarManager.closestDistance) { _, distance in
            hapticsManager.updateForDistance(distance)
            speakDistanceIfNeeded(distance)
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

        guard subscriptionManager.canUseAIVision else {
            // Free uses exhausted and not subscribed
            let utterance = AVSpeechUtterance(string: "You've used all 3 free descriptions today. Subscribe to AI Vision for unlimited access.")
            utterance.rate = 0.45
            speechSynth.speak(utterance)
            navigateToSubscription = true
            print("[DashboardView] Free uses exhausted — navigating to paywall")
            return
        }

        // Consume a free use if not subscribed
        if !subscriptionManager.isSubscribed {
            _ = subscriptionManager.consumeFreeUse()
            let remaining = subscriptionManager.freeUsesRemaining
            let countMsg = remaining > 0 ? "\(remaining) free descriptions remaining today." : "That was your last free description today."
            // Speak remaining count after the scene description
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                let countUtterance = AVSpeechUtterance(string: countMsg)
                countUtterance.rate = 0.45
                speechSynth.speak(countUtterance)
            }
        }

        isAnalyzingScene = true
        print("[DashboardView] Capturing scene for AI analysis")
        Task {
            await visionManager.captureAndAnalyze(from: lidarManager.session)
            isAnalyzingScene = false
        }
    }

    /// Speak distance when crossing key thresholds: 1.0m, 0.5m, 0.3m
    private func speakDistanceIfNeeded(_ distance: Float) {
        guard distance < 1.2 else {
            // Cleared — reset so we can announce again when approaching
            if lastSpokenThreshold < Float.greatestFiniteMagnitude {
                lastSpokenThreshold = Float.greatestFiniteMagnitude
            }
            return
        }

        // Determine which threshold was crossed
        let threshold: Float
        if distance < 0.3 {
            threshold = 0.3
        } else if distance < 0.5 {
            threshold = 0.5
        } else if distance < 1.0 {
            threshold = 1.0
        } else {
            return
        }

        // Only speak if this is a NEW threshold crossing + cooldown elapsed
        guard threshold != lastSpokenThreshold else { return }
        guard Date().timeIntervalSince(lastDistanceSpeechTime) > 3.0 else { return }

        lastSpokenThreshold = threshold
        lastDistanceSpeechTime = Date()

        let distanceText: String
        switch threshold {
        case 0.3: distanceText = "Very close. Less than 1 foot."
        case 0.5: distanceText = "Obstacle. About 2 feet ahead."
        case 1.0: distanceText = "Object ahead. About 3 feet."
        default: return
        }

        // Speak with high priority (interrupt current speech if any non-critical)
        let utterance = AVSpeechUtterance(string: distanceText)
        utterance.rate = 0.55
        utterance.volume = 0.9
        speechSynth.speak(utterance)
    }

    /// Triple-tap emergency: speak location loudly + offer to call emergency services
    private func handleEmergencyTripleTap() {
        // Strong haptic burst
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Stop current speech and announce emergency mode
        speechSynth.stopSpeaking(at: .immediate)
        let emergencyMsg = AVSpeechUtterance(string: "Emergency mode activated. Your location is being announced. Triple tap again to call emergency services.")
        emergencyMsg.rate = 0.45
        emergencyMsg.volume = 1.0
        speechSynth.speak(emergencyMsg)

        // Speak current location after the emergency message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            navigationManager.speakCurrentLocation()
        }

        print("[DashboardView] 🚨 Emergency triple-tap activated")
    }
}
