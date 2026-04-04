//
//  PermissionsView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import AVFoundation

/// S-002: Sequential permission granting screen.
struct PermissionsView: View {
    @State private var permissionsManager = PermissionsManager()
    @State private var navigateToDashboard = false
    @State private var screenSynth = AVSpeechSynthesizer()

    var body: some View {
        VStack(spacing: 0) {
            Text("Permissions")
                .font(SeyeghtTheme.largeTitle)
                .foregroundColor(SeyeghtTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Text("Seyeght needs these to keep you safe")
                .font(SeyeghtTheme.body)
                .foregroundColor(SeyeghtTheme.secondaryText)
                .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 16) {
                    PermissionCard(
                        iconName: "camera.fill",
                        title: "Camera Access",
                        description: "Needed for LiDAR scanning",
                        isGranted: permissionsManager.cameraStatus,
                        onGrant: { permissionsManager.requestCamera() }
                    )

                    PermissionCard(
                        iconName: "location.fill",
                        title: "Location Access",
                        description: "Used for spatial awareness",
                        isGranted: permissionsManager.locationStatus,
                        onGrant: { permissionsManager.requestLocation() }
                    )

                    PermissionCard(
                        iconName: "mic.fill",
                        title: "Microphone Access",
                        description: "For voice commands",
                        isGranted: permissionsManager.microphoneStatus,
                        onGrant: { permissionsManager.requestMicrophone() }
                    )

                    PermissionCard(
                        iconName: "waveform",
                        title: "Speech Recognition",
                        description: "For wake word detection",
                        isGranted: permissionsManager.speechStatus,
                        onGrant: { permissionsManager.requestSpeechRecognition() }
                    )
                }
            }

            Spacer()

            HapticButton("Continue", isEnabled: permissionsManager.allGranted) {
                print("[PermissionsView] All permissions granted, navigating to Dashboard")
                navigateToDashboard = true
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, SeyeghtTheme.horizontalPadding)
        .background(SeyeghtTheme.background)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToDashboard) {
            DashboardView()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let utterance = AVSpeechUtterance(string: "Permissions screen. Seyeght needs Camera, Location, Microphone, and Speech Recognition. Tap each Grant button to allow. Once all are granted, tap Continue at the bottom.")
                utterance.rate = 0.45
                utterance.volume = 0.9
                screenSynth.speak(utterance)
            }
        }
    }
}
