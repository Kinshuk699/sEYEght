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

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private let wakePhrase = "hey seyeght"

    func startListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("[SpeechManager] ❌ Speech recognizer not available")
            return
        }

        stopListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            try audioEngine.start()
            isListening = true
            print("[SpeechManager] ✅ Listening for wake phrase: '\(wakePhrase)'")
        } catch {
            print("[SpeechManager] ❌ Audio engine failed to start: \(error)")
            return
        }

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

                    self.onWakeWordDetected?()
                    self.restartListening()
                }
            }

            if let error = error {
                print("[SpeechManager] Recognition error: \(error.localizedDescription)")
                self.restartListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        print("[SpeechManager] Stopped listening")
    }

    private func restartListening() {
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startListening()
        }
    }
}
