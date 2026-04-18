//
//  UserSettings.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import Foundation
import SwiftData

@Model
final class UserSettings {
    /// Haptic intensity level: 0.0 (off) to 1.0 (max)
    var hapticIntensityLevel: Double = 1.0

    /// Maximum radar detection range in meters
    var radarRangeMeters: Double = 1.5

    /// AI speech rate: 0.3 (slow) to 0.7 (fast), default 0.5
    var speechRate: Double = 0.5

    /// Audio proximity beep volume: 0.0 (off) to 0.5 (max), default 0.05 (quiet)
    var beepVolume: Double = 0.05

    /// Whether user has completed onboarding
    var hasCompletedOnboarding: Bool = false

    // MARK: - Feedback Preferences

    /// Voice narration enabled (AI descriptions, alerts, UI reading)
    var voiceEnabled: Bool = true

    /// Proximity beep tones enabled (off by default — user can enable in Settings)
    var beepsEnabled: Bool = false

    /// Haptic vibration feedback enabled
    var hapticsEnabled: Bool = true

    /// Returns true if at least one feedback type is enabled (safety requirement)
    func hasAtLeastOneFeedback() -> Bool {
        voiceEnabled || beepsEnabled || hapticsEnabled
    }

    init() {
    }
}
