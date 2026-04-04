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
    var hapticIntensityLevel: Double = 0.5

    /// Maximum radar detection range in meters
    var radarRangeMeters: Double = 1.5

    /// AI speech rate: 0.3 (slow) to 0.7 (fast), default 0.5
    var speechRate: Double = 0.5

    /// Whether user has completed onboarding
    var hasCompletedOnboarding: Bool = false

    init() {
        print("[UserSettings] Initialized with defaults")
    }
}
