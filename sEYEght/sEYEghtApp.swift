//
//  sEYEghtApp.swift
//  sEYEght
//
//  Created by Kinshuk on 4/1/26.
//

import SwiftUI
import SwiftData

@main
struct sEYEghtApp: App {
    @State private var appState = AppState()
    @State private var lidarManager = LiDARManager()
    @State private var hapticsManager = HapticsManager()
    @State private var speechManager = SpeechManager()
    @State private var visionManager = VisionManager()
    @State private var navigationManager = NavigationManager()
    @State private var subscriptionManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                OnboardingContainerView()
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
                print("[sEYEghtApp] App launched")
            }
        }
        .modelContainer(for: UserSettings.self)
    }
}
