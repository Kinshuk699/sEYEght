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
    private let selectedVoice: AVSpeechSynthesisVoice?

    private override init() {
        // Find an enhanced voice for the device locale
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let enhanced = voices.first(where: {
            $0.language.hasPrefix(locale) && $0.quality == .enhanced
        })
        let premium = voices.first(where: {
            $0.language.hasPrefix(locale) && $0.quality == .premium
        })
        selectedVoice = premium ?? enhanced
        super.init()
        synth.delegate = self
        if let voice = selectedVoice {
            print("[Narrator] Using voice: \(voice.name) (\(voice.quality.rawValue))")
        } else {
            print("[Narrator] No enhanced voice found, using system default")
        }
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
