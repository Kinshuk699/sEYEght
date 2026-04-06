//
//  Narrator.swift
//  sEYEght
//
//  Created by Kinshuk on 4/4/26.
//

import AVFoundation
import SwiftUI

/// Single shared speech output for the entire app.
/// Uses OpenAI TTS for natural voice (scene descriptions), falls back to Apple TTS for quick alerts.
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    /// True while OpenAI TTS audio is playing
    private var isPlayingOpenAI = false

    /// Best available Apple voice — used as fallback for short alerts
    private var selectedVoice: AVSpeechSynthesisVoice?

    /// Whether we're using a high-quality voice (enhanced or premium)
    var hasHighQualityVoice: Bool {
        // We have OpenAI TTS now, so always true
        return true
    }

    private override init() {
        selectedVoice = Self.pickBestVoice()
        super.init()
        synth.delegate = self
        if let voice = selectedVoice {
            print("[Narrator] Apple fallback voice: \(voice.name) quality=\(voice.quality.rawValue)")
        }
        print("[Narrator] OpenAI TTS enabled as primary voice")
    }

    /// Re-select the best available voice (call after user downloads an enhanced voice)
    func refreshVoice() {
        selectedVoice = Self.pickBestVoice()
        if let voice = selectedVoice {
            print("[Narrator] 🔄 Voice refreshed: \(voice.name) quality=\(voice.quality.rawValue)")
        }
    }

    private static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let enVoices = voices.filter { $0.language.hasPrefix("en") }

        // Premium > Enhanced > Compact
        if let v = enVoices.first(where: { $0.quality == .premium }) { return v }

        let preferred = ["Ava", "Samantha", "Allison", "Zoe", "Susan", "Victoria"]
        for name in preferred {
            if let v = enVoices.first(where: { $0.quality == .enhanced && $0.name.contains(name) }) { return v }
        }
        if let v = enVoices.first(where: { $0.quality == .enhanced }) { return v }

        let compactPreferred = ["Samantha", "Ava", "Allison", "Zoe", "Nicky", "Karen"]
        for name in compactPreferred {
            if let v = enVoices.first(where: { $0.name.contains(name) }) { return v }
        }
        return enVoices.first
    }

    // MARK: - Primary: OpenAI TTS

    /// Speak using OpenAI TTS (natural voice). Falls back to Apple TTS if network fails.
    func speakWithOpenAI(_ text: String) {
        // Stop any current speech
        stopAll()

        let apiKey = SeyeghtSecrets.openAIKey
        guard !apiKey.isEmpty else {
            speak(text) // Fallback
            return
        }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": "nova",
            "response_format": "mp3",
            "speed": 1.0
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isPlayingOpenAI = true
        print("[Narrator] OpenAI TTS request: \"\(text.prefix(80))\"")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    print("[Narrator] OpenAI TTS error: \(error.localizedDescription), falling back to Apple")
                    self.isPlayingOpenAI = false
                    self.speak(text)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let data = data, data.count > 100 else {
                    print("[Narrator] OpenAI TTS failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)), falling back to Apple")
                    self.isPlayingOpenAI = false
                    self.speak(text)
                    return
                }

                do {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.volume = 0.9
                    self.audioPlayer = player
                    player.play()
                    print("[Narrator] ✅ OpenAI TTS playing (\(data.count) bytes)")
                } catch {
                    print("[Narrator] AVAudioPlayer error: \(error), falling back to Apple")
                    self.isPlayingOpenAI = false
                    self.speak(text)
                }
            }
        }.resume()
    }

    /// Speak with OpenAI TTS and wait until done.
    func speakWithOpenAIAndWait(_ text: String) async {
        speakWithOpenAI(text)
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    // MARK: - Fallback: Apple TTS

    /// Speak using Apple's built-in TTS. Used for quick alerts and fallback.
    /// If `interruptible` is false, won't interrupt currently playing speech.
    func speak(_ text: String, rate: Float = 0.45, volume: Float = 0.9, interruptible: Bool = true) {
        // Don't interrupt OpenAI TTS or ongoing Apple speech with non-priority messages
        if !interruptible && (isPlayingOpenAI || synth.isSpeaking) {
            print("[Narrator] Skipping non-priority speech while already speaking: \"\(text.prefix(40))\"")
            return
        }

        stopAll()

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

    /// Stop all speech (both OpenAI and Apple).
    func stop() {
        stopAll()
    }

    private func stopAll() {
        // Stop OpenAI audio
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingOpenAI = false

        // Stop Apple TTS
        synth.stopSpeaking(at: .immediate)

        // Resume any waiting continuations
        continuation?.resume()
        continuation = nil
    }

    /// Whether the narrator is currently speaking (either engine).
    var isSpeaking: Bool {
        synth.isSpeaking || isPlayingOpenAI
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

// MARK: - AVAudioPlayerDelegate (OpenAI TTS playback)

extension Narrator: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlayingOpenAI = false
            self?.audioPlayer = nil
            self?.continuation?.resume()
            self?.continuation = nil
            print("[Narrator] OpenAI TTS playback finished")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlayingOpenAI = false
            self?.audioPlayer = nil
            self?.continuation?.resume()
            self?.continuation = nil
            print("[Narrator] OpenAI TTS decode error: \(error?.localizedDescription ?? "unknown")")
        }
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
