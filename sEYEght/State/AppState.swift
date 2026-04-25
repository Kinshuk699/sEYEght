//
//  AppState.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import Foundation
import Observation

@Observable
final class AppState {
    // MARK: - Session
    var hasCompletedOnboarding = false
    /// Prevents re-announcing "Sight ready" when returning from background
    var hasAnnouncedWelcomeThisSession = false

    init() {
        // Restore onboarding state from disk so returning users go straight to Dashboard
        if UserDefaults.standard.bool(forKey: "setupComplete") {
            hasCompletedOnboarding = true
        }
        print("[AppState] Initialized, setupComplete=\(hasCompletedOnboarding)")
    }
}
