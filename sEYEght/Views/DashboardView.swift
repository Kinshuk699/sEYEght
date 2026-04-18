//
//  DashboardView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import SwiftData
import Combine
import UIKit
import AVFoundation

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
    @State private var navigateToNavSearch = false
    @State private var isAnalyzingScene = false

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
    /// Suppress distance warnings while scene description is playing
    @State private var sceneSpeechUntil: Date = .distantPast
    /// Track when distance speech started — don't interrupt until it finishes
    @State private var distanceSpeechUntil: Date = .distantPast
    /// Battery level warnings — track which thresholds have been spoken
    @State private var lastBatteryWarningLevel: Int = 100
    /// Timer for periodic battery checks
    @State private var batteryCheckTimer: Timer?

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
                    .accessibilityLabel(lidarManager.isRunning ? "Sight is active" : "Sight is starting")
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
                    Text(isAnalyzingScene ? "Describing scene…" : "4-tap to describe")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                }
                .accessibilityHidden(true)

                Spacer()

                // Bottom bar: settings (left) + navigation (right)
                HStack {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24))
                        .foregroundColor(SeyeghtTheme.accent)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .navigable("Settings button") {
                            navigateToSettings = true
                        }

                    Spacer()

                    // Stop navigation button (only visible during active nav)
                    if navigationManager.isNavigating {
                        Button {
                            navigationManager.stopNavigation()
                            speak("Navigation stopped.", priority: true)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Stop")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.8))
                            .clipShape(Capsule())
                        }
                        .accessibilityLabel("Stop navigation")
                        .accessibilityHint("Double tap to cancel the current route")
                    }

                    // Navigation mode button
                    Image(systemName: "location.fill")
                        .font(.system(size: 24))
                        .foregroundColor(SeyeghtTheme.accent)
                        .padding(10)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .navigable("Navigate button. Find a destination.") {
                            navigateToNavSearch = true
                        }
                }
                .padding(.horizontal, SeyeghtTheme.horizontalPadding)
                .padding(.bottom, 24)
            }
        }
        .contentShape(Rectangle())
        // 4-tap has priority — SwiftUI waits to see if 4th tap comes before firing 3-tap
        .highPriorityGesture(
            TapGesture(count: 4)
                .onEnded { handleSceneTap() }
        )
        .onTapGesture(count: 3) {
            handleEmergencyTripleTap()
        }
        .onAppear {
            // Guard: only do full init ONCE per app session — not on every return from background
            guard !appState.hasAnnouncedWelcomeThisSession else {
                // Returning from background/settings — restart hardware + re-sync settings
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
                    try session.setActive(true)
                } catch {
                    print("[DashboardView] Audio session re-config failed: \(error)")
                }

                // Re-sync settings (user may have changed toggles in SettingsView)
                if let settings = settingsArray.first {
                    hapticsManager.userIntensityLevel = settings.hapticIntensityLevel
                    hapticsManager.maxRange = settings.radarRangeMeters
                    hapticsManager.audioToneVolume = Float(settings.beepVolume)
                    hapticsManager.audioToneEnabled = settings.beepsEnabled
                    hapticsManager.hapticsEnabled = settings.hapticsEnabled
                }

                lidarManager.start()
                hapticsManager.ensureEngine()
                ShakeDetector.shared.start()
                startBatteryMonitoring()
                return
            }
            appState.hasAnnouncedWelcomeThisSession = true
            appState.hasCompletedOnboarding = true

            // Immediate haptic so blind user knows the screen loaded
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Sync stored settings to live managers
            if let settings = settingsArray.first {
                hapticsManager.userIntensityLevel = settings.hapticIntensityLevel
                hapticsManager.maxRange = settings.radarRangeMeters
                hapticsManager.audioToneVolume = Float(settings.beepVolume)
                hapticsManager.audioToneEnabled = settings.beepsEnabled
                hapticsManager.hapticsEnabled = settings.hapticsEnabled
            }

            // Start battery monitoring
            UIDevice.current.isBatteryMonitoringEnabled = true
            startBatteryMonitoring()

            // Defer hardware init slightly so the app is fully active
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                // Configure audio session for playback (speech + tones, no mic needed)
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
                    try session.setActive(true)
                } catch {
                    print("[DashboardView] ❌ Audio session config failed: \(error)")
                }

                hapticsManager.ensureEngine()
                lidarManager.start()

                // Wire all managers' speech through Dashboard's single synthesizer
                visionManager.onSpeechRequest = { text in speakNatural(text) }
                navigationManager.onSpeechRequest = { text in speak(text) }
                navigationManager.onPrioritySpeechRequest = { text in speak(text, priority: true) }

                // Start shake detection
                ShakeDetector.shared.start()

                // Spoken welcome ONLY on first launch this session
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                speak("Sight ready. Tap the bottom right to navigate somewhere.")
            }
        }
        .onDisappear {
            // Only stop the tone, NOT LiDAR or speech — those should keep running
            // when user is in Settings/Subscription screens
            hapticsManager.stopTone()
            proximityRepeatTimer?.invalidate()
            proximityRepeatTimer = nil
            batteryCheckTimer?.invalidate()
            batteryCheckTimer = nil
            ShakeDetector.shared.stop()
        }
        .onReceive(ShakeDetector.shared.shakeDetected) { _ in
            handleSceneTap()
        }
        .onChange(of: lidarManager.closestDistance) { _, distance in
            // Only fire haptics/speech when Dashboard is the active screen
            if navigateToNavSearch || navigateToSettings || navigateToSubscription {
                print("[DashboardView] ❌ Haptics blocked: child screen open (nav=\(navigateToNavSearch) set=\(navigateToSettings) sub=\(navigateToSubscription))")
                return
            }
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
        .navigationDestination(isPresented: $navigateToNavSearch) {
            NavigationSearchView()
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
        // Check if voice is enabled for automatic announcements
        // (User-initiated speech like .navigable() and 4-tap bypass this)
        guard settingsArray.first?.voiceEnabled ?? true else { return }
        // Suppress distance speech while a scene description is being read
        guard !isAnalyzingScene && Date() > sceneSpeechUntil else { return }
        // Don't interrupt an in-progress distance announcement — let it finish
        guard Date() > distanceSpeechUntil else { return }
        // During active navigation, only warn for very close obstacles (< 0.5m)
        // to avoid talking over turn-by-turn directions
        if navigationManager.isNavigating && distance >= 0.5 { return }
        
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

        // Block new distance announcements for ~2.5 seconds (let current one finish)
        distanceSpeechUntil = Date().addingTimeInterval(2.5)
        
        // Speak WITHOUT interrupting — if something else is playing, this gets queued
        // The distanceSpeechUntil check ensures we won't try to speak again too soon
        speak(distanceText, priority: false)

        // For very close obstacles, set up a repeat timer
        proximityRepeatTimer?.invalidate()
        if threshold <= 0.5 {
            proximityRepeatTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [self] _ in
                let current = lidarManager.closestDistance
                let voiceOn = settingsArray.first?.voiceEnabled ?? true
                if current < 0.5 && !isEmergencyActive && !Narrator.shared.isSpeaking && voiceOn {
                    let msg = current < 0.3 ? "Still very close." : "Still close. About 2 feet."
                    speak(msg, priority: false)
                } else {
                    proximityRepeatTimer?.invalidate()
                    proximityRepeatTimer = nil
                }
            }
        }
    }

    /// Triple-tap: immediately speak current location
    private func handleEmergencyTripleTap() {
        // Strong haptic so user knows it registered
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        print("[DashboardView] 📍 Triple-tap detected — requesting location")
        
        // Stop any current speech and announce we're getting location
        Narrator.shared.stop()
        
        // Speak location (uses reverse geocoding, may take a moment)
        navigationManager.speakCurrentLocation()
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

    /// Speak important content (scene descriptions) — interrupts distance warnings.
    private func speakNatural(_ text: String) {
        // Give scene speech a 15-second window free from distance interruptions
        sceneSpeechUntil = Date().addingTimeInterval(15)
        proximityRepeatTimer?.invalidate()
        proximityRepeatTimer = nil
        Narrator.shared.stop()
        Narrator.shared.speak(text, rate: 0.45, volume: 0.9)
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

    // MARK: - Battery Monitoring

    /// Start periodic battery level checks
    private func startBatteryMonitoring() {
        // Check immediately
        checkBattery()
        // Then check every 60 seconds
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            checkBattery()
        }
    }

    /// Check battery level and warn at 20%, 10%, 5%
    private func checkBattery() {
        let level = Int(UIDevice.current.batteryLevel * 100)
        let state = UIDevice.current.batteryState
        
        // Don't warn if charging or level is unknown (-1)
        guard level >= 0, state != .charging, state != .full else { return }
        
        // Warning thresholds: 20%, 10%, 5%
        let warningThresholds = [20, 10, 5]
        
        for threshold in warningThresholds {
            // Warn if we just crossed below this threshold
            if level <= threshold && lastBatteryWarningLevel > threshold {
                lastBatteryWarningLevel = level
                let message: String
                switch threshold {
                case 20:
                    message = "Battery at \(level) percent. Consider charging soon."
                case 10:
                    message = "Battery low. \(level) percent remaining."
                case 5:
                    message = "Battery critical. Only \(level) percent left. Please charge now."
                default:
                    message = "Battery at \(level) percent."
                }
                speak(message, priority: true)
                print("[DashboardView] 🔋 Battery warning: \(level)%")
                return
            }
        }
        
        // Update tracking even if no warning
        if level < lastBatteryWarningLevel {
            lastBatteryWarningLevel = level
        }
    }

    // MARK: - Help

    /// Speak all available commands (can be wired up to settings later)
    private func speakHelp() {
        let helpText = """
        Here are your commands. \
        Tap the bottom right button to navigate somewhere. \
        Tap four times or shake to describe what's ahead. \
        Triple-tap to hear your current location. \
        Say where am I for your address. \
        Double-tap the bottom left corner for settings.
        """
        speak(helpText, priority: true)
    }
}
