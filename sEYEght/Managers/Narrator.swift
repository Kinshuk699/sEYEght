//
//  Narrator.swift
//  sEYEght
//
//  Created by Kinshuk on 4/4/26.
//

import AVFoundation
import SwiftUI

/// Single shared speech output for the entire app.
/// OpenAI TTS is the primary voice for ALL conversational speech.
/// Apple TTS is used ONLY for ultra-low-latency safety alerts (distance warnings).
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Narrator()

    private let synth = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    /// True while OpenAI TTS audio is playing
    private var isPlayingOpenAI = false

    /// Generation counter: incremented on every stopAll() to invalidate in-flight URL requests.
    /// Prevents stale OpenAI responses from playing after speech was cancelled.
    private var speechGeneration: Int = 0

    /// Tracks the current Apple TTS utterance to ignore stale delegate callbacks.
    private var currentUtterance: AVSpeechUtterance?

    /// Best available Apple voice — used for safety alerts only
    private var selectedVoice: AVSpeechSynthesisVoice?

    var hasHighQualityVoice: Bool { true }

    private override init() {
        selectedVoice = Self.pickBestVoice()
        super.init()
        synth.delegate = self
        if let voice = selectedVoice {
            print("[Narrator] Apple fallback voice: \(voice.name) quality=\(voice.quality.rawValue)")
        }
        print("[Narrator] OpenAI TTS enabled as primary voice")
    }

    func refreshVoice() {
        selectedVoice = Self.pickBestVoice()
        if let voice = selectedVoice {
            print("[Narrator] 🔄 Voice refreshed: \(voice.name) quality=\(voice.quality.rawValue)")
        }
    }

    private static func pickBestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let enVoices = voices.filter { $0.language.hasPrefix("en") }
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

    // MARK: - Stop Everything

    /// Stop all speech (both engines), cancel pending requests, resume waiting callers.
    func stop() { stopAll() }

    private func stopAll() {
        speechGeneration += 1  // Invalidate any in-flight OpenAI URL requests

        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingOpenAI = false

        synth.stopSpeaking(at: .immediate)
        currentUtterance = nil  // So stale didCancel callbacks are ignored

        continuation?.resume()
        continuation = nil
    }

    /// Whether the narrator is currently speaking (either engine).
    var isSpeaking: Bool {
        synth.isSpeaking || isPlayingOpenAI
    }

    // MARK: - Primary: OpenAI TTS

    /// Speak using OpenAI TTS (fire-and-forget). Falls back to Apple TTS if network fails.
    func speakWithOpenAI(_ text: String) {
        stopAll()

        let apiKey = SeyeghtSecrets.openAIKey
        guard !apiKey.isEmpty else {
            startAppleTTS(text)
            return
        }

        let generation = speechGeneration  // Capture for stale-check

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "tts-1",
            "input": text,
            "voice": "nova",
            "response_format": "mp3",
            "speed": 1.0
        ] as [String: Any])

        isPlayingOpenAI = true
        print("[Narrator] OpenAI TTS request: \"\(text.prefix(80))\"")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // CRITICAL: Discard if stopAll() was called since this request started
                guard self.speechGeneration == generation else {
                    print("[Narrator] Discarding stale OpenAI TTS response")
                    return
                }

                if let error = error {
                    print("[Narrator] OpenAI TTS error: \(error.localizedDescription), falling back to Apple")
                    self.isPlayingOpenAI = false
                    self.startAppleTTS(text)  // Fallback without stopAll
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data, data.count > 100 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    print("[Narrator] OpenAI TTS failed (HTTP \(code)), falling back to Apple")
                    self.isPlayingOpenAI = false
                    self.startAppleTTS(text)  // Fallback without stopAll
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
                    self.startAppleTTS(text)  // Fallback without stopAll
                }
            }
        }.resume()
    }

    /// Speak with OpenAI TTS and wait until playback finishes.
    func speakWithOpenAIAndWait(_ text: String) async {
        speakWithOpenAI(text)
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    // MARK: - Apple TTS (safety alerts only)

    /// Internal: start Apple TTS WITHOUT calling stopAll.
    /// Used as fallback from OpenAI so we don't prematurely resume the awaiting continuation.
    private func startAppleTTS(_ text: String, rate: Float = 0.45, volume: Float = 0.9) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume
        if let voice = selectedVoice { utterance.voice = voice }
        currentUtterance = utterance
        synth.speak(utterance)
    }

    /// Speak using Apple TTS (fire-and-forget). For distance warnings and safety alerts ONLY.
    /// If interruptible is false, won't interrupt currently playing speech.
    func speak(_ text: String, rate: Float = 0.45, volume: Float = 0.9, interruptible: Bool = true) {
        if !interruptible && (isPlayingOpenAI || synth.isSpeaking) {
            print("[Narrator] Skipping non-priority speech while already speaking: \"\(text.prefix(40))\"")
            return
        }
        stopAll()
        startAppleTTS(text, rate: rate, volume: volume)
    }

    /// Speak with Apple TTS and wait. Low-latency awaitable path.
    func speakAndWait(_ text: String, rate: Float = 0.45, volume: Float = 0.9) async {
        speak(text, rate: rate, volume: volume)
        await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Ignore stale callbacks from previously cancelled utterances
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        continuation?.resume()
        continuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Ignore stale callbacks from previously cancelled utterances
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - AVAudioPlayerDelegate (OpenAI TTS playback)

extension Narrator: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.audioPlayer === player else { return }  // Ignore stale
            self.isPlayingOpenAI = false
            self.audioPlayer = nil
            self.continuation?.resume()
            self.continuation = nil
            print("[Narrator] OpenAI TTS playback finished")
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.audioPlayer === player else { return }  // Ignore stale
            self.isPlayingOpenAI = false
            self.audioPlayer = nil
            self.continuation?.resume()
            self.continuation = nil
            print("[Narrator] OpenAI TTS decode error: \(error?.localizedDescription ?? "unknown")")
        }
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
