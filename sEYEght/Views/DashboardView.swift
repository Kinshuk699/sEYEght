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
    @State private var hasInitializedHardware = false

    /// Tracks the last spoken distance threshold to avoid repeating
    @State private var lastSpokenThreshold: Float = Float.greatestFiniteMagnitude
    /// Cooldown so we don't speak distance more than once every 3 seconds
    @State private var lastDistanceSpeechTime: Date = .distantPast

    var body: some View {
        ZStack {
            // Layer 1: Live camera feed from ARKit
            if lidarManager.isRunning {
                ARCameraView(session: lidarManager.session)
                    .ignoresSafeArea()

                // Semi-transparent overlay so UI elements are readable
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
            } else {
                SeyeghtTheme.background.ignoresSafeArea()
            }

            // Layer 2: LiDAR obstacle indicator
            // Shows a pulsing colored circle where the closest obstacle is detected
            if lidarManager.closestDistance < Float(hapticsManager.maxRange) {
                GeometryReader { geo in
                    let xPos = CGFloat(lidarManager.closestNormalizedX) * geo.size.width
                    let yPos = geo.size.height * 0.35  // Upper portion of screen
                    let proximity = max(0, min(1, 1.0 - Double(lidarManager.closestDistance) / hapticsManager.maxRange))

                    // Obstacle marker — red when close, yellow when medium, green when far
                    Circle()
                        .fill(obstacleColor(proximity: proximity))
                        .frame(width: 40 + proximity * 40, height: 40 + proximity * 40)
                        .opacity(0.7 + proximity * 0.3)
                        .shadow(color: obstacleColor(proximity: proximity), radius: 10 + proximity * 20)
                        .position(x: xPos, y: yPos)
                        .accessibilityHidden(true)

                    // Distance label near the indicator
                    Text(String(format: "%.1fm", lidarManager.closestDistance))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(obstacleColor(proximity: proximity).opacity(0.8))
                        .cornerRadius(8)
                        .position(x: xPos, y: yPos + 40 + proximity * 20 + 16)
                        .accessibilityHidden(true)
                }
            }

            // Layer 3: UI controls
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(lidarManager.isRunning ? SeyeghtTheme.accent : Color.red)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(lidarManager.isRunning ? "Seyeght Active" : "Starting…")
                            .font(SeyeghtTheme.caption)
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                    .accessibilityLabel(lidarManager.isRunning ? "Seyeght is active" : "Seyeght is starting")
                    Spacer()

                    // Distance readout (top-right)
                    if lidarManager.closestDistance < Float(hapticsManager.maxRange) {
                        Text(String(format: "%.1fm", lidarManager.closestDistance))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(obstacleColor(proximity: 1.0 - Double(lidarManager.closestDistance) / hapticsManager.maxRange))
                            .accessibilityLabel(String(format: "Closest obstacle %.1f meters", lidarManager.closestDistance))
                    }
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

                // Center action hint
                VStack(spacing: 12) {
                    Image(systemName: isAnalyzingScene ? "eye.fill" : "hand.tap.fill")
                        .font(.system(size: 32))
                        .foregroundColor(SeyeghtTheme.accent)
                        .symbolEffect(.pulse, isActive: isAnalyzingScene)
                    Text(isAnalyzingScene ? "Describing scene…" : "Tap anywhere to describe scene")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
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
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
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
            speak("You've used all 3 free descriptions today. Subscribe to AI Vision for unlimited access.")
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
                speak(countMsg)
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

        // Speak with high priority — stops any current speech first
        speak(distanceText, priority: true)
    }

    /// Triple-tap emergency: speak location loudly + offer to call emergency services
    private func handleEmergencyTripleTap() {
        // Strong haptic burst
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Stop ALL current speech and announce emergency mode
        speak("Emergency mode activated. Your location is being announced.", priority: true)

        // Speak current location after the emergency message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            navigationManager.speakCurrentLocation()
        }

        print("[DashboardView] 🚨 Emergency triple-tap activated")
    }

    // MARK: - Centralized Speech

    /// Single voice output — stops current speech if priority, otherwise queues.
    private func speak(_ text: String, priority: Bool = false) {
        if priority {
            speechSynth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.45
        utterance.volume = 0.85
        speechSynth.speak(utterance)
    }

    /// Returns a color from green (far) → yellow → red (close) based on proximity 0…1
    private func obstacleColor(proximity: Double) -> Color {
        let clamped = max(0, min(1, proximity))
        if clamped < 0.5 {
            // Green → Yellow
            return Color(red: clamped * 2, green: 1.0, blue: 0)
        } else {
            // Yellow → Red
            return Color(red: 1.0, green: 1.0 - (clamped - 0.5) * 2, blue: 0)
        }
    }
}
