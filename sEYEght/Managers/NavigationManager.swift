//
//  NavigationManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import MapKit
import AVFoundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

/// F-004: Voice Destination Routing.
/// Searches for places, reads results aloud, calculates walking routes,
/// and delivers turn-by-turn directions with voice + haptic feedback.
@Observable
final class NavigationManager: NSObject, CLLocationManagerDelegate {
    var currentDestination: String?
    var nextInstruction: String?
    var isNavigating = false
    var currentRoute: MKRoute?

    /// Search results waiting for user selection
    var pendingSearchResults: [MKMapItem] = []
    var isWaitingForSelection = false

    private let locationManager = CLLocationManager()
    /// Callback so Dashboard can speak through its single synthesizer
    var onSpeechRequest: ((String) -> Void)?
    /// Callback for priority speech (interrupts current)
    var onPrioritySpeechRequest: ((String) -> Void)?
    /// Callback to sync selection state to SpeechManager
    var onSelectionStateChanged: ((Bool) -> Void)?
    private var currentStepIndex = 0
    /// Track if user has been warned about being off-course recently
    private var lastOffCourseWarning: Date = .distantPast

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        print("[NavigationManager] Initialized")
    }

    // MARK: - Search Flow

    /// Search for a destination and read results aloud.
    func searchDestination(_ query: String) async {
        speakInstruction("Searching for \(query)")
        print("[NavigationManager] Searching for: \(query)")

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Bias search to user's current location
        if let location = locationManager.location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )
        }

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            let items = Array(response.mapItems.prefix(3))

            guard !items.isEmpty else {
                speakInstruction("I couldn't find that place. Try again with a different name.")
                print("[NavigationManager] No results for '\(query)'")
                return
            }

            if items.count == 1 {
                // Single result — go straight to routing
                let item = items[0]
                let name = item.name ?? query
                let distance = distanceString(to: item)
                speakInstruction("I found \(name), \(distance) away. Starting route.")
                await startRouteToItem(item)
            } else {
                // Multiple results — read them and wait for selection
                pendingSearchResults = items
                isWaitingForSelection = true
                onSelectionStateChanged?(true)

                var announcement = "I found \(items.count) places. "
                let ordinals = ["First", "Second", "Third"]
                for (i, item) in items.enumerated() {
                    let name = item.name ?? "Unknown"
                    let distance = distanceString(to: item)
                    let street = item.placemark.thoroughfare ?? ""
                    let streetPart = street.isEmpty ? "" : " on \(street)"
                    announcement += "\(ordinals[i]): \(name), \(distance) away\(streetPart). "
                }
                announcement += "Say first, second, or third."
                speakInstruction(announcement)
                print("[NavigationManager] Read \(items.count) results, waiting for selection")
            }
        } catch {
            speakInstruction("Search failed. Please try again.")
            print("[NavigationManager] Search error: \(error)")
        }
    }

    /// User selected a search result by index (0-based)
    func selectSearchResult(at index: Int) async {
        guard index >= 0, index < pendingSearchResults.count else {
            speakInstruction("Invalid selection. Say first, second, or third.")
            return
        }

        let item = pendingSearchResults[index]
        let name = item.name ?? "destination"
        isWaitingForSelection = false
        onSelectionStateChanged?(false)
        pendingSearchResults = []

        speakInstruction("Navigating to \(name). Calculating route.")
        await startRouteToItem(item)
    }

    // MARK: - Route Calculation

    /// Calculate and start a walking route to a specific map item.
    private func startRouteToItem(_ mapItem: MKMapItem) async {
        let name = mapItem.name ?? "destination"
        currentDestination = name

        do {
            let dirRequest = MKDirections.Request()
            dirRequest.source = MKMapItem.forCurrentLocation()
            dirRequest.destination = mapItem
            dirRequest.transportType = .walking

            let directions = MKDirections(request: dirRequest)
            let dirResponse = try await directions.calculate()

            guard let route = dirResponse.routes.first else {
                speakInstruction("No walking route found to \(name).")
                print("[NavigationManager] No route to '\(name)'")
                return
            }

            currentRoute = route
            currentStepIndex = 0
            isNavigating = true
            lastOffCourseWarning = .distantPast

            // Enable background tracking if available
            let bgModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
            if bgModes.contains("location") {
                locationManager.allowsBackgroundLocationUpdates = true
                locationManager.pausesLocationUpdatesAutomatically = false
            }
            locationManager.startUpdatingLocation()

            // Success haptic
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            // Announce route start
            let totalDistance = formatDistance(route.distance)
            let firstInstruction = route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? ""
            let startAnnouncement = firstInstruction.isEmpty
                ? "Starting route. \(totalDistance) total. Say stop navigation to cancel anytime."
                : "\(firstInstruction). \(totalDistance) total. Say stop navigation to cancel anytime."
            nextInstruction = firstInstruction
            speakInstruction(startAnnouncement)

            print("[NavigationManager] Route started: \(route.steps.count) steps, \(route.distance)m")

        } catch {
            speakInstruction("Route calculation failed. Please try again.")
            print("[NavigationManager] Route error: \(error)")
        }
    }

    /// Legacy method — still useful for direct routing by string
    func navigateTo(_ destination: String) async {
        await searchDestination(destination)
    }

    func stopNavigation() {
        guard isNavigating || isWaitingForSelection else { return }

        let wasNavigating = isNavigating
        isNavigating = false
        isWaitingForSelection = false
        onSelectionStateChanged?(false)
        pendingSearchResults = []
        currentRoute = nil
        currentDestination = nil
        nextInstruction = nil
        currentStepIndex = 0
        locationManager.stopUpdatingLocation()

        if wasNavigating {
            #if canImport(UIKit)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            #endif
            speakInstruction("Navigation cancelled.")
        }
        print("[NavigationManager] Navigation stopped")
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isNavigating, let route = currentRoute, let location = locations.last else { return }

        let steps = route.steps.filter { !$0.instructions.isEmpty }
        guard currentStepIndex < steps.count else {
            // Arrived
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
            speakPriority("You have arrived at \(currentDestination ?? "your destination").")
            stopNavigation()
            return
        }

        let step = steps[currentStepIndex]
        let stepLocation = CLLocation(
            latitude: step.polyline.coordinate.latitude,
            longitude: step.polyline.coordinate.longitude
        )

        let distanceToStep = location.distance(from: stepLocation)

        // Off-course detection: if >50m from the route polyline
        let distanceFromRoute = minimumDistanceToRoute(from: location)
        if distanceFromRoute > 50 && Date().timeIntervalSince(lastOffCourseWarning) > 15 {
            lastOffCourseWarning = Date()
            #if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            #endif
            speakPriority("You seem to be off route. Recalculating.")
            Task { @MainActor in
                // Recalculate
                if let dest = currentDestination {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = dest
                    if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                        await startRouteToItem(item)
                    }
                }
            }
            return
        }

        // Approaching next step
        if distanceToStep < 20 {
            currentStepIndex += 1
            if currentStepIndex < steps.count {
                let nextStep = steps[currentStepIndex]
                nextInstruction = nextStep.instructions

                // Directional haptic
                playTurnHaptic(for: nextStep.instructions)

                speakInstruction(nextStep.instructions)
                print("[NavigationManager] Step \(currentStepIndex): \(nextStep.instructions)")
            } else {
                // Last step — arrival
                #if canImport(UIKit)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                #endif
                speakPriority("You have arrived at \(currentDestination ?? "your destination").")
                stopNavigation()
            }
        }
    }

    // MARK: - Turn Haptics

    /// Play a directional haptic pattern for turn instructions
    private func playTurnHaptic(for instruction: String) {
        #if canImport(UIKit)
        let lower = instruction.lowercased()
        let generator = UIImpactFeedbackGenerator(style: .medium)

        if lower.contains("left") {
            // 2 quick pulses for left
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                generator.impactOccurred()
            }
        } else if lower.contains("right") {
            // 2 quick pulses for right
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                generator.impactOccurred()
            }
        }
        // Straight = no haptic
        #endif
    }

    // MARK: - Speech

    private func speakInstruction(_ text: String) {
        guard !text.isEmpty else { return }
        print("[NavigationManager] Speaking: \(text)")
        onSpeechRequest?(text)
    }

    private func speakPriority(_ text: String) {
        guard !text.isEmpty else { return }
        print("[NavigationManager] Priority: \(text)")
        if let onPriority = onPrioritySpeechRequest {
            onPriority(text)
        } else {
            onSpeechRequest?(text)
        }
    }

    // MARK: - Location

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
                print("[NavigationManager] Reverse geocode failed: \(error)")
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
            print("[NavigationManager] Current location: \(locationText)")
            self.speakInstruction("You are near \(locationText)")
        }
    }

    // MARK: - Helpers

    /// Human-readable distance from user to a map item
    private func distanceString(to item: MKMapItem) -> String {
        guard let userLocation = locationManager.location else { return "unknown distance" }
        let itemLocation = CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        let meters = userLocation.distance(from: itemLocation)
        return formatDistance(meters)
    }

    /// Format meters into spoken distance
    private func formatDistance(_ meters: Double) -> String {
        if meters < 200 {
            let feet = Int(meters * 3.28084)
            return "\(feet) feet"
        } else if meters < 1000 {
            return "\(Int(meters)) meters"
        } else {
            let km = meters / 1000.0
            return String(format: "%.1f kilometers", km)
        }
    }

    /// Calculate minimum distance from a location to the route polyline
    private func minimumDistanceToRoute(from location: CLLocation) -> Double {
        guard let route = currentRoute else { return 0 }

        // Check distance to each step location
        let steps = route.steps
        var minDist = Double.greatestFiniteMagnitude
        for step in steps {
            let stepLoc = CLLocation(
                latitude: step.polyline.coordinate.latitude,
                longitude: step.polyline.coordinate.longitude
            )
            let dist = location.distance(from: stepLoc)
            if dist < minDist { minDist = dist }
        }
        return minDist
    }
}
