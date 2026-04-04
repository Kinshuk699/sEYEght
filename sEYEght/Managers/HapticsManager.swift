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

            for frame in 0..<Int(frameCount) {
                // Beep timing
                self.beepTimer += 1.0 / self.sampleRate
                let beepCycle = self.beepOn + self.beepOff
                if self.beepTimer >= beepCycle {
                    self.beepTimer -= beepCycle
                }
                let inBeep = self.beepTimer < self.beepOn

                var sample: Float = 0.0
                if freq > 0 && isEnabled && inBeep {
                    self.tonePhase += 2.0 * .pi * freq / self.sampleRate
                    if self.tonePhase > 2.0 * .pi { self.tonePhase -= 2.0 * .pi }
                    sample = Float(sin(self.tonePhase)) * 0.3 // Volume cap at 0.3
                }

                for buffer in ablPointer {
                    let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                    buf?[frame] = sample
                }
            }
            return noErr
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
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

    /// Update haptic feedback AND audio tone based on obstacle distance.
    func updateForDistance(_ distance: Float) {
        let withinRange = distance < Float(maxRange)

        // Audio tone: map distance to frequency and beep rate
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

        // Haptics
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
