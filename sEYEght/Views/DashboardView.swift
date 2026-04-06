//
//  DashboardView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import SwiftData

/// S-003: Main active dashboard. The user spends 99% of their time here.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(LiDARManager.self) private var lidarManager
    @Environment(HapticsManager.self) private var hapticsManager
    @Environment(VisionManager.self) private var visionManager
    @Environment(NavigationManager.self) private var navigationManager
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [UserSettings]

    @State private var navigateToSettings = false
    @State private var navigateToSubscription = false
    @State private var isAnalyzingScene = false
    @State private var hasInitializedHardware = false

    /// Tracks the last spoken distance threshold to avoid repeating
    @State private var lastSpokenThreshold: Float = Float.greatestFiniteMagnitude
    /// Cooldown so we don't speak distance more than once every 3 seconds
    @State private var lastDistanceSpeechTime: Date = .distantPast
    /// Timer for repeating close-proximity warnings
    @State private var proximityRepeatTimer: Timer?
    /// Suppress other speech during emergency mode
    @State private var isEmergencyActive = false
    /// Cooldown: last time a scene analysis was requested (prevents API flooding)
    @State private var lastAnalysisTime: Date = .distantPast

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
                    let padding: CGFloat = 50
                    let rawX = CGFloat(lidarManager.closestNormalizedX) * geo.size.width
                    let xPos = min(max(rawX, padding), geo.size.width - padding)
                    let yPos = geo.size.height * 0.35
                    let proximity = max(0, min(1, 1.0 - Double(lidarManager.closestDistance) / hapticsManager.maxRange))
                    let bubbleSize = 40 + proximity * 40

                    // Obstacle marker — red when close, yellow when medium, green when far
                    Circle()
                        .fill(obstacleColor(proximity: proximity))
                        .frame(width: bubbleSize, height: bubbleSize)
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
                        .position(x: xPos, y: yPos + bubbleSize / 2 + 16)
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
                    Text(isAnalyzingScene ? "Describing scene…" : "Double-tap to describe what's ahead")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                }
                .accessibilityLabel(isAnalyzingScene ? "Describing scene" : "Double-tap anywhere to describe scene")

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
        .onTapGesture(count: 2) {
            handleSceneTap()
        }
        .onAppear {
            // Immediate haptic so blind user knows the screen loaded
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            appState.hasCompletedOnboarding = true

            // Sync stored settings to live managers
            if let settings = settingsArray.first {
                hapticsManager.userIntensityLevel = settings.hapticIntensityLevel
                hapticsManager.maxRange = settings.radarRangeMeters
                hapticsManager.audioToneVolume = Float(settings.beepVolume)
            }

            // Defer hardware init slightly so the app is fully active
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                hapticsManager.ensureEngine()
                lidarManager.start()

                // Wire all managers' speech through Dashboard's single synthesizer
                // Scene descriptions use OpenAI TTS for natural voice
                visionManager.onSpeechRequest = { text in speakNatural(text) }
                navigationManager.onSpeechRequest = { text in speak(text) }

                // Spoken welcome so blind users know the app is working
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                speak("Seyeght ready. LiDAR scanning. Double-tap the screen to describe what's ahead. Triple-tap for emergency mode.")
            }
        }
        .onDisappear {
            // Only stop the tone, NOT LiDAR or speech — those should keep running
            // when user is in Settings/Subscription screens
            hapticsManager.stopTone()
            proximityRepeatTimer?.invalidate()
            proximityRepeatTimer = nil
        }
        .onChange(of: lidarManager.closestDistance) { _, distance in
            hapticsManager.updateForDistance(distance, normalizedX: lidarManager.closestNormalizedX)
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
        guard !isAnalyzingScene else {
            speak("Still looking. Please wait.", priority: false)
            return
        }
        guard !isEmergencyActive else { return }

        // Rate limit: minimum 8 seconds between analysis requests to avoid API flooding
        let timeSinceLast = Date().timeIntervalSince(lastAnalysisTime)
        if timeSinceLast < 8.0 {
            let waitTime = Int(ceil(8.0 - timeSinceLast))
            speak("Please wait \(waitTime) seconds before asking again.", priority: false)
            return
        }
        lastAnalysisTime = Date()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        #if DEBUG
        // Reset free uses for testing
        subscriptionManager.resetFreeUsesForTesting()
        #endif

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                speak(countMsg)
            }
        }

        isAnalyzingScene = true
        speak("Looking...")
        print("[DashboardView] Capturing scene for AI analysis")

        visionManager.captureAndAnalyze(from: lidarManager.session)

        // Wait for VisionManager to finish processing, then clear the flag
        Task {
            for _ in 0..<60 { // up to 30 seconds
                try? await Task.sleep(for: .milliseconds(500))
                if !visionManager.isProcessing { break }
            }
            isAnalyzingScene = false
        }
    }

    /// Speak distance when crossing key thresholds, and repeat if still in danger zone
    private func speakDistanceIfNeeded(_ distance: Float) {
        guard !isEmergencyActive else { return }
        guard distance < 1.2 else {
            // Cleared — reset so we can announce again when approaching
            if lastSpokenThreshold < Float.greatestFiniteMagnitude {
                lastSpokenThreshold = Float.greatestFiniteMagnitude
            }
            proximityRepeatTimer?.invalidate()
            proximityRepeatTimer = nil
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

        // Speak if this is a NEW threshold crossing + cooldown elapsed
        let isNewThreshold = threshold != lastSpokenThreshold
        guard isNewThreshold || Date().timeIntervalSince(lastDistanceSpeechTime) > 4.0 else { return }

        lastSpokenThreshold = threshold
        lastDistanceSpeechTime = Date()

        // Directional context from LiDAR
        let direction: String
        let x = lidarManager.closestNormalizedX
        if x < 0.35 {
            direction = "to your left"
        } else if x > 0.65 {
            direction = "to your right"
        } else {
            direction = "ahead"
        }

        let distanceText: String
        switch threshold {
        case 0.3: distanceText = "Very close \(direction). Less than 1 foot."
        case 0.5: distanceText = "Obstacle \(direction). About 2 feet."
        case 1.0: distanceText = "Object \(direction). About 3 feet."
        default: return
        }

        // Speak with high priority — stops any current speech first
        speak(distanceText, priority: true)

        // For very close obstacles, set up a repeat timer
        proximityRepeatTimer?.invalidate()
        if threshold <= 0.5 {
            proximityRepeatTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [self] _ in
                let current = lidarManager.closestDistance
                if current < 0.5 && !isEmergencyActive && !Narrator.shared.isSpeaking {
                    let msg = current < 0.3 ? "Still very close." : "Still close. About 2 feet."
                    speak(msg, priority: false)
                } else {
                    proximityRepeatTimer?.invalidate()
                    proximityRepeatTimer = nil
                }
            }
        }
    }

    /// Triple-tap emergency: speak location loudly. Triple-tap again to exit.
    private func handleEmergencyTripleTap() {
        if isEmergencyActive {
            // Triple-tap again to EXIT emergency mode
            isEmergencyActive = false
            let exitGen = UINotificationFeedbackGenerator()
            exitGen.notificationOccurred(.success)
            speak("Emergency mode ended. Resuming normal navigation.", priority: true)
            print("[DashboardView] 🚨 Emergency mode deactivated by user")
            return
        }

        isEmergencyActive = true

        // Strong haptic burst
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Stop ALL current speech and announce emergency mode
        speak("Emergency mode activated. Your location is being announced. Triple-tap again to exit.", priority: true)

        // Speak current location after the emergency message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [self] in
            guard isEmergencyActive else { return }
            navigationManager.speakCurrentLocation()
        }

        // Repeat location every 30 seconds while emergency mode is active
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(34))
            while !Task.isCancelled && isEmergencyActive {
                navigationManager.speakCurrentLocation()
                try? await Task.sleep(for: .seconds(30))
            }
        }

        print("[DashboardView] 🚨 Emergency triple-tap activated — persists until dismissed")
    }

    // MARK: - Centralized Speech

    /// Single voice output — stops current speech if priority, otherwise skips if busy.
    private func speak(_ text: String, priority: Bool = false) {
        if priority {
            Narrator.shared.stop()
            Narrator.shared.speak(text, rate: 0.45, volume: 0.85)
        } else {
            // Non-priority: don't interrupt ongoing speech
            Narrator.shared.speak(text, rate: 0.45, volume: 0.85, interruptible: false)
        }
    }

    /// Speak important content (scene descriptions) using OpenAI TTS for natural voice.
    private func speakNatural(_ text: String) {
        Narrator.shared.speakWithOpenAI(text)
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
