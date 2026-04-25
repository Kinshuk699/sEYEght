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
import CoreLocation
import MapKit

/// S-003: Main active dashboard. The user spends 99% of their time here.
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(LiDARManager.self) private var lidarManager
    @Environment(HapticsManager.self) private var hapticsManager
    @Environment(VisionManager.self) private var visionManager
    @Environment(NavigationManager.self) private var navigationManager
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [UserSettings]

    @State private var navigateToSettings = false
    @State private var navigateToNavSearch = false
    @State private var isAnalyzingScene = false

    /// Suppress other speech during emergency mode
    @State private var isEmergencyActive = false
    /// Cooldown: last time a scene analysis was requested (prevents API flooding)
    @State private var lastAnalysisTime: Date = .distantPast
    /// Suppress distance warnings while scene description is playing
    @State private var sceneSpeechUntil: Date = .distantPast
    /// Battery level warnings — track which thresholds have been spoken
    @State private var lastBatteryWarningLevel: Int = 100
    /// Timer for periodic battery checks
    @State private var batteryCheckTimer: Timer?
    /// AR navigation overlay manager
    @State private var arOverlay = ARNavigationOverlay()
    /// Compass bearing to next waypoint (degrees, 0=north)
    @State private var compassBearing: Double = 0
    /// User's current heading (degrees)
    @State private var userHeading: Double = 0
    /// Distance to next turn in meters
    @State private var distanceToNextTurn: Double = 0
    /// Next turn instruction text for compass overlay
    @State private var nextTurnText: String = ""
    /// Timer for updating AR overlay
    @State private var arUpdateTimer: Timer?

    var body: some View {
        ZStack {
            // Layer 1: Live camera feed from ARKit
            if lidarManager.isRunning {
                ARCameraView(session: lidarManager.session, onSceneReady: { scene in
                    arOverlay.attach(to: scene)
                })
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

            // Compass arrow overlay (only during navigation)
            if navigationManager.isNavigating {
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        // Rotating arrow pointing toward next waypoint
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.2))
                            .rotationEffect(.degrees(compassBearing - userHeading))
                            .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.2).opacity(0.8), radius: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            if !nextTurnText.isEmpty {
                                Text(nextTurnText)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            if distanceToNextTurn > 0 {
                                Text(formatCompassDistance(distanceToNextTurn))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.2))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
                    .padding(.bottom, 80)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(nextTurnText.isEmpty ? "Navigating" : "\(nextTurnText), \(formatCompassDistance(distanceToNextTurn))")
                }
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

                hapticsManager.ensureEngine()
                ShakeDetector.shared.start()
                startBatteryMonitoring()
                startAROverlayUpdates()
                Task { @MainActor in await startLiDARWhenAuthorized() }
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

                // Wait until camera permission is actually granted before
                // starting ARKit — ARSession.run() with .notDetermined or
                // .denied silently produces zero frames and never recovers,
                // which is what makes the dashboard look frozen on a fresh
                // install. Poll up to 30 s so the user can grant in Settings.
                await startLiDARWhenAuthorized()

                // Wire all managers' speech through Dashboard's single synthesizer
                visionManager.onSpeechRequest = { text in speakNatural(text) }
                navigationManager.onSpeechRequest = { text in speak(text) }
                navigationManager.onPrioritySpeechRequest = { text in speak(text, priority: true) }

                // Start shake detection
                ShakeDetector.shared.start()

                // Start AR overlay update timer (updates at 2 Hz during navigation)
                startAROverlayUpdates()

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
            batteryCheckTimer?.invalidate()
            batteryCheckTimer = nil
            arUpdateTimer?.invalidate()
            arUpdateTimer = nil
            arOverlay.detach()
            ShakeDetector.shared.stop()
        }
        .onReceive(ShakeDetector.shared.shakeDetected) { _ in
            handleSceneTap()
        }
        .onChange(of: lidarManager.closestDistance) { _, distance in
            // Only fire haptics/speech when Dashboard is the active screen
            if navigateToNavSearch || navigateToSettings {
                return
            }
            // Single source of truth: HapticsManager owns zone state and fires
            // discrete haptic+audio patterns on transitions. We add spoken
            // context only when the zone changes (escalations, all-clear).
            let transition = hapticsManager.updateForDistance(distance, normalizedX: lidarManager.closestNormalizedX)
            if let t = transition {
                speakForTransition(t)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingsView()
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

        // Rate limit: minimum 3 seconds between requests (on-device is fast but avoid spam)
        let timeSinceLast = Date().timeIntervalSince(lastAnalysisTime)
        if timeSinceLast < 3.0 {
            speak("Please wait.", priority: false)
            return
        }
        lastAnalysisTime = Date()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        isAnalyzingScene = true
        speak("Looking...")
        print("[DashboardView] Capturing scene for on-device analysis")

        // Pass current LiDAR distance so the description can anchor with
        // "about one meter ahead". Only pass valid finite distances; the
        // simulator and very-far targets get nil.
        let dist = lidarManager.closestDistance
        let validDist: Float? = (dist > 0 && dist.isFinite && dist < 8.0) ? dist : nil
        visionManager.captureAndAnalyze(from: lidarManager.session, closestDistance: validDist)

        // Wait for VisionManager to finish processing, then clear the flag
        Task {
            for _ in 0..<20 { // up to 10 seconds (on-device is fast)
                try? await Task.sleep(for: .milliseconds(500))
                if !visionManager.isProcessing { break }
            }
            isAnalyzingScene = false
        }
    }

    /// Start LiDAR as soon as the user grants camera permission. ARKit will
    /// silently produce zero frames if started before permission is granted,
    /// so we poll authorization status (it changes to .authorized the moment
    /// the system dialog is dismissed with Allow). Bails after 30 s so we
    /// never spin forever.
    @MainActor
    private func startLiDARWhenAuthorized() async {
        if lidarManager.isRunning { return }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                lidarManager.start()
                print("[DashboardView] ✅ Camera authorized — LiDAR started")
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        print("[DashboardView] ⚠️ Camera permission not granted within 30 s")
        speak("Sight needs camera access. Open iPhone Settings and enable it.", priority: true)
    }

    /// Speak short context on a proximity-zone transition. Quiet by default:
    /// nothing is spoken while inside a stable zone — that's what the haptic
    /// pattern is for. Speech only fires on **transitions** so the user always
    /// associates a phrase with a felt change.
    private func speakForTransition(_ t: HapticsManager.ZoneTransition) {
        guard !isEmergencyActive else { return }
        guard settingsArray.first?.voiceEnabled ?? true else { return }
        // Don't talk over a scene description.
        guard !isAnalyzingScene && Date() > sceneSpeechUntil else { return }
        // During active turn-by-turn, only speak DANGER so we don't drown
        // out directions with caution chatter.
        if navigationManager.isNavigating && t.to != .danger { return }

        let direction: String
        switch t.normalizedX {
        case ..<0.35: direction = "left"
        case 0.65...: direction = "right"
        default:      direction = "ahead"
        }

        let phrase: String
        switch t.to {
        case .clear:
            // Only announce all-clear if user was actually in a danger/warning state
            if t.from.rawValue >= HapticsManager.ProximityZone.warning.rawValue {
                phrase = "Clear."
            } else {
                return
            }
        case .caution:
            // Don't bother speaking when escalating up FROM a worse zone (improvement).
            if !t.isEscalation { return }
            phrase = "Object \(direction). One and a half meters."
        case .warning:
            phrase = "Close \(direction). One meter."
        case .danger:
            phrase = "Stop. \(direction.capitalized). Half a meter."
        }

        speak(phrase, priority: t.to == .danger)
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

    // MARK: - AR Navigation Overlay

    private func startAROverlayUpdates() {
        arUpdateTimer?.invalidate()
        arUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            updateAROverlay()
            updateCompassArrow()
        }
    }

    private func updateAROverlay() {
        guard navigationManager.isNavigating,
              let route = navigationManager.currentRoute,
              let userLoc = navigationManager.userLocation else {
            return
        }
        arOverlay.update(
            route: route,
            userLocation: userLoc,
            currentStepIndex: navigationManager.activeStepIndex
        )
    }

    private func updateCompassArrow() {
        guard navigationManager.isNavigating,
              let route = navigationManager.currentRoute,
              let userLoc = navigationManager.userLocation else {
            compassBearing = 0
            distanceToNextTurn = 0
            nextTurnText = ""
            return
        }

        let steps = route.steps.filter { !$0.instructions.isEmpty }
        let stepIdx = navigationManager.activeStepIndex
        guard stepIdx < steps.count else { return }

        let step = steps[stepIdx]
        let stepCoord = step.polyline.coordinate
        let stepLoc = CLLocation(latitude: stepCoord.latitude, longitude: stepCoord.longitude)

        distanceToNextTurn = userLoc.distance(from: stepLoc)
        nextTurnText = step.instructions
        compassBearing = bearingBetween(userLoc.coordinate, stepCoord)

        // Get device heading from ARKit camera transform
        if lidarManager.isRunning {
            let transform = lidarManager.cameraTransform
            // Extract forward direction from camera transform
            let forward = simd_float3(-transform.columns.2.x, 0, -transform.columns.2.z)
            let heading = atan2(forward.x, -forward.z) * 180 / .pi
            userHeading = Double(heading < 0 ? heading + 360 : heading)
        }
    }

    private func bearingBetween(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var b = atan2(y, x) * 180 / .pi
        if b < 0 { b += 360 }
        return b
    }

    private func formatCompassDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            return "\(Int(meters / 10) * 10)m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}
