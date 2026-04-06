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
/// This prevents voice overlap between screens and components.
final class Narrator {
    static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()

    private init() {}

    /// Speak text, stopping any current speech first.
    func speak(_ text: String, rate: Float = 0.45, volume: Float = 0.9) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume
        synth.speak(utterance)
    }

    /// Stop any current speech immediately.
    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    /// Whether the narrator is currently speaking.
    var isSpeaking: Bool {
        synth.isSpeaking
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
