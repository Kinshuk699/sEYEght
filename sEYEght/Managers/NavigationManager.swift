//
//  NavigationManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import MapKit
import AVFoundation
import CoreLocation

/// F-004: Voice Destination Routing.
/// Calculates walking routes and speaks turn-by-turn directions.
@Observable
final class NavigationManager: NSObject, CLLocationManagerDelegate {
    var currentDestination: String?
    var nextInstruction: String?
    var isNavigating = false
    var currentRoute: MKRoute?

    private let locationManager = CLLocationManager()
    /// Callback so Dashboard can speak through its single synthesizer
    var onSpeechRequest: ((String) -> Void)?
    private var currentStepIndex = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // NOTE: allowsBackgroundLocationUpdates requires UIBackgroundModes with "location"
        // in Info.plist — set only when navigation starts, not at init time.
        print("[NavigationManager] Initialized")
    }

    /// Calculate a walking route to a destination string.
    func navigateTo(_ destination: String) async {
        print("[NavigationManager] Routing to: \(destination)")
        currentDestination = destination

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destination

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()

            guard let mapItem = response.mapItems.first else {
                print("[NavigationManager] ❌ No results found for '\(destination)'")
                return
            }

            let dirRequest = MKDirections.Request()
            dirRequest.source = MKMapItem.forCurrentLocation()
            dirRequest.destination = mapItem
            dirRequest.transportType = .walking

            let directions = MKDirections(request: dirRequest)
            let dirResponse = try await directions.calculate()

            guard let route = dirResponse.routes.first else {
                print("[NavigationManager] ❌ No walking route found")
                return
            }

            currentRoute = route
            currentStepIndex = 0
            isNavigating = true
            // Enable background tracking only if UIBackgroundModes contains "location"
            let bgModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
            if bgModes.contains("location") {
                locationManager.allowsBackgroundLocationUpdates = true
                locationManager.pausesLocationUpdatesAutomatically = false
            }
            locationManager.startUpdatingLocation()

            if let firstStep = route.steps.first {
                nextInstruction = firstStep.instructions
                speakInstruction(firstStep.instructions)
            }

            print("[NavigationManager] ✅ Route calculated: \(route.steps.count) steps, \(route.distance)m")

        } catch {
            print("[NavigationManager] ❌ Route calculation failed: \(error)")
        }
    }

    func stopNavigation() {
        isNavigating = false
        currentRoute = nil
        currentDestination = nil
        nextInstruction = nil
        locationManager.stopUpdatingLocation()
        print("[NavigationManager] Navigation stopped")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isNavigating, let route = currentRoute, let location = locations.last else { return }

        let steps = route.steps
        guard currentStepIndex < steps.count else {
            speakInstruction("You have arrived at your destination.")
            stopNavigation()
            return
        }

        let step = steps[currentStepIndex]
        let stepLocation = CLLocation(
            latitude: step.polyline.coordinate.latitude,
            longitude: step.polyline.coordinate.longitude
        )

        let distanceToStep = location.distance(from: stepLocation)

        if distanceToStep < 20 {
            currentStepIndex += 1
            if currentStepIndex < steps.count {
                let nextStep = steps[currentStepIndex]
                nextInstruction = nextStep.instructions
                speakInstruction(nextStep.instructions)
                print("[NavigationManager] Step \(currentStepIndex): \(nextStep.instructions)")
            }
        }
    }

    private func speakInstruction(_ text: String) {
        guard !text.isEmpty else { return }

        AudioSessionManager.shared.beginSpeaking()
        print("[NavigationManager] 🔊 Speaking: \(text)")

        if let onSpeechRequest = onSpeechRequest {
            onSpeechRequest(text)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(text.count) * 0.06) {
            AudioSessionManager.shared.endSpeaking()
        }
    }

    /// Reverse-geocode the user's current GPS location and speak it aloud.
    func speakCurrentLocation() {
        guard let location = locationManager.location else {
            speakInstruction("Location not available yet.")
            return
        }

        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }

            if let error = error {
                print("[NavigationManager] ❌ Reverse geocode failed: \(error)")
                self.speakInstruction("Could not determine your location.")
                return
            }

            guard let placemark = placemarks?.first else {
                self.speakInstruction("Could not determine your location.")
                return
            }

            var parts: [String] = []
            if let street = placemark.thoroughfare {
                if let number = placemark.subThoroughfare {
                    parts.append("\(number) \(street)")
                } else {
                    parts.append(street)
                }
            }
            if let city = placemark.locality {
                parts.append(city)
            }

            let locationText = parts.isEmpty ? "Unknown location" : parts.joined(separator: ", ")
            print("[NavigationManager] 📍 Current location: \(locationText)")
            self.speakInstruction("You are near \(locationText)")
        }
    }
}
