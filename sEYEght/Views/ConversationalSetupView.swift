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
    @Environment(SpeechManager.self) private var speechManager
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
            Color.black.ignoresSafeArea()

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
            await runConversation()
        }
    }

    // MARK: - Conversation State Machine

    private func runConversation() async {
        await phaseWelcome()
        guard !Task.isCancelled else { return }

        await phasePermissions()
        guard !Task.isCancelled else { return }

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

        await Narrator.shared.speakAndWait(
            "Hi there. I'm Seyeght — your personal navigation assistant. I use your iPhone's camera and sensors to detect obstacles around you, warn you with sounds and vibrations, and describe what's in front of you. Let's get you set up. It'll take about two minutes."
        )
        guard !Task.isCancelled else { return }

        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait(
            "I'll need a few permissions to work. I'll ask for each one now and explain why."
        )
    }

    // MARK: - Phase 2: Permissions

    private func phasePermissions() async {
        phase = .permissions
        statusText = "Permissions"

        // Camera (mandatory)
        await requestPermission(
            name: "Camera",
            prompt: "First, I need access to your camera. This is how I see obstacles and describe your surroundings. You'll hear a system prompt now — please tap Allow.",
            request: { permissionsManager.requestCamera() },
            check: { permissionsManager.cameraStatus },
            isMandatory: true,
            grantedMessage: "Perfect. Camera is ready.",
            deniedMessage: "I wasn't able to get camera access. Seyeght really needs the camera to keep you safe."
        )
        guard !Task.isCancelled else { return }

        // Location (mandatory)
        await requestPermission(
            name: "Location",
            prompt: "Next, I need your location. This helps me tell you where you are when you ask. You'll hear a system prompt — please tap Allow While Using App.",
            request: { permissionsManager.requestLocation() },
            check: { permissionsManager.locationStatus },
            isMandatory: true,
            grantedMessage: "Got it. Location is active.",
            deniedMessage: "I wasn't able to get location access. Seyeght needs this to tell you where you are."
        )
        guard !Task.isCancelled else { return }

        // Check mandatory permissions
        if !permissionsManager.cameraStatus || !permissionsManager.locationStatus {
            await Narrator.shared.speakAndWait(
                "I can't work without the camera and location. You can grant these in your iPhone's Settings app under Seyeght. I'll check again when you come back."
            )
            return
        }

        // Microphone (optional)
        await requestPermission(
            name: "Microphone",
            prompt: "I'd also like access to your microphone, so you can use voice commands. This is optional. You'll hear a prompt now.",
            request: { permissionsManager.requestMicrophone() },
            check: { permissionsManager.microphoneStatus },
            isMandatory: false,
            grantedMessage: "Microphone ready. You'll be able to talk to me.",
            deniedMessage: "No problem. Voice commands won't be available, but everything else works fine."
        )
        guard !Task.isCancelled else { return }

        // Speech Recognition (optional)
        await requestPermission(
            name: "Speech Recognition",
            prompt: "Last one — speech recognition. This helps me understand what you say. Again, optional.",
            request: { permissionsManager.requestSpeechRecognition() },
            check: { permissionsManager.speechStatus },
            isMandatory: false,
            grantedMessage: "All set.",
            deniedMessage: "That's okay. I'll skip voice commands."
        )
    }

    private func requestPermission(
        name: String,
        prompt: String,
        request: @escaping () -> Void,
        check: @escaping () -> Bool,
        isMandatory: Bool,
        grantedMessage: String,
        deniedMessage: String
    ) async {
        statusText = name

        await Narrator.shared.speakAndWait(prompt)
        guard !Task.isCancelled else { return }

        // Trigger the system permission dialog
        request()

        // Poll for result (system dialog is async — wait up to 30s)
        var granted = false
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            permissionsManager.checkCurrentStatuses()
            if check() {
                granted = true
                break
            }
        }

        if granted {
            await Narrator.shared.speakAndWait(grantedMessage)
        } else {
            await Narrator.shared.speakAndWait(deniedMessage)
            // Retry once for mandatory permissions
            if isMandatory {
                await Narrator.shared.speakAndWait("Let me try one more time.")
                request()
                for _ in 0..<30 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    permissionsManager.checkCurrentStatuses()
                    if check() {
                        await Narrator.shared.speakAndWait(grantedMessage)
                        return
                    }
                }
                await Narrator.shared.speakAndWait("Still not granted. You can enable \(name) later in your iPhone Settings under Seyeght.")
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

        // 4c — Voice command practice
        if permissionsManager.microphoneStatus && permissionsManager.speechStatus {
            await demoVoiceCommands()
            guard !Task.isCancelled else { return }
        }

        // 4d — Live camera demo
        if permissionsManager.cameraStatus {
            await demoCameraVision()
            guard !Task.isCancelled else { return }
        }
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

    private func demoVoiceCommands() async {
        await Narrator.shared.speakAndWait("You can talk to me too. Let's practice. Say Hey Sight now.")
        guard !Task.isCancelled else { return }

        // Listen for wake phrase using a continuation
        let heard = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            var resumed = false
            speechManager.onWakeWordDetected = {
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: true)
            }
            speechManager.startListening()

            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: false)
            }
        }

        speechManager.onWakeWordDetected = nil
        speechManager.stopListening()

        if heard {
            await Narrator.shared.speakAndWait(
                "I heard you! When you say that during navigation, I'll describe what's around you."
            )
        } else {
            await Narrator.shared.speakAndWait(
                "I didn't catch that — no worries. You can always try again later. Say Hey Sight anytime during navigation."
            )
        }
        guard !Task.isCancelled else { return }

        await Narrator.shared.speakAndWait(
            "You can also say 'Where am I' anytime to hear your current street address. And if you ever feel unsafe, triple-tap the screen for emergency mode — I'll announce your location loudly."
        )
    }

    private func demoCameraVision() async {
        await Narrator.shared.speakAndWait(
            "Let's do a quick test. I'm going to look through your camera right now and describe what I see."
        )
        guard !Task.isCancelled else { return }

        statusText = "Analyzing..."

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
                "That's what you'll hear when you tap the screen or say Hey Sight during navigation."
            )
        } else {
            await Narrator.shared.speakAndWait(
                "The scene description feature needs a bit more setup. You'll be able to use it later — just tap the screen during navigation."
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
