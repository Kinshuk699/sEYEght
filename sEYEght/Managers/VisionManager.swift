//
//  VisionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import ARKit
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// F-005: On-Device Vision Pipeline.
/// Captures ARFrame → runs Apple Vision framework requests → speaks result.
/// Works completely offline — no internet, no API key, no subscription needed.
@Observable
final class VisionManager {
    var isProcessing = false
    var lastDescription = ""

    /// Callback so Dashboard can speak through its single synthesizer
    var onSpeechRequest: ((String) -> Void)?

    /// Speech rate set from user settings
    var speechRate: Float = 0.5

    /// Capture current AR frame and analyze on-device with Apple Vision framework.
    func captureAndAnalyze(from session: ARSession?) {
        guard !isProcessing else {
            print("[VisionManager] Already processing, skipping")
            return
        }

        // Try to get a frame — retry briefly if AR just started
        var frame: ARFrame? = session?.currentFrame
        if frame == nil {
            print("[VisionManager] No frame yet, will retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, !self.isProcessing else { return }
                if let f = session?.currentFrame {
                    self.isProcessing = true
                    self.analyzeFrame(f)
                } else {
                    print("[VisionManager] \u{274c} No current AR frame available after retry")
                    self.speakText("Camera not ready yet. Try again in a moment.")
                }
            }
            return
        }

        isProcessing = true
        print("[VisionManager] Capturing frame for on-device analysis")
        analyzeFrame(frame!)
    }

    private func analyzeFrame(_ frame: ARFrame) {
        let pixelBuffer = frame.capturedImage

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

            // 1. Scene classification
            let classifyRequest = VNClassifyImageRequest()

            // 2. Text recognition (signs, labels)
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast

            // 3. Human detection
            let humanRequest = VNDetectHumanRectanglesRequest()

            do {
                try handler.perform([classifyRequest, textRequest, humanRequest])
            } catch {
                print("[VisionManager] \u{274c} Vision analysis failed: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.speakText("Couldn't analyze the scene. Try again.")
                }
                return
            }

            // Build description from results
            var parts: [String] = []

            // Scene classifications (top results above 20% confidence)
            if let classifications = classifyRequest.results {
                let top = classifications
                    .filter { $0.confidence > 0.2 }
                    .prefix(4)
                    .map { self.humanReadableLabel($0.identifier) }

                if !top.isEmpty {
                    parts.append(top.joined(separator: ", "))
                }
            }

            // People count
            if let humans = humanRequest.results, !humans.isEmpty {
                let count = humans.count
                if count == 1 {
                    parts.append("1 person")
                } else {
                    parts.append("\(count) people")
                }
            }

            // Text detected
            if let textResults = textRequest.results {
                let texts = textResults
                    .compactMap { $0.topCandidates(1).first?.string }
                    .prefix(3)

                if !texts.isEmpty {
                    let textStr = texts.joined(separator: ", ")
                    parts.append("text reads: \(textStr)")
                }
            }

            let description: String
            if parts.isEmpty {
                description = "I can't identify anything specific in front of you right now."
            } else {
                description = parts.joined(separator: ". ") + "."
            }

            print("[VisionManager] \u{2705} On-device scene: \(description)")

            DispatchQueue.main.async {
                self.lastDescription = description
                self.isProcessing = false
                self.speakText(description)
            }
        }
    }

    /// Convert Vision taxonomy identifiers to natural spoken labels.
    /// e.g. "office_building" → "office building", "dining_table" → "dining table"
    private func humanReadableLabel(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    private func speakText(_ text: String) {
        print("[VisionManager] Speaking: \(text)")
        if let onSpeechRequest = onSpeechRequest {
            onSpeechRequest(text)
        }
    }
}
