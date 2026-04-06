//
//  sEYEghtApp.swift
//  sEYEght
//
//  Created by Kinshuk on 4/1/26.
//

import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation

@main
struct sEYEghtApp: App {
    @State private var appState = AppState()
    @State private var lidarManager = LiDARManager()
    @State private var hapticsManager = HapticsManager()
    @State private var speechManager = SpeechManager()
    @State private var visionManager = VisionManager()
    @State private var navigationManager = NavigationManager()
    @State private var subscriptionManager = SubscriptionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if UserDefaults.standard.bool(forKey: "setupComplete") {
                    DashboardView()
                } else {
                    ConversationalSetupView()
                }
            }
            .environment(appState)
            .environment(lidarManager)
            .environment(hapticsManager)
            .environment(speechManager)
            .environment(visionManager)
            .environment(navigationManager)
            .environment(subscriptionManager)
            .preferredColorScheme(.dark)
            .onAppear {
                // Immediate haptic so blind users know the app launched
                let startupHaptic = UINotificationFeedbackGenerator()
                startupHaptic.notificationOccurred(.success)

                // Configure audio session early so speech works on all screens including onboarding
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
                    try session.setActive(true)
                } catch {
                    print("[sEYEghtApp] Audio session setup error: \(error)")
                }
                print("[sEYEghtApp] App launched")
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    lidarManager.stop()
                    speechManager.stopListening()
                    hapticsManager.stopTone()
                    print("[sEYEghtApp] Entered background — stopped LiDAR/speech")
                case .active:
                    // Re-check critical permissions
                    if UserDefaults.standard.bool(forKey: "setupComplete") {
                        let camOK = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                        let locMgr = CLLocationManager()
                        let locOK = (locMgr.authorizationStatus == .authorizedWhenInUse || locMgr.authorizationStatus == .authorizedAlways)
                        if !camOK || !locOK {
                            Narrator.shared.speak("Seyeght needs camera and location access to keep you safe. Please re-enable them in your iPhone Settings.")
                        }
                    }
                    // Re-start if they were running before (user returned from background)
                    if appState.hasCompletedOnboarding {
                        hapticsManager.ensureEngine()
                        lidarManager.start()
                        speechManager.startListening()
                        print("[sEYEghtApp] Returned to foreground — restarted LiDAR/speech")
                    }
                default:
                    break
                }
            }
        }
        .modelContainer(for: UserSettings.self)
    }
}
