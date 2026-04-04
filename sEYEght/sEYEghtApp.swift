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

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                OnboardingContainerView()
            }
            .environment(appState)
            .preferredColorScheme(.dark)
            .onAppear {
                print("[sEYEghtApp] App launched")
            }
        }
        .modelContainer(for: UserSettings.self)
    }
}
