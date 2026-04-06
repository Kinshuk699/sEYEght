//
//  VisionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import ARKit
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// F-005: LLM Vision Pipeline.
/// Captures ARFrame → compresses → sends to GPT-4o Vision → speaks result.
@Observable
final class VisionManager {
    var isProcessing = false
    var lastDescription = ""

    /// Callback so Dashboard can speak through its single synthesizer
    var onSpeechRequest: ((String) -> Void)?

    private var apiKey: String {
        // Read from Secrets.swift (generated from Config.xcconfig, excluded from git)
        return SeyeghtSecrets.openAIKey
    }

    /// Speech rate set from user settings
    var speechRate: Float = 0.5

    /// Capture current AR frame, compress, send to OpenAI, speak result.
    func captureAndAnalyze(from session: ARSession?) {
        guard !isProcessing else {
            print("[VisionManager] Already processing, skipping")
            return
        }
        guard let frame = session?.currentFrame else {
            print("[VisionManager] ❌ No current AR frame available")
            return
        }

        isProcessing = true
        print("[VisionManager] Capturing frame for analysis")

        let pixelBuffer = frame.capturedImage

        guard let jpegData = compressFrame(pixelBuffer) else {
            print("[VisionManager] ❌ Failed to compress frame")
            isProcessing = false
            return
        }

        print("[VisionManager] Compressed to \(jpegData.count) bytes, sending to API")
        sendToOpenAI(imageData: jpegData)
    }

    private func compressFrame(_ pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let uiImage = UIImage(cgImage: cgImage)

        // Scale to max 512px width
        let maxWidth: CGFloat = 512
        let scale = min(1.0, maxWidth / uiImage.size.width)
        let newSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage?.jpegData(compressionQuality: 0.3)
    }

    private func sendToOpenAI(imageData: Data) {
        let base64Image = imageData.base64EncodedString()

        guard !apiKey.isEmpty && apiKey != "sk-your-key-here" else {
            print("[VisionManager] ❌ No valid API key configured")
            isProcessing = false
            speakText("API key not configured. Please add your OpenAI key in settings.")
            return
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "You are navigating a blind person. Describe the immediate scene in front of them in less than 15 words. Focus only on critical obstacles, signage, or the structural layout."
                        ],
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                        ]
                    ]
                ]
            ],
            "max_tokens": 60
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isProcessing = false

                if let error = error {
                    print("[VisionManager] ❌ API error: \(error.localizedDescription)")
                    self?.speakText("Sorry, I couldn't analyze the scene right now.")
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    print("[VisionManager] ❌ Failed to parse API response")
                    self?.speakText("Sorry, I couldn't understand the response.")
                    return
                }

                let description = content.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.lastDescription = description
                print("[VisionManager] ✅ Scene description: \(description)")
                self?.speakText(description)
            }
        }.resume()
    }

    private func speakText(_ text: String) {
        AudioSessionManager.shared.beginSpeaking()
        print("[VisionManager] Speaking: \(text)")
        if let onSpeechRequest = onSpeechRequest {
            onSpeechRequest(text)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(text.count) * 0.06) {
            AudioSessionManager.shared.endSpeaking()
        }
    }
}
