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

    /// YOLOv8n-OIV7 CoreML model. Loaded on a background queue right after
    /// init() returns — NEVER on the main thread, or iOS watchdog will
    /// SIGKILL the app at launch (0x8badf00d) for blocking the main thread
    /// during scene setup. Until it's ready, describes fall back to text +
    /// faces + distance only (still useful).
    /// Not @Observable-tracked because it never changes after load.
    @ObservationIgnored
    private var yoloModel: VNCoreMLModel?

    init() {
        // Defer model load to background so app launches instantly.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let model = Self.loadYOLOModel()
            DispatchQueue.main.async {
                self?.yoloModel = model
            }
        }
    }

    private static func loadYOLOModel() -> VNCoreMLModel? {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all   // CPU + GPU + Neural Engine
            guard let modelURL = Bundle.main.url(forResource: "yolov8n-oiv7", withExtension: "mlmodelc") else {
                print("[VisionManager] ❌ yolov8n-oiv7.mlmodelc not found in bundle")
                return nil
            }
            let model = try MLModel(contentsOf: modelURL, configuration: config)
            print("[VisionManager] ✅ YOLOv8n-OIV7 loaded (600 classes)")
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

            // YOLOv8n-OIV7 object detector — 600 Open Images classes.
            // .centerCrop = take the center square of the camera frame and
            // feed that to YOLO. Critical for blind UX: the user is pointing
            // the phone at something, so we only care about what's in the
            // center of view, NOT the bed at the right edge of the frame.
            var requests: [VNRequest] = [textRequest, faceRequest]
            let yoloRequest: VNCoreMLRequest? = self.yoloModel.map { model in
                let req = VNCoreMLRequest(model: model)
                req.imageCropAndScaleOption = .centerCrop
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

        // 1. Text — keep up to 3 highest-confidence lines. Drop noise:
        //    low confidence, single chars, or single short words (likely
        //    OCR misreads of furniture labels / patterns, e.g. "BED" on a
        //    headboard which then duplicates with the YOLO label).
        if let textResults = textResults {
            let lines = textResults
                .compactMap { obs -> String? in
                    guard let cand = obs.topCandidates(1).first,
                          cand.confidence >= 0.5
                    else { return nil }
                    let s = cand.string.trimmingCharacters(in: .whitespaces)
                    // Require either multi-word OR contains a digit OR is
                    // longer than 4 chars. Real signs are rarely 1-3 chars.
                    let hasSpace = s.contains(" ")
                    let hasDigit = s.rangeOfCharacter(from: .decimalDigits) != nil
                    guard hasSpace || hasDigit || s.count > 4 else { return nil }
                    return s
                }
                .prefix(3)

            if !lines.isEmpty {
                let joined = lines.joined(separator: ", ")
                parts.append("Sign reads: \(joined)")
            }
        }

        // 2. Objects — YOLOv8n-OIV7 returns 600 Open Images classes.
        //    Sort by distance-from-center so what the user is pointing at
        //    is spoken first. Drop person sub-classes (face detector handles).
        if let yolo = yoloResults as? [VNRecognizedObjectObservation] {
            let personLikeLabels: Set<String> = [
                "person", "man", "woman", "boy", "girl",
                "human face", "human head", "human body", "human eye",
                "human nose", "human mouth", "human ear", "human hand",
                "human arm", "human leg", "human foot", "clothing"
            ]
            // Sort detections by Euclidean distance of bbox center from
            // (0.5, 0.5). Vision bbox is in normalized image coords (0–1).
            let sorted = yolo
                .filter { obs in
                    guard obs.confidence >= 0.35,
                          let top = obs.labels.first, top.confidence >= 0.35
                    else { return false }
                    return !personLikeLabels.contains(top.identifier.lowercased())
                }
                .sorted { a, b in
                    let ax = a.boundingBox.midX - 0.5, ay = a.boundingBox.midY - 0.5
                    let bx = b.boundingBox.midX - 0.5, by = b.boundingBox.midY - 0.5
                    return (ax * ax + ay * ay) < (bx * bx + by * by)
                }

            var counts: [String: Int] = [:]
            var order: [String] = []  // preserve center-first order
            for obs in sorted {
                guard let top = obs.labels.first else { continue }
                let label = top.identifier.lowercased()
                if counts[label] == nil { order.append(label) }
                counts[label, default: 0] += 1
            }

            let phrases = order.prefix(5).map { label -> String in
                let n = counts[label] ?? 1
                return n > 1 ? "\(numberWord(n)) \(pluralize(label))" : "\(article(for: label)) \(label)"
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

    /// Naive English pluralization, good enough for OIV7 labels.
    /// Pluralizes only the final word for multi-word labels ("light bulbs").
    private func pluralize(_ word: String) -> String {
        let parts = word.split(separator: " ")
        guard let last = parts.last else { return word }
        let pluralLast: String
        let s = String(last)
        if s.hasSuffix("s") || s.hasSuffix("x") { pluralLast = s + "es" }
        else if s.hasSuffix("y") { pluralLast = String(s.dropLast()) + "ies" }
        else { pluralLast = s + "s" }
        return (parts.dropLast().joined(separator: " ") + " " + pluralLast)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Pick "a" or "an" for natural speech ("a lamp", "an oven").
    private func article(for word: String) -> String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        if let first = word.first, vowels.contains(first) { return "an" }
        return "a"
    }
}
