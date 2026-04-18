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

    /// Fired when the wake phrase is detected
    var onWakeWordDetected: (() -> Void)?

    /// Fired when "where am I" is detected (works standalone, no wake phrase needed)
    var onWhereAmIDetected: (() -> Void)?

    /// Fired when "navigate to [destination]" is detected — passes extracted destination
    var onNavigateDetected: ((String) -> Void)?

    /// Fired when user picks a search result ("first", "second", "third")
    var onSelectionDetected: ((Int) -> Void)?

    /// Fired when "stop navigation" / "cancel" is detected during active nav
    var onStopNavigationDetected: (() -> Void)?

    /// Fired when "help" is detected
    var onHelpDetected: (() -> Void)?

    /// When true, listen for selection commands instead of normal commands
    var isWaitingForSelection = false

    /// When true, "stop" / "cancel" triggers stop navigation
    var isNavigationActive = false

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

    // Navigation trigger phrases — destination extracted from text after these
    private let navigationTriggers = [
        "navigate to", "take me to", "go to", "directions to",
        "navigating to", "navigate two", "navigate too",
        "take me two", "take me too", "go two", "go too"
    ]

    // Selection phrases — user picking from search results
    private let selectionPhrases: [(phrases: [String], index: Int)] = [
        (["first", "the first", "first one", "the first one", "number one", "one", "1"], 0),
        (["second", "the second", "second one", "the second one", "number two", "two", "2"], 1),
        (["third", "the third", "third one", "the third one", "number three", "three", "3"], 2)
    ]

    // Stop navigation phrases
    private let stopPhrases = [
        "stop navigation", "cancel navigation", "stop navigating",
        "cancel route", "stop route", "stop directions", "cancel directions"
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
        guard !isListening else { return }

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

                // --- Selection mode: user is picking from search results ---
                if self.isWaitingForSelection {
                    for entry in self.selectionPhrases {
                        if entry.phrases.contains(where: { text.contains($0) }) {
                            print("[SpeechManager] 🗺️ Selection detected: index \(entry.index) from '\(text)'")
                            #if canImport(UIKit)
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            #endif
                            self.onSelectionDetected?(entry.index)
                            self.restartRecognitionOnly()
                            return
                        }
                    }
                    // Don't process other commands while waiting for selection
                    return
                }

                // --- Help command ---
                if self.helpPhrases.contains(where: { text.contains($0) }) {
                    print("[SpeechManager] ❓ Help command detected")
                    self.onHelpDetected?()
                    self.restartRecognitionOnly()
                    return
                }

                // --- Stop navigation ---
                if self.isNavigationActive {
                    let stopDetected = self.stopPhrases.contains { text.contains($0) }
                    // Also allow just "stop" or "cancel" during active navigation
                    let simpleStop = text.hasSuffix("stop") || text.hasSuffix("cancel")
                    if stopDetected || simpleStop {
                        print("[SpeechManager] 🛑 Stop navigation detected")
                        #if canImport(UIKit)
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.warning)
                        #endif
                        self.onStopNavigationDetected?()
                        self.restartRecognitionOnly()
                        return
                    }
                }

                // --- Navigation command: "navigate to [destination]" ---
                for trigger in self.navigationTriggers {
                    if let range = text.range(of: trigger) {
                        let destination = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if destination.count >= 2 {
                            print("[SpeechManager] 🗺️ Navigate command: '\(destination)'")
                            #if canImport(UIKit)
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            #endif
                            self.onNavigateDetected?(destination)
                            self.restartRecognitionOnly()
                            return
                        }
                    }
                }

                // "Where am I" works standalone — no wake phrase needed
                if text.contains("where am i") {
                    print("[SpeechManager] 📍 'Where am I' command detected")
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
                    print("[SpeechManager] 🎤 Command detected! Text: '\(text)' (wake=\(wakeDetected), describe=\(describeDetected))")

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
