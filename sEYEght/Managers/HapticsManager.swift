//
//  HapticsManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import CoreHaptics
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// F-002: Dynamic Haptic & Audio Radar.
/// Maps closest depth point to haptic intensity AND an audio proximity tone.
@Observable
final class HapticsManager {
    private var isSetup = false

    /// User-configurable intensity multiplier (0.0 to 1.0)
    var userIntensityLevel: Double = 0.5

    /// Whether haptic vibrations are enabled (user can toggle)
    var hapticsEnabled: Bool = true

    /// Whether audio proximity tones are enabled (off by default, user enables in Settings)
    var audioToneEnabled: Bool = false

    /// Volume of the proximity beep tone: 0.0 (silent) to 1.0 (full)
    var audioToneVolume: Float = 0.04

    /// Maximum detection range in meters
    var maxRange: Double = 1.5

    // MARK: - UIKit Haptic Generators (work alongside AVAudioEngine)

    #if canImport(UIKit)
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    #endif

    // MARK: - Audio Tone Properties

    private var audioEngine: AVAudioEngine?
    private var toneSourceNode: AVAudioSourceNode?
    private var tonePhase: Double = 0.0
    private var toneFrequency: Double = 0.0 // 0 = silent
    private let sampleRate: Double = 44100.0

    /// Beeping: tone plays for `beepOn` then silent for `beepOff`
    private var beepOn: Double = 0.08
    private var beepOff: Double = 0.5
    private var beepTimer: Double = 0.0
    private var beepActive: Bool = true

    /// Stereo panning: -1.0 = full left, 0.0 = center, 1.0 = full right
    private var tonePan: Float = 0.0

    init() {
        // UIKit generators are ready immediately — no deferred setup needed
    }

    func ensureEngine() {
        guard !isSetup else { return }
        isSetup = true
        print("[HapticsManager] \u{2705} Engine setup (UIKit generators), hapticsEnabled=\(hapticsEnabled), intensity=\(userIntensityLevel)")
        // Prepare haptic generators for lower latency
        #if canImport(UIKit)
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        #endif
        // Only start the beep audio engine if the user has enabled beeps
        if audioToneEnabled {
            setupAudioTone()
        }
    }

    /// Start the beep audio engine on demand (called when user enables beeps in Settings)
    func startAudioToneIfNeeded() {
        guard audioToneEnabled, audioEngine == nil else { return }
        setupAudioTone()
    }

    /// Stop the beep audio engine (called when user disables beeps in Settings)
    func stopAudioTone() {
        audioEngine?.stop()
        if let node = toneSourceNode {
            audioEngine?.detach(node)
        }
        audioEngine = nil
        toneSourceNode = nil
        toneFrequency = 0
    }

    // MARK: - Audio Proximity Tone

    private func setupAudioTone() {
        let engine = AVAudioEngine()

        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = self.toneFrequency
            let isEnabled = self.audioToneEnabled
            let pan = self.tonePan  // -1 = left, 0 = center, +1 = right

            // Stereo gains: equal-power panning
            let leftGain = self.audioToneVolume * min(1.0, 1.0 - pan)
            let rightGain = self.audioToneVolume * min(1.0, 1.0 + pan)

            for frame in 0..<Int(frameCount) {
                // Beep timing
                self.beepTimer += 1.0 / self.sampleRate
                let beepCycle = self.beepOn + self.beepOff
                if self.beepTimer >= beepCycle {
                    self.beepTimer -= beepCycle
                }
                let inBeep = self.beepTimer < self.beepOn

                var rawSample: Float = 0.0
                if freq > 0 && isEnabled && inBeep {
                    self.tonePhase += 2.0 * .pi * freq / self.sampleRate
                    if self.tonePhase > 2.0 * .pi { self.tonePhase -= 2.0 * .pi }
                    rawSample = Float(sin(self.tonePhase))
                }

                // Write stereo: channel 0 = left, channel 1 = right
                for (index, buffer) in ablPointer.enumerated() {
                    let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                    let gain = index == 0 ? leftGain : rightGain
                    buf?[frame] = rawSample * gain
                }
            }
            return noErr
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.toneSourceNode = sourceNode
            print("[HapticsManager] ✅ Audio proximity tone started")
        } catch {
            print("[HapticsManager] ❌ Audio tone failed to start: \(error)")
        }
    }

    /// Throttle: max 5 haptic events per second
    private var lastHapticTime: Date = .distantPast
    private let hapticInterval: TimeInterval = 0.2  // 5 per second

    /// Update haptic feedback AND audio tone based on obstacle distance and direction.
    /// `normalizedX`: 0.0 = far left, 0.5 = center, 1.0 = far right
    func updateForDistance(_ distance: Float, normalizedX: Float = 0.5) {
        let withinRange = distance < Float(maxRange)

        // Stereo panning: convert 0..1 → -1..+1
        tonePan = (normalizedX * 2.0) - 1.0

        // Audio tone: map distance to frequency and beep rate (this is cheap, no throttle needed)
        if withinRange {
            let normalized = max(0, min(1, Double(distance) / maxRange))
            // Frequency: 300 Hz (far) → 1200 Hz (very close)
            toneFrequency = 300 + (1.0 - normalized) * 900
            // Beep interval: 0.5s (far) → 0.06s (very close) — faster beeps when closer
            beepOff = 0.06 + normalized * 0.44
            beepOn = 0.06 + (1.0 - normalized) * 0.04 // Slightly longer beep when close
        } else {
            toneFrequency = 0 // Silent
        }

        // Haptics — throttled to avoid rate-limit warnings and respects user preference
        guard hapticsEnabled else {
            print("[HapticsManager] ❌ BLOCKED: hapticsEnabled=false")
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= hapticInterval else { return } // throttle — silent
        lastHapticTime = now
        guard withinRange else {
            print("[HapticsManager] ❌ BLOCKED: out of range dist=\(distance) max=\(maxRange)")
            return
        }

        let normalizedDistance = max(0, min(1, Double(distance) / maxRange))
        let intensity = (1.0 - normalizedDistance) * userIntensityLevel

        guard intensity > 0.05 else {
            print("[HapticsManager] ❌ BLOCKED: intensity too low=\(intensity) userLevel=\(userIntensityLevel)")
            return
        }

        // UIKit haptic generators — MUST run on main thread
        #if canImport(UIKit)
        DispatchQueue.main.async { [self] in
            if intensity > 0.6 {
                heavyGenerator.prepare()
                heavyGenerator.impactOccurred(intensity: CGFloat(min(1.0, intensity)))
            } else if intensity > 0.3 {
                mediumGenerator.prepare()
                mediumGenerator.impactOccurred(intensity: CGFloat(intensity))
            } else {
                lightGenerator.prepare()
                lightGenerator.impactOccurred(intensity: CGFloat(intensity))
            }
            print("[HapticsManager] ✅ Haptic fired: dist=\(String(format: "%.2f", distance))m intensity=\(String(format: "%.2f", intensity)) thread=\(Thread.isMainThread ? "main" : "bg")")
        }
        #endif
    }

    /// Stop audio tone (e.g., when leaving Dashboard)
    func stopTone() {
        toneFrequency = 0
    }
}
