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
/// One voice, one screen, one conversation.
struct ConversationalSetupView: View {
    @Environment(HapticsManager.self) private var hapticsManager
    @Environment(VisionManager.self) private var visionManager
    @Environment(LiDARManager.self) private var lidarManager
    @Environment(AppState.self) private var appState

    @State private var permissionsManager = PermissionsManager()
    @State private var phase: SetupPhase = .welcome
    @State private var statusText: String = "Setting up..."
    @State private var isPulsing = false
    @State private var navigateToDashboard = false

    enum SetupPhase: Int, CaseIterable {
        case welcome
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
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToDashboard) {
            DashboardView()
        }
        .task {
            isPulsing = true
            defer { Narrator.shared.stop() }
            await runConversation()
        }
    }

    // MARK: - Conversation State Machine

    private func runConversation() async {
        await phaseWelcome()
        guard !Task.isCancelled else { return }

        // Guide user to download better voice if using basic compact voice
        await phaseVoiceCheck()
        guard !Task.isCancelled else { return }

        await phasePermissions()
        guard !Task.isCancelled else { return }

        // Don't continue if mandatory permissions are missing
        guard permissionsManager.cameraStatus && permissionsManager.locationStatus else {
            statusText = "Waiting for permissions..."
            return
        }

        await phaseMountPhone()
        guard !Task.isCancelled else { return }

        await phaseFeatureDemo()
        guard !Task.isCancelled else { return }

        await phaseReady()
    }

    // MARK: - Phase 1: Welcome

    private func phaseWelcome() async {
        phase = .welcome
        statusText = "Welcome"

        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait(
            "Hi there. I'm Seyeght — your personal navigation assistant. I use your iPhone's camera and sensors to detect obstacles around you, warn you with sounds and vibrations, and describe what's in front of you. Let's get you set up. It'll take about two minutes."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait(
            "I'll need a few permissions to work. I'll ask for each one now and explain why."
        )
    }

    // MARK: - Phase 1b: Voice Quality Check

    private func phaseVoiceCheck() async {
        // Already have an enhanced or premium voice — no download needed
        if Narrator.shared.hasHighQualityVoice {
            print("[Setup] Voice quality OK: \(Narrator.shared.voiceDescription)")
            return
        }

        // User has only compact (robotic) voice — guide them to download a better one
        statusText = "Voice Setup"

        await Narrator.shared.speakAndWait(
            "Right now I'm using a basic voice that sounds a bit robotic. Your iPhone can download a much more natural-sounding voice for free. It takes about a minute."
        )
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait(
            "I'm going to open your Settings now. Go to Accessibility, then Spoken Content, then Voices, then English. Tap the download button next to Ava or Samantha Enhanced. When it's done, come back to this app."
        )
        guard !Task.isCancelled else { return }

        // Open Accessibility settings (closest we can get programmatically)
        await MainActor.run {
            if let url = URL(string: "App-prefs:ACCESSIBILITY") {
                UIApplication.shared.open(url)
            }
        }

        // Poll until they come back with an enhanced voice (up to 5 minutes)
        for _ in 0..<600 {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            Narrator.shared.refreshVoice()
            if Narrator.shared.hasHighQualityVoice {
                await Narrator.shared.speakAndWait(
                    "Excellent! I can hear the difference already. \(Narrator.shared.voiceDescription) is loaded. Much better."
                )
                return
            }
        }

        // They came back without downloading — that's OK, continue with what we have
        Narrator.shared.refreshVoice()
        if Narrator.shared.hasHighQualityVoice {
            await Narrator.shared.speakAndWait("Great, new voice is ready. Let's continue.")
        } else {
            await Narrator.shared.speakAndWait(
                "No worries, we'll use the current voice for now. You can always download a better one later in Settings under Accessibility, Spoken Content, Voices."
            )
        }
    }

    // MARK: - Phase 2: Permissions

    private func phasePermissions() async {
        phase = .permissions
        statusText = "Permissions"

        // Camera (mandatory)
        await handlePermission(
            name: "Camera",
            alreadyGranted: permissionsManager.cameraStatus,
            notDetermined: permissionsManager.cameraNotDetermined,
            firstTimePrompt: "First, I need access to your camera. This is how I see obstacles and describe your surroundings. You'll hear a system prompt now — please tap Allow.",
            alreadyDeniedPrompt: "I need camera access, but it was previously denied. I'll open your Settings now — please turn on Camera for Seyeght, then come back.",
            request: { permissionsManager.requestCamera() },
            check: { permissionsManager.cameraStatus },
            grantedMessage: "Perfect. Camera is ready.",
            deniedMessage: "I wasn't able to get camera access. Seyeght really needs the camera to keep you safe."
        )
        guard !Task.isCancelled else { return }

        // Location (mandatory)
        await handlePermission(
            name: "Location",
            alreadyGranted: permissionsManager.locationStatus,
            notDetermined: permissionsManager.locationNotDetermined,
            firstTimePrompt: "Next, I need your location. This helps me tell you where you are when you ask. You'll hear a system prompt — please tap Allow While Using App.",
            alreadyDeniedPrompt: "I need location access, but it was previously denied. I'll open your Settings now — please turn on Location for Seyeght, then come back.",
            request: { permissionsManager.requestLocation() },
            check: { permissionsManager.locationStatus },
            grantedMessage: "Got it. Location is active.",
            deniedMessage: "I wasn't able to get location access. Seyeght needs this to tell you where you are."
        )
        guard !Task.isCancelled else { return }

        // After both have been individually requested, check if any were denied
        if !permissionsManager.cameraStatus || !permissionsManager.locationStatus {
            let missing = [
                !permissionsManager.cameraStatus ? "Camera" : nil,
                !permissionsManager.locationStatus ? "Location" : nil,
            ].compactMap { $0 }.joined(separator: " and ")

            await Narrator.shared.speakWithOpenAIAndWait(
                "I really need \(missing) to keep you safe. I'm opening Settings now. Please enable \(missing) for Seyeght, then come back to the app."
            )
            guard !Task.isCancelled else { return }

            await openSettings()

            // Poll until they come back with permissions granted (or give up after 3 min)
            for _ in 0..<360 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                permissionsManager.checkCurrentStatuses()
                if permissionsManager.cameraStatus && permissionsManager.locationStatus {
                    await Narrator.shared.speakWithOpenAIAndWait("Thank you. All permissions are ready. Let's continue.")
                    break
                }
            }

            if !permissionsManager.cameraStatus || !permissionsManager.locationStatus {
                await Narrator.shared.speakWithOpenAIAndWait(
                    "I still can't access what I need. The app will try again next time you open it."
                )
                return
            }
        }
    }

    /// Handles three permission states: already granted, not yet asked, previously denied.
    private func handlePermission(
        name: String,
        alreadyGranted: Bool,
        notDetermined: Bool,
        firstTimePrompt: String,
        alreadyDeniedPrompt: String?,
        request: @escaping () -> Void,
        check: @escaping () -> Bool,
        grantedMessage: String,
        deniedMessage: String
    ) async {
        statusText = name

        // Already granted — just acknowledge and move on
        if alreadyGranted {
            await Narrator.shared.speakWithOpenAIAndWait("\(name) is already enabled. Great.")
            return
        }

        // Never asked — show the system dialog
        if notDetermined {
            await Narrator.shared.speakWithOpenAIAndWait(firstTimePrompt)
            guard !Task.isCancelled else { return }

            request()

            // Poll — but also detect DENIAL quickly (status changes from notDetermined)
            var granted = false
            for _ in 0..<40 { // 20 seconds max
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                permissionsManager.checkCurrentStatuses()
                if check() {
                    granted = true
                    break
                }
                // If no longer notDetermined AND not granted → user denied
                // (Check the raw status to detect denial immediately)
                if !isStillNotDetermined(name: name) && !check() {
                    break // User explicitly denied — don't keep polling
                }
            }

            if granted {
                await Narrator.shared.speakWithOpenAIAndWait(grantedMessage)
            } else {
                await Narrator.shared.speakWithOpenAIAndWait(deniedMessage)
                // For mandatory: the caller (phasePermissions) handles Settings redirect
            }
            return
        }

        // Previously denied — can't show dialog again
        if let deniedPrompt = alreadyDeniedPrompt {
            await Narrator.shared.speakWithOpenAIAndWait(deniedPrompt)
            guard !Task.isCancelled else { return }

            await openSettings()

            // Wait for user to come back with permission enabled (up to 2 min)
            for _ in 0..<240 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                permissionsManager.checkCurrentStatuses()
                if check() {
                    await Narrator.shared.speakWithOpenAIAndWait(grantedMessage)
                    return
                }
            }
            await Narrator.shared.speakWithOpenAIAndWait(deniedMessage)
        } else {
            // Optional permission, previously denied — just skip
            await Narrator.shared.speakWithOpenAIAndWait("\(name) was previously denied. You can enable it later in Settings if you'd like.")
        }
    }

    /// Check if a permission is still in the not-determined state
    private func isStillNotDetermined(name: String) -> Bool {
        switch name {
        case "Camera": return permissionsManager.cameraNotDetermined
        case "Location": return permissionsManager.locationNotDetermined
        default: return false
        }
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

        await Narrator.shared.speakWithOpenAIAndWait(
            "Now, let's get your phone positioned. Attach your iPhone to your chest using a lanyard, clip, or chest strap. The back camera — that's the one facing away from the screen — should point straight ahead, away from your body."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("Once it's in place, I'll check if the camera can see clearly. Take your time.")
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
                    await Narrator.shared.speakWithOpenAIAndWait("Hmm, I'm not seeing clearly yet. Try adjusting the phone so the camera faces straight ahead.")
                    try? await Task.sleep(for: .seconds(3))
                }
            }

            if verified {
                await Narrator.shared.speakWithOpenAIAndWait("I can see the space in front of you. Nice work.")
            } else {
                await Narrator.shared.speakWithOpenAIAndWait("Let's move on — you can adjust later. I'll show you what the app does.")
            }

            lidarManager.stop()
        } else {
            try? await Task.sleep(for: .seconds(3))
            await Narrator.shared.speakWithOpenAIAndWait("Since camera isn't available yet, we'll skip the check. You can adjust the position later.")
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
        await Narrator.shared.speakWithOpenAIAndWait(
            "To use the app, just double-tap anywhere on the screen and I'll describe what's in front of you. If you ever feel unsafe, triple-tap the screen for emergency mode — I'll announce your location loudly."
        )
    }

    private func demoBeeps() async {
        await Narrator.shared.speakWithOpenAIAndWait(
            "Let me show you how obstacle detection works. You'll hear a beep. The faster it beeps, the closer you are to something."
        )
        guard !Task.isCancelled else { return }

        // Demo 1: Slow beep (~3m away)
        hapticsManager.ensureEngine()
        hapticsManager.updateForDistance(2.5) // Far = slow beep
        try? await Task.sleep(for: .seconds(3))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("That means something is about 3 meters away — no rush.")
        guard !Task.isCancelled else { return }

        // Demo 2: Fast beep (~0.5m)
        hapticsManager.updateForDistance(0.5)
        try? await Task.sleep(for: .seconds(3))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("That means something is very close — about half a meter. Slow down.")
        guard !Task.isCancelled else { return }

        // Demo 3: Continuous tone (<0.3m)
        hapticsManager.updateForDistance(0.15)
        try? await Task.sleep(for: .seconds(2))
        hapticsManager.stopTone()
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("And that means stop — obstacle right in front of you.")
    }

    private func demoHaptics() async {
        await Narrator.shared.speakWithOpenAIAndWait("You'll also feel vibrations. Let me show you.")
        guard !Task.isCancelled else { return }

        // Medium impact
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.prepare()
        medium.impactOccurred()
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("A pulse like that means I'm reading something to you.")
        guard !Task.isCancelled else { return }

        // Heavy impact
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()
        heavy.impactOccurred()
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("A strong pulse like that means you've activated a button.")
        guard !Task.isCancelled else { return }

        // Warning (notification)
        let warning = UINotificationFeedbackGenerator()
        warning.prepare()
        warning.notificationOccurred(.warning)
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("And that urgent feeling is for emergencies.")
    }

    private func demoCameraVision() async {
        await Narrator.shared.speakWithOpenAIAndWait(
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

            await Narrator.shared.speakWithOpenAIAndWait(
                "That's what you'll hear when you double-tap the screen during navigation."
            )
        } else {
            await Narrator.shared.speakWithOpenAIAndWait(
                "I couldn't describe the scene this time — that can happen on first try. Don't worry, it will work during navigation. Just double-tap the screen."
            )
        }
    }

    // MARK: - Phase 5: Ready

    private func phaseReady() async {
        phase = .ready
        statusText = "Ready!"

        await Narrator.shared.speakWithOpenAIAndWait(
            "Setup complete. You're ready to go. From now on, just open the app, mount your phone, and start walking. I'll keep watch."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakWithOpenAIAndWait("Let's begin.")

        // Mark setup as complete
        appState.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "setupComplete")

        // Navigate to Dashboard
        navigateToDashboard = true
    }
}
