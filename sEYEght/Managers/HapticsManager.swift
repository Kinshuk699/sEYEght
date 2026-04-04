//
//  HapticsManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import CoreHaptics

/// F-002: Dynamic Haptic & Audio Radar.
/// Maps closest depth point to haptic intensity.
final class HapticsManager {
    private var engine: CHHapticEngine?

    /// User-configurable intensity multiplier (0.0 to 1.0)
    var userIntensityLevel: Double = 0.5

    /// Maximum detection range in meters
    var maxRange: Double = 1.5

    init() {
        setupEngine()
    }

    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("[HapticsManager] ❌ Device does not support haptics")
            return
        }

        do {
            engine = try CHHapticEngine()
            engine?.resetHandler = { [weak self] in
                print("[HapticsManager] Engine reset, restarting")
                try? self?.engine?.start()
            }
            try engine?.start()
            print("[HapticsManager] ✅ Haptic engine started")
        } catch {
            print("[HapticsManager] ❌ Failed to start engine: \(error)")
        }
    }

    /// Update haptic feedback based on obstacle distance.
    func updateForDistance(_ distance: Float) {
        guard let engine = engine, distance < Float(maxRange) else {
            return
        }

        let normalizedDistance = max(0, min(1, Double(distance) / maxRange))
        let intensity = (1.0 - normalizedDistance) * userIntensityLevel
        let sharpness = normalizedDistance < 0.2 ? 1.0 : 0.5

        do {
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))

            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: 0,
                duration: 0.2
            )

            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("[HapticsManager] ❌ Haptic playback error: \(error)")
        }
    }
}
