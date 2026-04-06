//
//  Narrator.swift
//  sEYEght
//
//  Created by Kinshuk on 4/4/26.
//

import AVFoundation
import SwiftUI

/// Single shared speech output for the entire app.
/// Any new speech automatically stops whatever was playing before.
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    /// Best available voice — prefers enhanced/premium in user's locale
    private var selectedVoice: AVSpeechSynthesisVoice?

    /// Whether we're using a high-quality voice (enhanced or premium)
    var hasHighQualityVoice: Bool {
        guard let voice = selectedVoice else { return false }
        return voice.quality == .enhanced || voice.quality == .premium
    }

    private override init() {
        selectedVoice = Self.pickBestVoice()
        super.init()
        synth.delegate = self
        if let voice = selectedVoice {
            print("[Narrator] Using voice: \(voice.name) id=\(voice.identifier) quality=\(voice.quality.rawValue)")
        } else {
            print("[Narrator] ⚠️ No good voice found — using system default (robotic)")
        }
    }

    /// Re-select the best available voice (call after user downloads an enhanced voice)
    func refreshVoice() {
        selectedVoice = Self.pickBestVoice()
        if let voice = selectedVoice {
            print("[Narrator] \u{1f504} Voice refreshed: \(voice.name) quality=\(voice.quality.rawValue)")
        }
    }

    private static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Log all English voices for debugging
        let enVoices = voices.filter { $0.language.hasPrefix("en") }
        print("[Narrator] Available English voices (\(enVoices.count)):")
        for v in enVoices.sorted(by: { $0.quality.rawValue > $1.quality.rawValue }) {
            print("  - \(v.name) | \(v.language) | quality=\(v.quality.rawValue) | id=\(v.identifier)")
        }

        // 1. Premium (requires download — best quality)
        if let v = enVoices.first(where: { $0.quality == .premium }) {
            print("[Narrator] ✅ Found premium voice: \(v.name)")
            return v
        }

        // 2. Enhanced by name preference (requires download)
        let preferred = ["Ava", "Samantha", "Allison", "Zoe", "Susan", "Victoria"]
        for name in preferred {
            if let v = enVoices.first(where: { $0.quality == .enhanced && $0.name.contains(name) }) {
                print("[Narrator] ✅ Found enhanced voice: \(v.name)")
                return v
            }
        }

        // 3. Any enhanced
        if let v = enVoices.first(where: { $0.quality == .enhanced }) {
            print("[Narrator] ✅ Found enhanced voice: \(v.name)")
            return v
        }

        // 4. Best compact voices — these are always available, no download needed
        // "Samantha" is the classic Siri voice and sounds less robotic than others
        let compactPreferred = ["Samantha", "Ava", "Allison", "Zoe", "Nicky", "Karen"]
        for name in compactPreferred {
            if let v = enVoices.first(where: { $0.name.contains(name) }) {
                print("[Narrator] Using compact voice: \(v.name)")
                return v
            }
        }

        // 5. Any English voice at all
        if let v = enVoices.first {
            print("[Narrator] Falling back to: \(v.name)")
            return v
        }

        return nil
    }

    /// Speak text, stopping any current speech first.
    func speak(_ text: String, rate: Float = 0.45, volume: Float = 0.9) {
        synth.stopSpeaking(at: .immediate)
        // Cancel any pending speakAndWait continuation
        continuation?.resume()
        continuation = nil

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume
        if let voice = selectedVoice {
            utterance.voice = voice
        }
        synth.speak(utterance)
    }

    /// Speak text and wait until speech finishes. Cancellation-safe.
    func speakAndWait(_ text: String, rate: Float = 0.45, volume: Float = 0.9) async {
        speak(text, rate: rate, volume: volume)
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    /// Stop any current speech immediately.
    func stop() {
        synth.stopSpeaking(at: .immediate)
        continuation?.resume()
        continuation = nil
    }

    /// Whether the narrator is currently speaking.
    var isSpeaking: Bool {
        synth.isSpeaking
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        continuation?.resume()
        continuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Readable View Modifier

/// Makes any view tappable — single tap reads the label aloud via the shared Narrator.
struct ReadableModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                Narrator.shared.speak(label)
            }
    }
}

extension View {
    /// Single tap on this view reads the given text aloud.
    func readable(_ label: String) -> some View {
        self.modifier(ReadableModifier(label: label))
    }
}
