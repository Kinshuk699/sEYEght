//
//  Narrator.swift
//  sEYEght
//
//  Created by Kinshuk on 4/4/26.
//

import AVFoundation
import SwiftUI

/// Single shared speech output for the entire app.
/// Uses sherpa-onnx Kokoro neural TTS — free, offline, natural-sounding.
final class Narrator: NSObject, @unchecked Sendable {
    static let shared = Narrator()

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private var generation: Int = 0
    private let queue = DispatchQueue(label: "narrator.tts", qos: .userInitiated)

    /// Speaker ID: af_bella (natural female voice)
    private let speakerID: Int = 1

    /// Always true — Kokoro is high quality neural TTS
    var hasHighQualityVoice: Bool { tts != nil }

    var voiceDescription: String { "Kokoro (Neural)" }

    var isSpeaking: Bool { player?.isPlaying ?? false }

    private override init() {
        super.init()
        initTTS()
    }

    private func initTTS() {
        guard let modelPath = Bundle.main.path(forResource: "model.int8", ofType: "onnx", inDirectory: "kokoro-int8-en-v0_19"),
              let voicesPath = Bundle.main.path(forResource: "voices", ofType: "bin", inDirectory: "kokoro-int8-en-v0_19"),
              let tokensPath = Bundle.main.path(forResource: "tokens", ofType: "txt", inDirectory: "kokoro-int8-en-v0_19"),
              let dataDirURL = Bundle.main.url(forResource: "espeak-ng-data", withExtension: nil, subdirectory: "kokoro-int8-en-v0_19")
        else {
            print("[Narrator] ❌ Kokoro model files not found in bundle")
            return
        }

        let dataDir = dataDirURL.path

        let kokoro = sherpaOnnxOfflineTtsKokoroModelConfig(
            model: modelPath,
            voices: voicesPath,
            tokens: tokensPath,
            dataDir: dataDir
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(
            kokoro: kokoro,
            numThreads: 2
        )
        var config = sherpaOnnxOfflineTtsConfig(model: modelConfig)
        tts = SherpaOnnxOfflineTtsWrapper(config: &config)
        print("[Narrator] ✅ Kokoro TTS initialized (speaker: af_bella)")
    }

    func refreshVoice() {
        // No-op for Kokoro — model doesn't change dynamically
    }

    // MARK: - Speech Output

    func speak(_ text: String, rate: Float = 0.45, volume: Float = 0.9, interruptible: Bool = true) {
        if !interruptible && isSpeaking {
            print("[Narrator] Skipping non-priority: \"\(text.prefix(40))\"")
            return
        }
        stopAll()
        let gen = generation
        let speed = max(0.5, min(2.0, rate / 0.45))
        queue.async { [weak self] in
            self?.generateAndPlay(text: text, speed: speed, volume: volume, generation: gen)
        }
    }

    func speakAndWait(_ text: String, rate: Float = 0.45, volume: Float = 0.9) async {
        stopAll()
        let gen = generation
        let speed = max(0.5, min(2.0, rate / 0.45))
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            queue.async { [weak self] in
                self?.generateAndPlay(text: text, speed: speed, volume: volume, generation: gen)
            }
        }
    }

    func speakWithOpenAI(_ text: String) {
        speak(text)
    }

    func speakWithOpenAIAndWait(_ text: String) async {
        await speakAndWait(text)
    }

    func stop() { stopAll() }

    // MARK: - Internal

    private func generateAndPlay(text: String, speed: Float, volume: Float, generation: Int) {
        guard let tts = tts else {
            print("[Narrator] TTS not initialized")
            DispatchQueue.main.async { [weak self] in
                self?.continuation?.resume()
                self?.continuation = nil
            }
            return
        }

        guard generation == self.generation else {
            return
        }

        let audio = tts.generate(text: text, sid: speakerID, speed: speed)
        let samples = audio.samples
        let sampleRate = audio.sampleRate

        guard !samples.isEmpty, generation == self.generation else {
            DispatchQueue.main.async { [weak self] in
                self?.continuation?.resume()
                self?.continuation = nil
            }
            return
        }

        // Convert Float samples to 16-bit PCM WAV in memory
        let wavData = Self.createWAV(samples: samples, sampleRate: Int(sampleRate))

        DispatchQueue.main.async { [weak self] in
            guard let self = self, generation == self.generation else {
                self?.continuation?.resume()
                self?.continuation = nil
                return
            }
            do {
                self.player?.stop()
                self.player = try AVAudioPlayer(data: wavData)
                self.player?.volume = volume
                self.player?.delegate = self
                self.player?.play()
            } catch {
                print("[Narrator] ❌ AVAudioPlayer error: \(error)")
                self.continuation?.resume()
                self.continuation = nil
            }
        }
    }

    private func stopAll() {
        generation += 1
        player?.stop()
        player = nil
        continuation?.resume()
        continuation = nil
    }

    /// Create a WAV file in memory from Float samples
    private static func createWAV(samples: [Float], sampleRate: Int) -> Data {
        let numSamples = samples.count
        let bytesPerSample = 2
        let dataSize = numSamples * bytesPerSample
        let fileSize = 44 + dataSize

        var data = Data(capacity: fileSize)

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * bytesPerSample).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bytesPerSample).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

        // data chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767.0)
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        return data
    }
}

// MARK: - AVAudioPlayerDelegate

extension Narrator: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
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
