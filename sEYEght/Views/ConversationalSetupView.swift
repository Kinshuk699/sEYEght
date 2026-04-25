//
//  ConversationalSetupView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/6/26.
//

import SwiftUI
import AVFoundation
import ARKit
import CoreMotion

/// Audio-first conversational setup that replaces all visual onboarding.
/// Offers Quick (45 seconds) or Full (3 minutes) setup modes.
struct ConversationalSetupView: View {
    @Environment(HapticsManager.self) private var hapticsManager
    @Environment(VisionManager.self) private var visionManager
    @Environment(LiDARManager.self) private var lidarManager
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    @State private var permissionsManager = PermissionsManager()
    @State private var phase: SetupPhase = .welcome
    @State private var statusText: String = "Setting up..."
    @State private var isPulsing = false
    @State private var navigateToDashboard = false
    @State private var setupMode: SetupMode = .none
    @State private var waitingForTap = false  // For user choice input
    @State private var waitingForSettingsReturn = false  // User is in Settings app
    @State private var hasReturnedFromSettings = false  // Set true when scenePhase becomes .active while waiting

    enum SetupMode {
        case none      // Not yet chosen
        case quick     // ~45 seconds: intro → permissions → one beep → go
        case full      // ~3 minutes: comprehensive walkthrough
    }

    enum SetupPhase: Int, CaseIterable {
        case welcome
        case modeChoice
        case permissions
        case mountPhone
        case featureDemo
        case ready
    }

    var body: some View {
        ZStack {
            // Camera feed when LiDAR is running, black otherwise
            if lidarManager.isRunning {
                ARCameraView(session: lidarManager.session)
                    .ignoresSafeArea()
                // Dim overlay so text stays readable
                Color.black.opacity(0.45).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 32) {
                Spacer()

                // Pulsing gold circle — visual anchor for low-vision users
                Circle()
                    .fill(SeyeghtTheme.accent.opacity(0.8))
                    .frame(width: 120, height: 120)
                    .scaleEffect(isPulsing ? 1.15 : 0.95)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                    .accessibilityHidden(true)

                Text(statusText)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .readable(statusText)

                Spacer()
            }
        }
        .contentShape(Rectangle())  // Makes entire area tappable
        .onTapGesture(count: 1) {
            handleTap(count: 1)
        }
        .onTapGesture(count: 2) {
            handleTap(count: 2)
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToDashboard) {
            DashboardView()
        }
        .task {
            isPulsing = true
            defer { Narrator.shared.stop() }
            await runConversation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                isPulsing = true
                // If user is returning from Settings, force an immediate permission
                // refresh AND interrupt any in-flight reminder so the polling loop
                // can pick up the new state on its very next 500 ms tick.
                if waitingForSettingsReturn {
                    permissionsManager.checkCurrentStatuses()
                    hasReturnedFromSettings = true
                    print("[Setup] scenePhase=.active while waiting; camera=\(permissionsManager.cameraStatus) location=\(permissionsManager.locationStatus)")
                    // Interrupt any reminder that's currently being spoken so the
                    // loop's next iteration runs without delay.
                    Narrator.shared.stop()
                }
            case .background, .inactive:
                Narrator.shared.stop()
            @unknown default:
                break
            }
        }
    }

    /// Single source of truth for tap handling. Order matters:
    /// 1. If we're waiting for the user to return from Settings, treat the tap as
    ///    a request to re-open Settings — BUT first refresh status, because the
    ///    user may already have granted and just not heard the confirmation yet.
    /// 2. Otherwise, if we're in the mode-choice phase, record their pick.
    private func handleTap(count: Int) {
        if waitingForSettingsReturn {
            permissionsManager.checkCurrentStatuses()
            // If they've actually granted, the polling loop will speak success;
            // we just interrupt any in-flight reminder so it picks up immediately.
            if permissionsManager.cameraStatus && permissionsManager.locationStatus {
                Narrator.shared.stop()
                hasReturnedFromSettings = true
                return
            }
            // Still missing — re-open Settings as the user expects.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        if waitingForTap && setupMode == .none {
            setupMode = (count == 1) ? .quick : .full
            waitingForTap = false
        }
    }

    // MARK: - Conversation State Machine

    private func runConversation() async {
        // Safety: if setup already done, don't re-run
        guard !appState.hasCompletedOnboarding else {
            print("[Setup] Already completed onboarding, skipping conversation")
            return
        }

        // Phase 1: Welcome + Mode Choice
        await phaseWelcomeAndModeChoice()
        guard !Task.isCancelled else { return }

        // Branch based on chosen mode
        if setupMode == .quick {
            await runQuickSetup()
        } else {
            await runFullSetup()
        }
    }

    // MARK: - Quick Setup (~45 seconds)

    private func runQuickSetup() async {
        // Streamlined permissions (no extra explanations) — BOTH mandatory
        await phasePermissionsQuick()
        guard !Task.isCancelled else { return }

        // Both permissions are mandatory; if either still missing, end setup.
        guard permissionsManager.cameraStatus && permissionsManager.locationStatus else {
            statusText = "Permissions required to continue"
            return
        }

        // One quick beep demo
        await demoBeepsQuick()
        guard !Task.isCancelled else { return }

        // Done!
        await phaseReadyQuick()
    }

    // MARK: - Full Setup (~3 minutes)

    private func runFullSetup() async {
        // Voice quality check (only in full mode)
        await phaseVoiceCheck()
        guard !Task.isCancelled else { return }

        // Full permissions with explanations — BOTH mandatory
        await phasePermissions()
        guard !Task.isCancelled else { return }

        // Both permissions are mandatory; if either still missing, end setup.
        guard permissionsManager.cameraStatus && permissionsManager.locationStatus else {
            statusText = "Permissions required to continue"
            return
        }

        // Mount phone with verification
        await phaseMountPhone()
        guard !Task.isCancelled else { return }

        // Full feature demo (beeps, haptics, camera)
        await phaseFeatureDemo()
        guard !Task.isCancelled else { return }

        // Ready
        await phaseReady()
    }

    // MARK: - Phase 1: Welcome + Mode Choice

    private func phaseWelcomeAndModeChoice() async {
        phase = .welcome
        statusText = "Welcome"

        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait(
            "Hi, I'm Sight — your navigation assistant. I detect obstacles with sound and vibration."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }

        // Mode choice
        phase = .modeChoice
        statusText = "Choose Setup"

        await Narrator.shared.speakAndWait(
            "Tap once for quick setup, about 45 seconds. Double-tap for full walkthrough, about 3 minutes."
        )
        guard !Task.isCancelled else { return }

        // Wait for tap
        waitingForTap = true
        statusText = "Tap to choose..."

        // Poll until user chooses (with timeout + reminder)
        var waited = 0
        while setupMode == .none && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            waited += 500
            guard !Task.isCancelled else { return }

            // Reminder every 8 seconds
            if waited % 8000 == 0 && waited < 24000 {
                await Narrator.shared.speakAndWait("Tap once for quick. Double-tap for full.")
            }

            // Default to quick after 25 seconds
            if waited >= 25000 {
                setupMode = .quick
                await Narrator.shared.speakAndWait("Starting quick setup.")
            }
        }
        waitingForTap = false

        if setupMode == .quick {
            statusText = "Quick Setup"
        } else {
            statusText = "Full Setup"
        }
    }

    // MARK: - Phase 1b: Voice Quality Check

    private func phaseVoiceCheck() async {
        // Refresh in case voices were installed since launch
        Narrator.shared.refreshVoice()

        // Already have an enhanced or premium voice — no action needed
        if Narrator.shared.hasHighQualityVoice {
            print("[Setup] Voice quality OK: \(Narrator.shared.voiceDescription)")
            return
        }

        // User has only the basic compact voice. We DO NOT open Settings here
        // (it traps the user mid-setup). Just mention it verbally and continue;
        // they can install a better voice later from system Settings.
        await Narrator.shared.speakAndWait(
            "Heads up — I'm using a basic voice right now. For a more natural sound, you can later go to Settings, Accessibility, Spoken Content, Voices, and download an Enhanced voice. Continuing for now."
        )
    }

    // MARK: - Quick Setup: Streamlined Permissions

    private func phasePermissionsQuick() async {
        phase = .permissions
        statusText = "Permissions"

        await Narrator.shared.speakAndWait("I need camera and location. Both are required.")
        guard !Task.isCancelled else { return }

        // Camera (mandatory) — keep trying until granted
        let cameraOK = await acquirePermission(
            name: "Camera",
            request: { permissionsManager.requestCamera() },
            isGranted: { permissionsManager.cameraStatus },
            isNotDetermined: { permissionsManager.cameraNotDetermined },
            firstAskCopy: "I need your camera to detect obstacles. Tap Allow on the prompt.",
            settingsCopy: "Camera was denied. I'll open Settings now. Find Camera and turn it on. When you come back, tap anywhere on the screen to re-open Settings if needed.",
            settingsGuidance: "Find Camera and turn it on."
        )
        guard !Task.isCancelled else { return }
        guard cameraOK else { return }

        // Location (mandatory)
        let locationOK = await acquirePermission(
            name: "Location",
            request: { permissionsManager.requestLocation() },
            isGranted: { permissionsManager.locationStatus },
            isNotDetermined: { permissionsManager.locationNotDetermined },
            firstAskCopy: "I need your location to tell you where you are. Tap Allow on the prompt.",
            settingsCopy: "Location was denied. I'll open Settings now. Tap Location and choose While Using the App. When you come back, tap anywhere on the screen to re-open Settings if needed.",
            settingsGuidance: "Tap Location and choose While Using the App."
        )
        guard !Task.isCancelled else { return }
        guard locationOK else { return }

        await Narrator.shared.speakAndWait("Both permissions are ready. Let's continue.")
    }

    /// Mandatory permission acquisition.
    /// Returns `true` once granted, or `false` if the task is cancelled / view closes.
    /// Strategy:
    ///   1. Try the system dialog ONCE if the permission has never been asked.
    ///   2. If denied, open Settings ONCE and wait for the user to flip the switch.
    ///   3. While waiting, refresh status every 500 ms, prompt every 20 s.
    ///   4. The user can tap the screen to re-open Settings any time
    ///      (handled in `handleTap` — that path is what makes the wait feel responsive).
    ///   5. The `scenePhase` observer also calls `Narrator.stop()` on foreground,
    ///      which immediately resumes any in-flight `speakAndWait` so the loop's
    ///      next iteration sees the granted state without delay.
    private func acquirePermission(
        name: String,
        request: () -> Void,
        isGranted: () -> Bool,
        isNotDetermined: () -> Bool,
        firstAskCopy: String,
        settingsCopy: String,
        settingsGuidance: String
    ) async -> Bool {
        permissionsManager.checkCurrentStatuses()
        if isGranted() { return true }

        // Step 1: try the system dialog once if we've never asked
        if isNotDetermined() {
            statusText = name
            await Narrator.shared.speakAndWait(firstAskCopy)
            guard !Task.isCancelled else { return false }
            request()
            // Wait up to 30 s for the dialog response
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return false }
                permissionsManager.checkCurrentStatuses()
                if isGranted() {
                    await Narrator.shared.speakAndWait("Got it. \(name) is on.")
                    return true
                }
                if !isNotDetermined() { break }  // user denied
            }
            if isGranted() { return true }
        }

        // Step 2: previously denied — open Settings, then wait indefinitely.
        statusText = "Enable \(name)"
        await Narrator.shared.speakAndWait(settingsCopy)
        guard !Task.isCancelled else { return false }

        waitingForSettingsReturn = true
        hasReturnedFromSettings = false
        await openSettings()

        // Step 3: poll until granted. No timeout — both permissions are required.
        // Reminder every 20 s. Foreground / tap interrupts speech so we react fast.
        var elapsedMs = 0
        let reminderEveryMs = 20_000

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                waitingForSettingsReturn = false
                return false
            }
            elapsedMs += 500

            // Belt-and-braces: refresh in case the delegate didn't fire
            permissionsManager.checkCurrentStatuses()
            if isGranted() {
                waitingForSettingsReturn = false
                hasReturnedFromSettings = false
                print("[Setup] \(name) granted — exiting wait loop after \(elapsedMs) ms")
                await Narrator.shared.speakAndWait("Got it. \(name) is on.")
                return true
            }

            // If user just returned from Settings without granting, give one nudge
            if hasReturnedFromSettings {
                hasReturnedFromSettings = false
                await Narrator.shared.speakAndWait(
                    "\(name) still off. \(settingsGuidance) Tap the screen to re-open Settings."
                )
                continue
            }

            // Periodic reminder
            if elapsedMs % reminderEveryMs == 0 {
                await Narrator.shared.speakAndWait(
                    "Waiting for \(name). \(settingsGuidance) Tap the screen to re-open Settings."
                )
            }
        }

        waitingForSettingsReturn = false
        return isGranted()
    }

    // MARK: - Quick Setup: Single Beep Demo

    private func demoBeepsQuick() async {
        statusText = "Demo"

        // Mount guidance first
        await Narrator.shared.speakAndWait("Mount your phone on your chest with camera facing forward.")
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("Quick demo: beeps mean obstacle ahead. Faster means closer.")
        guard !Task.isCancelled else { return }

        // Show medium beep (1.5m)
        hapticsManager.ensureEngine()
        hapticsManager.updateForDistance(1.5)
        try? await Task.sleep(for: .seconds(2.5))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("Tap the screen four times quickly to hear what's in front of you.")
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(0.5))
        await Narrator.shared.speakAndWait("Triple-tap to hear your current location.")
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(0.5))
        await Narrator.shared.speakAndWait("Tap the bottom right button to search for a destination and get walking directions.")
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(0.5))
        await Narrator.shared.speakAndWait("To open settings, double-tap the bottom-left corner of your screen.")
    }

    // MARK: - Quick Setup: Ready

    private func phaseReadyQuick() async {
        phase = .ready
        statusText = "Ready!"

        await Narrator.shared.speakAndWait("Setup complete. Let's go.")
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(0.5))

        // Mark setup as complete
        appState.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "setupComplete")

        // Navigate to Dashboard
        navigateToDashboard = true
    }

    // MARK: - Phase 2: Permissions (Full Setup variant — uses the same helper)

    private func phasePermissions() async {
        phase = .permissions
        statusText = "Permissions"

        await Narrator.shared.speakAndWait(
            "I need two things, both required: your camera so I can detect obstacles and describe surroundings, and your location so I can tell you where you are."
        )
        guard !Task.isCancelled else { return }

        let cameraOK = await acquirePermission(
            name: "Camera",
            request: { permissionsManager.requestCamera() },
            isGranted: { permissionsManager.cameraStatus },
            isNotDetermined: { permissionsManager.cameraNotDetermined },
            firstAskCopy: "First, camera. You'll hear a system prompt — please tap Allow.",
            settingsCopy: "Camera was previously denied. I'll open Settings now. Find Camera and turn it on. When you come back, tap anywhere on the screen to re-open Settings if needed.",
            settingsGuidance: "Find Camera and turn it on."
        )
        guard !Task.isCancelled else { return }
        guard cameraOK else { return }

        let locationOK = await acquirePermission(
            name: "Location",
            request: { permissionsManager.requestLocation() },
            isGranted: { permissionsManager.locationStatus },
            isNotDetermined: { permissionsManager.locationNotDetermined },
            firstAskCopy: "Next, location. You'll hear a system prompt — please tap Allow While Using App.",
            settingsCopy: "Location was previously denied. I'll open Settings now. Tap Location and choose While Using the App. When you come back, tap anywhere on the screen to re-open Settings if needed.",
            settingsGuidance: "Tap Location and choose While Using the App."
        )
        guard !Task.isCancelled else { return }
        guard locationOK else { return }
    }

    /// Open the iOS Settings page for this app
    private func openSettings() async {
        await MainActor.run {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Phase 3: Mount Phone

    private func phaseMountPhone() async {
        phase = .mountPhone
        statusText = "Mount Phone"

        await Narrator.shared.speakAndWait(
            "Now, let's get your phone positioned. Attach your iPhone to your chest using a lanyard, clip, or chest strap. The back camera — that's the one facing away from the screen — should point straight ahead, away from your body."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("Once it's in place, I'll check if the camera can see clearly. Take your time.")
        guard !Task.isCancelled else { return }

        // Camera verification (only if camera was granted)
        if permissionsManager.cameraStatus {
            lidarManager.start()
            try? await Task.sleep(for: .seconds(2)) // Let ARKit warm up
            guard !Task.isCancelled else { return }

            var verified = false
            for attempt in 1...5 {
                guard !Task.isCancelled else { return }

                // Check if LiDAR is getting reasonable depth data
                if lidarManager.closestDistance > 0 && lidarManager.closestDistance < 5.0 {
                    verified = true
                    break
                }

                if attempt < 5 {
                    await Narrator.shared.speakAndWait("Hmm, I'm not seeing clearly yet. Try adjusting the phone so the camera faces straight ahead.")
                    try? await Task.sleep(for: .seconds(3))
                }
            }

            if verified {
                await Narrator.shared.speakAndWait("I can see the space in front of you. Nice work.")
            } else {
                await Narrator.shared.speakAndWait("Let's move on — you can adjust later. I'll show you what the app does.")
            }

            lidarManager.stop()
        } else {
            try? await Task.sleep(for: .seconds(3))
            await Narrator.shared.speakAndWait("Since camera isn't available yet, we'll skip the check. You can adjust the position later.")
        }
    }

    // MARK: - Phase 4: Feature Demo

    private func phaseFeatureDemo() async {
        phase = .featureDemo
        statusText = "How It Works"

        // 4a — Beep demo
        await demoBeeps()
        guard !Task.isCancelled else { return }

        // 4b — Haptic demo
        await demoHaptics()
        guard !Task.isCancelled else { return }

        // 4c — Live camera demo
        if permissionsManager.cameraStatus {
            await demoCameraVision()
            guard !Task.isCancelled else { return }
        }

        // 4d — Explain interaction model
        await Narrator.shared.speakAndWait(
            "To use the app, tap the screen four times quickly and I'll describe what's in front of you. Or shake your phone. Triple-tap to hear your current location. Tap the bottom right button to search for a destination and get walking directions."
        )
    }

    private func demoBeeps() async {
        await Narrator.shared.speakAndWait(
            "Let me show you how obstacle detection works. You'll hear a beep. The faster it beeps, the closer you are to something."
        )
        guard !Task.isCancelled else { return }

        // Demo 1: Slow beep (~3m away)
        hapticsManager.ensureEngine()
        hapticsManager.updateForDistance(2.5) // Far = slow beep
        try? await Task.sleep(for: .seconds(3))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("That means something is about 3 meters away — no rush.")
        guard !Task.isCancelled else { return }

        // Demo 2: Fast beep (~0.5m)
        hapticsManager.updateForDistance(0.5)
        try? await Task.sleep(for: .seconds(3))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("That means something is very close — about half a meter. Slow down.")
        guard !Task.isCancelled else { return }

        // Demo 3: Continuous tone (<0.3m)
        hapticsManager.updateForDistance(0.15)
        try? await Task.sleep(for: .seconds(2))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("And that means stop — obstacle right in front of you.")
    }

    private func demoHaptics() async {
        await Narrator.shared.speakAndWait("You'll also feel vibrations. Let me show you.")
        guard !Task.isCancelled else { return }

        // Medium impact
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.prepare()
        medium.impactOccurred()
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("A pulse like that means I'm reading something to you.")
        guard !Task.isCancelled else { return }

        // Heavy impact
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()
        heavy.impactOccurred()
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("A strong pulse like that means you've activated a button.")
        guard !Task.isCancelled else { return }

        // Warning (notification)
        let warning = UINotificationFeedbackGenerator()
        warning.prepare()
        warning.notificationOccurred(.warning)
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("And that urgent feeling is for emergencies.")
    }

    private func demoCameraVision() async {
        await Narrator.shared.speakAndWait(
            "Let's do a quick test. I'm going to look through your camera right now and describe what I see."
        )
        guard !Task.isCancelled else { return }

        statusText = "Analyzing..."

        // Clear any previous description so we know if this call succeeded
        visionManager.lastDescription = ""

        // Start ARKit if not running
        if !lidarManager.isRunning {
            lidarManager.start()
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
        }

        // Capture and analyze
        visionManager.captureAndAnalyze(from: lidarManager.session)

        // Wait for result (up to 15 seconds)
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if !visionManager.isProcessing { break }
        }

        lidarManager.stop()
        statusText = "How It Works"

        if !visionManager.lastDescription.isEmpty {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            await Narrator.shared.speakAndWait(
                "That's what you'll hear when you double-tap the screen during navigation."
            )
        } else {
            await Narrator.shared.speakAndWait(
                "I couldn't describe the scene this time — that can happen on first try. Don't worry, it will work during navigation. Just double-tap the screen."
            )
        }
    }

    // MARK: - Phase 5: Ready

    private func phaseReady() async {
        phase = .ready
        statusText = "Ready!"

        await Narrator.shared.speakAndWait(
            "Setup complete. You're ready to go. From now on, just open the app, mount your phone, and start walking. I'll keep watch."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait("Let's begin.")

        // Mark setup as complete
        appState.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "setupComplete")

        // Navigate to Dashboard
        navigateToDashboard = true
    }
}
