//
//  SpeechManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import Speech
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// F-003: Continuous Voice Recognition Engine.
/// Listens for the fixed wake phrase "Hey Seyeght" while app is active.
@Observable
final class SpeechManager {
    var isListening = false
    var lastRecognizedText = ""

    /// Fired when the wake phrase is detected
    var onWakeWordDetected: (() -> Void)?

    /// Fired when "where am I" is detected after the wake phrase
    var onWhereAmIDetected: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer()  // Uses device locale for better accent support
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private let wakePhrase = "hey seyeght"
    private var isStopped = false  // true = user explicitly called stopListening()

    func startListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("[SpeechManager] ❌ Speech recognizer not available")
            return
        }

        isStopped = false
        stopRecognitionTask()

        // Only configure audio engine if it's not already running
        if !audioEngine.isRunning {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
            } catch {
                print("[SpeechManager] ❌ Failed to configure audio session: \(error)")
                return
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                print("[SpeechManager] ❌ Audio input format invalid (sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount))")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            do {
                try audioEngine.start()
            } catch {
                print("[SpeechManager] ❌ Audio engine failed to start: \(error)")
                return
            }
        }

        startRecognitionTask(with: speechRecognizer)
    }

    private func startRecognitionTask(with speechRecognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        if #available(iOS 16, *) {
            request.addsPunctuation = false
        }
        recognitionRequest = request

        isListening = true
        print("[SpeechManager] ✅ Listening for wake phrase: '\(wakePhrase)'")

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                self.lastRecognizedText = text

                if text.contains(self.wakePhrase) {
                    print("[SpeechManager] 🎤 Wake word detected! Text: '\(text)'")

                    #if canImport(UIKit)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif

                    // Check for "where am I" command
                    if text.contains("where am i") || text.contains("where am I") {
                        print("[SpeechManager] 📍 'Where am I' command detected")
                        self.onWhereAmIDetected?()
                    } else {
                        self.onWakeWordDetected?()
                    }
                    // Restart recognition task (not the whole engine)
                    self.restartRecognitionOnly()
                }
            }

            if let error = error {
                // Only log if it's NOT the common "no speech" timeout
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    // Code 1110 = "No speech detected" — normal, just restart quietly
                } else {
                    print("[SpeechManager] Recognition error: \(error.localizedDescription)")
                }
                self.restartRecognitionOnly()
            }
        }
    }

    func stopListening() {
        isStopped = true
        stopRecognitionTask()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        print("[SpeechManager] Stopped listening")
    }

    private func stopRecognitionTask() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    /// Restart only the recognition task, keep audio engine running
    private func restartRecognitionOnly() {
        stopRecognitionTask()
        isListening = false

        guard !isStopped else { return }

        // Longer delay to reduce churn — 2 seconds between recognition cycles
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.isStopped else { return }
            guard let speechRecognizer = self.speechRecognizer, speechRecognizer.isAvailable else { return }
            self.startRecognitionTask(with: speechRecognizer)
        }
    }
}
