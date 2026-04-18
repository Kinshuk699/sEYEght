//
//  PermissionsManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import AVFoundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

@Observable
final class PermissionsManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var foregroundObserver: NSObjectProtocol?

    var cameraStatus: Bool = false
    var locationStatus: Bool = false

    /// Whether the user has never been asked (true = we can show the system dialog)
    var cameraNotDetermined: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
    }
    var locationNotDetermined: Bool {
        locationManager.authorizationStatus == .notDetermined
    }

    override init() {
        super.init()
        locationManager.delegate = self
        checkCurrentStatuses()

        // Force re-check when returning from iOS Settings
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkCurrentStatuses()
        }

        print("[PermissionsManager] Initialized, checking current statuses")
    }

    deinit {
        locationManager.delegate = nil
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func checkCurrentStatuses() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let locStatus = locationManager.authorizationStatus
        locationStatus = (locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways)
        print("[PermissionsManager] Camera=\(cameraStatus), Location=\(locationStatus)")
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
        cameraStatus && locationStatus
    }
}
