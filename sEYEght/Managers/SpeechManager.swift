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
/// Listens for the fixed wake phrase "Hey Sight" while app is active.
@Observable
final class SpeechManager {
    var isListening = false
    var lastRecognizedText = ""

    /// Fired when the wake phrase is detected (scene description)
    var onWakeWordDetected: (() -> Void)?

    /// Fired when "where am I" is detected (works standalone, no wake phrase needed)
    var onWhereAmIDetected: (() -> Void)?

    /// Fired when "help" is detected
    var onHelpDetected: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer()  // Uses device locale for better accent support
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Multiple phrasings that speech recognizer might produce for wake word
    private let wakePhrases = [
        "hey sight", "hey site", "hey sigh", "a sight", "hey say",
        "hey seyeght", "hey say it", "hey side", "hey light",
        "hey cite", "hey fight", "hey slide", "heysite", "heysight",
        "hey psy", "hey sai", "hey sci"
    ]

    // Help phrases
    private let helpPhrases = [
        "help", "what can i do", "what are my commands",
        "how do i use this", "what can you do"
    ]

    // Natural commands that also trigger scene description — fuzzy partial matching
    private let describeCommands = [
        "what is near me", "what's near me", "what is in front", "what's in front",
        "describe", "what do you see", "what can you see", "what is around me",
        "what's around me", "tell me what you see", "what is ahead", "what's ahead",
        "look around", "scan", "help me see", "what is there",
        "what am i seeing", "what am i looking at", "what's in front of me",
        "what is in front of me", "what do i see", "describe the scene",
        "describe what", "what's there", "what's out there", "what's happening",
        "what is happening", "tell me what's", "what is this", "what's this",
        "can you see", "see anything", "what is out there"
    ]

    private var isStopped = false  // true = user explicitly called stopListening()

    func startListening() {
        // Guard: don't restart if already listening
        guard !isListening else {
            print("[SpeechManager] Already listening, skipping startListening()")
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("[SpeechManager] ❌ Speech recognizer not available")
            return
        }

        isStopped = false
        stopRecognitionTask()

        // Only configure audio engine if it's not already running
        if !audioEngine.isRunning {
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

        let wasListening = isListening
        isListening = true
        if !wasListening {
            print("[SpeechManager] ✅ Listening for wake phrase: 'Hey Sight' and 'Where am I'")
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                self.lastRecognizedText = text

                // --- Help command ---
                if self.helpPhrases.contains(where: { text.contains($0) }) {
                    print("[SpeechManager] Help command detected")
                    self.onHelpDetected?()
                    self.restartRecognitionOnly()
                    return
                }

                // "Where am I" works standalone — no wake phrase needed
                if text.contains("where am i") {
                    print("[SpeechManager] 'Where am I' command detected")
                    self.onWhereAmIDetected?()
                    self.restartRecognitionOnly()
                    return
                }

                // Check for wake phrase OR natural describe commands
                let wakeDetected = self.wakePhrases.contains { text.contains($0) }
                let describeDetected = self.describeCommands.contains { text.contains($0) }
                let partialDescribe = text.contains("what am i") || text.contains("what do i") ||
                    text.contains("see right now") || text.contains("seeing right now") ||
                    text.contains("looking at") || text.contains("in front of")
                if wakeDetected || describeDetected || partialDescribe {
                    print("[SpeechManager] Command detected! Text: '\(text)' (wake=\(wakeDetected), describe=\(describeDetected))")

                    #if canImport(UIKit)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif

                    self.onWakeWordDetected?()
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

        // Short delay between recognition cycles — keep responsive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, !self.isStopped else { return }
            guard let speechRecognizer = self.speechRecognizer, speechRecognizer.isAvailable else { return }
            self.startRecognitionTask(with: speechRecognizer)
        }
    }
}
