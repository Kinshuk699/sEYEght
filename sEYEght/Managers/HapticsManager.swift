//
//  HapticsManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import CoreHaptics
import AVFoundation
import UIKit

/// F-002: Discrete-zone Haptic & Audio Radar.
///
/// Silent by default. The phone is QUIET when the path is clear. We only
/// signal when the user crosses into a new proximity zone:
///
///   - CAUTION  (≤ 1.5 m): single soft tap + 220 Hz blip
///   - WARNING  (≤ 1.0 m): double tap        + 440 Hz blip
///   - DANGER   (≤ 0.5 m): triple sharp tap  + 880 Hz urgent tone, repeats 1×/s
///   - ALL CLEAR(> 1.5 m + hysteresis): one soft "ding" + 660 Hz blip
///
/// Hysteresis (0.15 m) prevents chatter when distance jitters around a
/// threshold. No constant beeping, no habituation, no noise.
@Observable
final class HapticsManager {
    private var isSetup = false

    enum ProximityZone: Int, Comparable {
        case clear = 0      // > 1.5 m
        case caution = 1    // 0.5 < d ≤ 1.5 m
        case warning = 2    // 0.3 < d ≤ 1.0 m
        case danger = 3     // d ≤ 0.5 m

        static func < (lhs: ProximityZone, rhs: ProximityZone) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Current zone — observable so views can react if they want to.
    private(set) var currentZone: ProximityZone = .clear

    /// User-configurable intensity multiplier (0.0 to 1.0)
    var userIntensityLevel: Double = 1.0

    /// Whether haptic vibrations are enabled (user can toggle)
    var hapticsEnabled: Bool = true

    /// Whether audio proximity tones are enabled (off by default, user enables in Settings)
    var audioToneEnabled: Bool = false

    /// Volume of the proximity blip tones: 0.0 (silent) to 1.0 (full)
    var audioToneVolume: Float = 0.4

    /// Maximum detection range in meters — anything farther is "clear".
    var maxRange: Double = 1.5

    // MARK: - Zone thresholds (entry / exit pairs for hysteresis)
    // Enter a tighter zone at the listed distance; leave it only once you've
    // moved 0.15 m back out. Prevents flicker when the LiDAR depth jitters.
    private let cautionEnter: Float = 1.50
    private let cautionExit:  Float = 1.65
    private let warningEnter: Float = 1.00
    private let warningExit:  Float = 1.15
    private let dangerEnter:  Float = 0.50
    private let dangerExit:   Float = 0.65

    // MARK: - UIKit Haptic Generators
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Audio Tone Properties (transient blips, NOT continuous beeping)

    private var audioEngine: AVAudioEngine?
    private var toneSourceNode: AVAudioSourceNode?
    private var tonePhase: Double = 0.0
    private var toneFrequency: Double = 0.0   // 0 = silent
    private var toneRemainingFrames: Int = 0  // counts down per audio frame; 0 = stop
    private let sampleRate: Double = 44100.0

    /// Stereo panning: -1.0 = full left, 0.0 = center, +1.0 = full right
    private var tonePan: Float = 0.0

    /// Track danger-zone repeat timing — fires the urgent pattern 1×/sec while in danger.
    private var lastDangerRepeat: Date = .distantPast
    private let dangerRepeatInterval: TimeInterval = 1.0

    init() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        rigidGenerator.prepare()
        notificationGenerator.prepare()
    }

    func ensureEngine() {
        guard !isSetup else { return }
        isSetup = true
        print("[HapticsManager] ✅ Engine ready (silent-by-default), hapticsEnabled=\(hapticsEnabled), intensity=\(userIntensityLevel)")
        if audioToneEnabled {
            setupAudioTone()
        }
    }

    /// Start the audio engine on demand (called when user enables tones in Settings)
    func startAudioToneIfNeeded() {
        guard audioToneEnabled, audioEngine == nil else { return }
        setupAudioTone()
    }

    /// Stop the audio engine (called when user disables tones in Settings)
    func stopAudioTone() {
        audioEngine?.stop()
        if let node = toneSourceNode {
            audioEngine?.detach(node)
        }
        audioEngine = nil
        toneSourceNode = nil
        toneFrequency = 0
        toneRemainingFrames = 0
    }

    // MARK: - Audio Blip Engine
    //
    // We render a sine wave for `toneRemainingFrames` audio frames, then go
    // silent. To play a fresh blip, call `playBlip(freq:duration:)` which
    // reseeds frequency + duration. No continuous beeping anywhere.

    private func setupAudioTone() {
        let engine = AVAudioEngine()

        let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let pan = self.tonePan
            let leftGain = self.audioToneVolume * min(1.0, 1.0 - pan)
            let rightGain = self.audioToneVolume * min(1.0, 1.0 + pan)

            for frame in 0..<Int(frameCount) {
                var rawSample: Float = 0.0
                if self.toneRemainingFrames > 0 && self.toneFrequency > 0 && self.audioToneEnabled {
                    self.tonePhase += 2.0 * .pi * self.toneFrequency / self.sampleRate
                    if self.tonePhase > 2.0 * .pi { self.tonePhase -= 2.0 * .pi }
                    rawSample = Float(sin(self.tonePhase))
                    self.toneRemainingFrames -= 1
                }
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
            print("[HapticsManager] ✅ Blip engine ready")
        } catch {
            print("[HapticsManager] ❌ Audio blip engine failed: \(error)")
        }
    }

    /// Play a single blip (pure tone burst) at `freq` Hz for `duration` seconds.
    /// Called only on zone transitions, not continuously.
    private func playBlip(freq: Double, duration: TimeInterval) {
        guard audioToneEnabled else { return }
        toneFrequency = freq
        toneRemainingFrames = Int(duration * sampleRate)
        // Engine may not be started yet (lazy) — start it.
        startAudioToneIfNeeded()
    }

    // MARK: - Public API
    //
    // The dashboard calls `updateForDistance` every LiDAR frame (~12 Hz). We
    // do all our own zone tracking and only emit haptics + audio + speech
    // requests on actual zone *transitions* (or repeats while in danger).

    /// Computes the proximity zone for `distance` given the current zone
    /// (so we can use hysteresis: the exit threshold is looser than entry).
    private func zoneFor(distance: Float, current: ProximityZone) -> ProximityZone {
        switch current {
        case .clear:
            if distance <= dangerEnter { return .danger }
            if distance <= warningEnter { return .warning }
            if distance <= cautionEnter { return .caution }
            return .clear
        case .caution:
            if distance <= dangerEnter { return .danger }
            if distance <= warningEnter { return .warning }
            if distance > cautionExit { return .clear }
            return .caution
        case .warning:
            if distance <= dangerEnter { return .danger }
            if distance > warningExit { return .caution }
            return .warning
        case .danger:
            if distance > dangerExit { return .warning }
            return .danger
        }
    }

    /// Call from the LiDAR observer. Returns the **transition** that occurred,
    /// if any, so the view layer can speak appropriate context.
    /// `normalizedX`: 0.0 = far left, 0.5 = center, 1.0 = far right.
    @discardableResult
    func updateForDistance(_ distance: Float, normalizedX: Float = 0.5) -> ZoneTransition? {
        // Stereo pan tracks the obstacle for any blip we play this tick.
        tonePan = (normalizedX * 2.0) - 1.0

        let previousZone = currentZone
        let newZone = zoneFor(distance: distance, current: previousZone)

        if newZone != previousZone {
            currentZone = newZone
            let transition = ZoneTransition(from: previousZone, to: newZone, distance: distance, normalizedX: normalizedX)
            firePattern(for: transition)
            return transition
        }

        // Same zone — only repeat the urgent pattern if we're still in DANGER.
        if newZone == .danger {
            let now = Date()
            if now.timeIntervalSince(lastDangerRepeat) >= dangerRepeatInterval {
                lastDangerRepeat = now
                fireDangerPattern()
            }
        }

        return nil
    }

    struct ZoneTransition {
        let from: ProximityZone
        let to: ProximityZone
        let distance: Float
        let normalizedX: Float

        /// True when crossing into a tighter (more dangerous) zone.
        var isEscalation: Bool { to.rawValue > from.rawValue }
    }

    private func firePattern(for transition: ZoneTransition) {
        switch transition.to {
        case .clear:
            // All-clear: single soft "ding"
            fireAllClearPattern()
        case .caution:
            fireCautionPattern()
        case .warning:
            fireWarningPattern()
        case .danger:
            lastDangerRepeat = Date()
            fireDangerPattern()
        }
    }

    private func fireCautionPattern() {
        guard hapticsEnabled else { return }
        mediumGenerator.impactOccurred(intensity: CGFloat(0.5 * userIntensityLevel))
        mediumGenerator.prepare()
        playBlip(freq: 220, duration: 0.20)
        print("[HapticsManager] · CAUTION (1 tap, 220 Hz)")
    }

    private func fireWarningPattern() {
        guard hapticsEnabled else { return }
        heavyGenerator.impactOccurred(intensity: CGFloat(0.75 * userIntensityLevel))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self = self else { return }
            self.heavyGenerator.impactOccurred(intensity: CGFloat(0.75 * self.userIntensityLevel))
            self.heavyGenerator.prepare()
        }
        playBlip(freq: 440, duration: 0.18)
        print("[HapticsManager] ·· WARNING (2 taps, 440 Hz)")
    }

    private func fireDangerPattern() {
        guard hapticsEnabled else { return }
        rigidGenerator.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            self.rigidGenerator.impactOccurred(intensity: 1.0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self = self else { return }
            self.rigidGenerator.impactOccurred(intensity: 1.0)
            self.rigidGenerator.prepare()
            self.notificationGenerator.notificationOccurred(.error)
            self.notificationGenerator.prepare()
        }
        playBlip(freq: 880, duration: 0.30)
        print("[HapticsManager] ··· DANGER (3 taps + alert, 880 Hz)")
    }

    private func fireAllClearPattern() {
        guard hapticsEnabled else { return }
        lightGenerator.impactOccurred(intensity: CGFloat(0.6 * userIntensityLevel))
        lightGenerator.prepare()
        playBlip(freq: 660, duration: 0.12)
        print("[HapticsManager] ✓ ALL CLEAR (soft tap, 660 Hz)")
    }

    /// Stop any ringing tone (e.g., when leaving Dashboard).
    func stopTone() {
        toneRemainingFrames = 0
        toneFrequency = 0
    }
}
