//
//  VisionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import ARKit
import Vision
import CoreML
#if canImport(UIKit)
import UIKit
#endif

/// F-005: On-Device Magic-Tap Describer.
///
/// Tells the user three concrete things, in plain language, in this order:
///
///   1. **Text** — any signs, labels, prices, room numbers in front of them
///      (uses `.accurate` recognition because signs are why blind users tap).
///   2. **Objects** — a short, deduplicated list of common things in view
///      ("laptop, water bottle, two people") via Apple's on-device object
///      recognizer. People come from the face detector for accuracy.
///   3. **Distance** — the closest LiDAR distance, spoken as meters.
///
/// 100% on-device, no internet. Same building blocks Apple Magnifier uses.
@Observable
final class VisionManager {
    var isProcessing = false
    var lastDescription = ""

    /// Callback so Dashboard can speak through its single synthesizer
    var onSpeechRequest: ((String) -> Void)?

    /// Speech rate set from user settings (kept for API compatibility)
    var speechRate: Float = 0.5

    /// YOLOv8n CoreML model, loaded once at init.
    /// Compiled by Xcode at build time from `yolov8n.mlpackage` -> `yolov8n.mlmodelc`.
    /// Not @Observable-tracked because it never changes after load.
    @ObservationIgnored
    private var yoloModel: VNCoreMLModel?

    init() {
        self.yoloModel = Self.loadYOLOModel()
    }

    private static func loadYOLOModel() -> VNCoreMLModel? {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all   // CPU + GPU + Neural Engine
            guard let modelURL = Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc") else {
                print("[VisionManager] ❌ yolov8n.mlmodelc not found in bundle")
                return nil
            }
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            print("[VisionManager] ✅ YOLOv8n loaded")
            return try VNCoreMLModel(for: model)
        } catch {
            print("[VisionManager] ❌ YOLO load failed: \(error)")
            return nil
        }
    }

    /// Capture current AR frame and describe it on-device.
    /// `closestDistance` is the LiDAR distance to the nearest obstacle in
    /// meters (or `nil` if not available — e.g., simulator).
    func captureAndAnalyze(from session: ARSession?, closestDistance: Float? = nil) {
        guard !isProcessing else {
            print("[VisionManager] Already processing, skipping")
            return
        }

        // Try to get a frame — retry briefly if AR just started
        if let frame = session?.currentFrame {
            isProcessing = true
            print("[VisionManager] Capturing frame for on-device describe")
            analyzeFrame(frame, closestDistance: closestDistance)
            return
        }

        print("[VisionManager] No frame yet, will retry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.isProcessing else { return }
            if let f = session?.currentFrame {
                self.isProcessing = true
                self.analyzeFrame(f, closestDistance: closestDistance)
            } else {
                print("[VisionManager] ❌ No current AR frame available after retry")
                self.speakText("Camera not ready yet. Try again in a moment.")
            }
        }
    }

    private func analyzeFrame(_ frame: ARFrame, closestDistance: Float?) {
        let pixelBuffer = frame.capturedImage

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

            // Text recognition — use .accurate. Signs are the #1 reason a
            // blind user taps Describe. Speed cost (~150 ms) is fine.
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true

            // Face count via face rectangles (lighter than landmarks).
            let faceRequest = VNDetectFaceRectanglesRequest()

            // YOLOv8n object detector — 80 COCO classes (laptop, bottle,
            // chair, car, dog, etc.). Real concrete labels.
            var requests: [VNRequest] = [textRequest, faceRequest]
            let yoloRequest: VNCoreMLRequest? = self.yoloModel.map { model in
                let req = VNCoreMLRequest(model: model)
                req.imageCropAndScaleOption = .scaleFill
                return req
            }
            if let yoloRequest = yoloRequest { requests.append(yoloRequest) }

            do {
                try handler.perform(requests)
            } catch {
                print("[VisionManager] ❌ Vision analysis failed: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.speakText("Couldn't analyze the scene. Try again.")
                }
                return
            }

            let description = self.buildDescription(
                textResults: textRequest.results,
                faceResults: faceRequest.results,
                yoloResults: yoloRequest?.results,
                closestDistance: closestDistance
            )

            print("[VisionManager] ✅ Describe: \(description)")

            DispatchQueue.main.async {
                self.lastDescription = description
                self.isProcessing = false
                self.speakText(description)
            }
        }
    }

    /// Compose the final spoken sentence. Order matters — text first because
    /// it's the most actionable, then objects, then people, then distance.
    private func buildDescription(
        textResults: [VNRecognizedTextObservation]?,
        faceResults: [VNFaceObservation]?,
        yoloResults: [VNObservation]?,
        closestDistance: Float?
    ) -> String {
        // Too-close guard: if the closest LiDAR pixel is under ~0.4 m, the
        // camera is almost certainly pressed against something (the user's
        // body, a hand, a coat). Vision returns an empty result and the
        // user just hears "less than half a meter ahead", which is useless.
        // Tell them what to actually do.
        if let d = closestDistance, d > 0, d.isFinite, d < 0.4 {
            return "Phone is too close to see. Hold it away from your body, then tap again."
        }

        var parts: [String] = []

        // 1. Text — keep up to 3 highest-confidence lines, drop noise (<0.4 conf,
        //    or single-character results which are usually misreads).
        if let textResults = textResults {
            let lines = textResults
                .compactMap { obs -> String? in
                    guard let cand = obs.topCandidates(1).first,
                          cand.confidence >= 0.4,
                          cand.string.trimmingCharacters(in: .whitespaces).count > 1
                    else { return nil }
                    return cand.string.trimmingCharacters(in: .whitespaces)
                }
                .prefix(3)

            if !lines.isEmpty {
                let joined = lines.joined(separator: ", ")
                parts.append("Sign reads: \(joined)")
            }
        }

        // 2. Objects — YOLOv8n returns VNRecognizedObjectObservation, each
        //    with a list of label/confidence pairs. We take the top label
        //    per detection, drop "person" (face detector handles it), count
        //    duplicates ("two bottles"), and cap at 4 distinct items.
        if let yolo = yoloResults as? [VNRecognizedObjectObservation] {
            var counts: [String: Int] = [:]
            var order: [String] = []  // preserve detection order for stable output
            for obs in yolo {
                guard obs.confidence >= 0.4,
                      let top = obs.labels.first,
                      top.confidence >= 0.4
                else { continue }
                let label = top.identifier.lowercased()
                if label == "person" { continue }   // faces handle people
                if counts[label] == nil { order.append(label) }
                counts[label, default: 0] += 1
            }

            let phrases = order.prefix(4).map { label -> String in
                let n = counts[label] ?? 1
                return n > 1 ? "\(numberWord(n)) \(pluralize(label))" : "a \(label)"
            }

            if !phrases.isEmpty {
                parts.append("In front of you: \(phrases.joined(separator: ", "))")
            }
        }

        // 3. Faces
        if let faces = faceResults, !faces.isEmpty {
            let count = faces.count
            switch count {
            case 1: parts.append("One person in front of you")
            case 2: parts.append("Two people in front of you")
            default: parts.append("\(count) people in front of you")
            }
        }

        // 4. Distance — always include if we have it. Anchors the user.
        if let d = closestDistance, d > 0, d.isFinite, d < 8.0 {
            parts.append(distancePhrase(d))
        }

        if parts.isEmpty {
            return "Nothing I can read or recognize in front of you."
        }
        return parts.joined(separator: ". ") + "."
    }

    /// Speak distance the way a human would: "less than half a meter",
    /// "about one meter", "about two and a half meters".
    private func distancePhrase(_ meters: Float) -> String {
        if meters < 0.5 {
            return "Less than half a meter ahead"
        }
        // Round to nearest 0.5 m for natural phrasing
        let rounded = (meters * 2.0).rounded() / 2.0
        let whole = Int(rounded)
        let hasHalf = rounded - Float(whole) >= 0.25

        if whole == 0 {
            return "Half a meter ahead"
        }
        let unit = (whole == 1 && !hasHalf) ? "meter" : "meters"
        if hasHalf {
            return "About \(whole) and a half \(unit) ahead"
        }
        return "About \(whole) \(unit) ahead"
    }

    private func speakText(_ text: String) {
        print("[VisionManager] Speaking: \(text)")
        onSpeechRequest?(text)
    }

    /// Spell out small counts the way a human would.
    private func numberWord(_ n: Int) -> String {
        switch n {
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        default: return "\(n)"
        }
    }

    /// Naive English pluralization, good enough for COCO labels.
    private func pluralize(_ word: String) -> String {
        if word.hasSuffix("s") || word.hasSuffix("x") { return word + "es" }
        if word.hasSuffix("y") { return String(word.dropLast()) + "ies" }
        return word + "s"
    }
}
