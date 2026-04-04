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
        // Guard: don't create duplicate sessions
        guard !isRunning else { return }

        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("[LiDARManager] ❌ Device does not support LiDAR sceneDepth")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth

        // Pause any existing session before creating a new one
        arSession?.pause()

        let session = ARSession()
        session.delegate = self
        session.run(config)
        arSession = session
        isRunning = true
        print("[LiDARManager] ✅ ARKit session started with sceneDepth")
    }

    func stop() {
        arSession?.pause()
        arSession = nil
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

        // Copy depth data immediately so we don't retain the ARFrame
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let depthData: [Float32]
        if let baseAddress = CVPixelBufferGetBaseAddress(depthMap) {
            let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
            depthData = Array(UnsafeBufferPointer(start: buffer, count: width * height))
        } else {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            return
        }
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)

        isProcessing = true
        processingQueue.async { [weak self] in
            self?.processDepthData(depthData, width: width, height: height)
            self?.isProcessing = false
        }
    }

    private func processDepthData(_ buffer: [Float32], width: Int, height: Int) {
        var minDist: Float = Float.greatestFiniteMagnitude
        var minX: Int = width / 2

        // Only scan TOP 50% of Y-axis (ignore ground/cane)
        let yEnd = height / 2

        for y in 0..<yEnd {
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
