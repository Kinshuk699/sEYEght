//
//  LiDARManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import ARKit
import Combine

/// F-001: ARKit Depth Matrix Engine.
/// Extracts depth map from LiDAR, filters ground-level objects,
/// and reports the closest obstacle distance + horizontal position.
@Observable
final class LiDARManager: NSObject, ARSessionDelegate {
    var closestDistance: Float = Float.greatestFiniteMagnitude
    var closestNormalizedX: Float = 0.5 // 0=left, 1=right
    var isRunning = false

    private var arSession: ARSession?
    private var lastProcessTime: TimeInterval = 0
    private let minProcessInterval: TimeInterval = 1.0 / 12.0 // ~12fps
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "com.seyeght.lidar", qos: .userInteractive)

    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("[LiDARManager] ❌ Device does not support LiDAR sceneDepth")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth

        let session = ARSession()
        session.delegate = self
        session.run(config)
        arSession = session
        isRunning = true
        print("[LiDARManager] ✅ ARKit session started with sceneDepth")
    }

    func stop() {
        arSession?.pause()
        isRunning = false
        closestDistance = Float.greatestFiniteMagnitude
        print("[LiDARManager] Session stopped")
    }

    /// Expose the ARSession for VisionManager frame capture
    var session: ARSession? { arSession }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastProcessTime >= minProcessInterval else { return }
        guard !isProcessing else { return }
        lastProcessTime = now

        guard let depthMap = frame.sceneDepth?.depthMap else { return }
        isProcessing = true
        processingQueue.async { [weak self] in
            self?.processDepthMap(depthMap)
            self?.isProcessing = false
        }
    }

    private func processDepthMap(_ depthMap: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        var minDist: Float = Float.greatestFiniteMagnitude
        var minX: Int = width / 2

        // Only scan TOP 50% of Y-axis (ignore ground/cane)
        let yStart = 0
        let yEnd = height / 2

        for y in yStart..<yEnd {
            for x in 0..<width {
                let index = y * width + x
                let depth = buffer[index]
                guard depth > 0 && depth < 10 else { continue }
                if depth < minDist {
                    minDist = depth
                    minX = x
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.closestDistance = minDist
            self?.closestNormalizedX = Float(minX) / Float(width)
        }
    }
}
