//
//  ShakeDetector.swift
//  sEYEght
//
//  Created by Kinshuk on 4/6/26.
//

import CoreMotion
import Combine

/// Detects shake gestures via accelerometer.
/// For a chest-mounted phone, shaking is far easier than reaching up to double-tap the screen.
final class ShakeDetector {
    static let shared = ShakeDetector()

    private let motionManager = CMMotionManager()
    private var lastShakeTime: Date = .distantPast

    /// Publishes when a shake is detected (with cooldown to prevent rapid firing)
    let shakeDetected = PassthroughSubject<Void, Never>()

    private init() {}

    func start() {
        guard motionManager.isAccelerometerAvailable, !motionManager.isAccelerometerActive else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let total = abs(data.acceleration.x) + abs(data.acceleration.y) + abs(data.acceleration.z)
            // Threshold 3.5g: high enough to avoid walking/stair false positives,
            // low enough for an easy intentional shake
            if total > 3.5 {
                let now = Date()
                guard now.timeIntervalSince(self.lastShakeTime) > 5.0 else { return }
                self.lastShakeTime = now
                print("[ShakeDetector] 📳 Shake detected (acceleration: \(String(format: "%.1f", total))g)")
                self.shakeDetected.send()
            }
        }
        print("[ShakeDetector] Started monitoring")
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
        print("[ShakeDetector] Stopped monitoring")
    }
}
