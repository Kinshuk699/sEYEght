//
//  Narrator.swift
//  sEYEght
//
//  Created by Kinshuk on 4/4/26.
//

import AVFoundation
import SwiftUI

/// Single shared speech output for the entire app.
/// Uses Apple's AVSpeechSynthesizer with enhanced voice selection.
final class Narrator: NSObject, @unchecked Sendable {
    static let shared = Narrator()

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var selectedVoice: AVSpeechSynthesisVoice?

    /// True if we found an enhanced/premium voice
    var hasHighQualityVoice: Bool { selectedVoice?.quality == .enhanced || selectedVoice?.quality == .premium }

    var voiceDescription: String {
        guard let voice = selectedVoice else { return "Default" }
        let qualityStr = voice.quality == .enhanced ? "Enhanced" : (voice.quality == .premium ? "Premium" : "Standard")
        return "\(voice.name) (\(qualityStr))"
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    private override init() {
        super.init()
        synthesizer.delegate = self
        selectBestVoice()
        print("[Narrator] ✅ Initialized with voice: \(voiceDescription)")
    }

    /// Select the best available English voice (prefer enhanced/premium)
    private func selectBestVoice() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = voices.filter { $0.language.starts(with: "en") }

        // Priority: Premium > Enhanced > Default
        if let premium = englishVoices.first(where: { $0.quality == .premium }) {
            selectedVoice = premium
        } else if let enhanced = englishVoices.first(where: { $0.quality == .enhanced }) {
            selectedVoice = enhanced
        } else if let defaultVoice = AVSpeechSynthesisVoice(language: "en-US") {
            selectedVoice = defaultVoice
        }
    }

    /// Re-check for better voices (e.g., after user downloads one)
    func refreshVoice() {
        selectBestVoice()
        print("[Narrator] Voice refreshed: \(voiceDescription)")
    }

    // MARK: - Speech Output

    func speak(_ text: String, rate: Float = 0.5, volume: Float = 0.9, interruptible: Bool = true) {
        if !interruptible && isSpeaking {
            print("[Narrator] Skipping non-priority: \"\(text.prefix(40))\"")
            return
        }

        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = rate
        utterance.volume = volume
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.1

        print("[Narrator] Speaking: \"\(text.prefix(60))\"")
        synthesizer.speak(utterance)
    }

    func speakAndWait(_ text: String, rate: Float = 0.5, volume: Float = 0.9) async {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = rate
        utterance.volume = volume
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.1

        print("[Narrator] Speaking (await): \"\(text.prefix(60))\"")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension Narrator: AVSpeechSynthesizerDelegate {
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
    func readable(_ label: String) -> some View {
        self.modifier(ReadableModifier(label: label))
    }
}

// MARK: - Navigable View Modifier (Single-tap speaks, Double-tap activates)

/// Makes a view accessible for blind users.
/// - VoiceOver ON: standard Button (VoiceOver handles focus + double-tap activate)
/// - VoiceOver OFF: single tap speaks the label, double tap executes action
struct NavigableModifier: ViewModifier {
    let label: String
    let action: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        Group {
            if voiceOverEnabled {
                // VoiceOver users: standard activation via VoiceOver gestures
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    action()
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                // Sighted/non-VoiceOver users: blind-first tap pattern
                content
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        action()
                    }
                    .onTapGesture(count: 1) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        Narrator.shared.speak(label)
                    }
            }
        }
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to activate")
    }
}

extension View {
    /// Makes element navigable: single-tap speaks, double-tap activates
    func navigable(_ label: String, action: @escaping () -> Void) -> some View {
        self.modifier(NavigableModifier(label: label, action: action))
    }
}
