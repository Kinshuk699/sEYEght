//
//  HapticsManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import CoreHaptics
import AVFoundation

/// F-002: Dynamic Haptic & Audio Radar.
/// Maps closest depth point to haptic intensity AND an audio proximity tone.
@Observable
final class HapticsManager {
    private var engine: CHHapticEngine?
    private var isSetup = false

    /// User-configurable intensity multiplier (0.0 to 1.0)
    var userIntensityLevel: Double = 0.5

    /// Whether audio proximity tones are enabled (user can toggle)
    var audioToneEnabled: Bool = true

    /// Volume of the proximity beep tone: 0.0 (silent) to 1.0 (full)
    var audioToneVolume: Float = 0.15

    /// Maximum detection range in meters
    var maxRange: Double = 1.5

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
        // Defer engine setup — CoreHaptics needs the app to be fully active
    }

    func ensureEngine() {
        guard !isSetup else { return }
        isSetup = true
        setupEngine()
        setupAudioTone()
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

        // Haptics — throttled to avoid rate-limit warnings
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= hapticInterval else { return }
        lastHapticTime = now
        guard let engine = engine, withinRange else { return }

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

    /// Stop audio tone (e.g., when leaving Dashboard)
    func stopTone() {
        toneFrequency = 0
    }
}
