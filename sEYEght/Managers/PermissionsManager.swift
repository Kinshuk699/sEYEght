//
//  PermissionsManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import AVFoundation
import CoreLocation
import Speech
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class PermissionsManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    var cameraStatus: Bool = false
    var locationStatus: Bool = false
    var microphoneStatus: Bool = false
    var speechStatus: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        checkCurrentStatuses()
        print("[PermissionsManager] Initialized, checking current statuses")
    }

    func checkCurrentStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let locStatus = locationManager.authorizationStatus
        locationStatus = (locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways)
        microphoneStatus = AVAudioApplication.shared.recordPermission == .granted
        speechStatus = SFSpeechRecognizer.authorizationStatus() == .authorized
        print("[PermissionsManager] Camera=\(cameraStatus), Location=\(locationStatus), Mic=\(microphoneStatus), Speech=\(speechStatus)")
    }

    func requestCamera() {
        print("[PermissionsManager] Requesting camera access")
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraStatus = granted
                self?.confirmGrant(granted: granted, name: "Camera")
            }
        }
    }

    func requestLocation() {
        print("[PermissionsManager] Requesting location access")
        locationManager.requestWhenInUseAuthorization()
    }

    func requestMicrophone() {
        print("[PermissionsManager] Requesting microphone access")
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphoneStatus = granted
                self?.confirmGrant(granted: granted, name: "Microphone")
            }
        }
    }

    func requestSpeechRecognition() {
        print("[PermissionsManager] Requesting speech recognition access")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                let granted = status == .authorized
                self?.speechStatus = granted
                self?.confirmGrant(granted: granted, name: "Speech Recognition")
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let locStatus = manager.authorizationStatus
        let granted = (locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways)
        locationStatus = granted
        confirmGrant(granted: granted, name: "Location")
        print("[PermissionsManager] Location authorization changed: \(locStatus.rawValue)")
    }

    private func confirmGrant(granted: Bool, name: String) {
        if granted {
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
            print("[PermissionsManager] ✅ \(name) granted")
        } else {
            print("[PermissionsManager] ❌ \(name) denied")
        }
    }

    var allGranted: Bool {
        cameraStatus && locationStatus && microphoneStatus && speechStatus
    }
}
