//
//  AppState.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import Foundation
import Observation

@Observable
final class AppState {
    // MARK: - Permissions
    var cameraGranted = false
    var locationGranted = false
    var microphoneGranted = false
    var speechRecognitionGranted = false

    var allPermissionsGranted: Bool {
        cameraGranted && locationGranted && microphoneGranted && speechRecognitionGranted
    }

    // MARK: - Navigation
    var currentDestination: String? = nil
    var nextInstruction: String? = nil
    var isNavigating = false

    // MARK: - Session
    var isListeningForWakeWord = false
    var isSeyeghtActive = false

    // MARK: - Subscription
    var isAIVisionSubscribed = false

    init() {
        print("[AppState] Initialized")
    }
}
