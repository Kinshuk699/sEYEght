//
//  ARCameraView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/4/26.
//

import SwiftUI
import ARKit

/// Renders the live ARKit camera feed by connecting to an existing ARSession.
/// The view shows what the rear camera sees — sighted users/developers can
/// visually confirm LiDAR is working.
struct ARCameraView: UIViewRepresentable {
    let session: ARSession?
    /// Callback providing the SCNScene once the view is created, for adding navigation nodes
    var onSceneReady: ((SCNScene) -> Void)?

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.automaticallyUpdatesLighting = true
        arView.rendersCameraGrain = false
        // Don't show debug visualizations by default — keep it clean
        arView.debugOptions = []
        // No scene interaction needed
        arView.isUserInteractionEnabled = false
        // Notify that scene is ready for overlay nodes
        onSceneReady?(arView.scene)
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Attach to the shared ARSession from LiDARManager
        if let session = session, uiView.session !== session {
            uiView.session = session
            // Re-notify after session reconnect
            onSceneReady?(uiView.scene)
        }
    }
}
