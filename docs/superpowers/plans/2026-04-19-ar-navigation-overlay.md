# AR Navigation Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add AR ground path lines, 3D turn arrows, compass overlay, and heading confirmation during active navigation.

**Architecture:** SceneKit nodes added to existing ARSCNView for ground path + turn arrows. SwiftUI overlay for compass arrow. NavigationManager gains heading monitoring via CLLocationManager heading updates. LiDAR configuration switches to `.gravityAndHeading` for world-aligned coordinates.

**Tech Stack:** ARKit, SceneKit, CoreLocation (heading), MapKit (route geometry), SwiftUI

---

### Task 1: Switch LiDAR to gravityAndHeading alignment

**Files:**
- Modify: `sEYEght/Managers/LiDARManager.swift`

- [ ] **Step 1: Add worldAlignment to ARWorldTrackingConfiguration**

In `LiDARManager.start()`, after creating the config, set world alignment:

```swift
let config = ARWorldTrackingConfiguration()
config.frameSemantics = .sceneDepth
config.worldAlignment = .gravityAndHeading  // X=east, Z=south for GPS mapping
```

- [ ] **Step 2: Expose camera transform for heading calculations**

Add a published property to LiDARManager:

```swift
/// Current camera transform — used by ARNavigationOverlay for coordinate mapping
var cameraTransform: simd_float4x4 = matrix_identity_float4x4
```

In `session(_:didUpdate:)`, before the guard for `minProcessInterval`, update it:

```swift
func session(_ session: ARSession, didUpdate frame: ARFrame) {
    // Always update camera transform (cheap, no throttle needed)
    DispatchQueue.main.async { [weak self] in
        self?.cameraTransform = frame.camera.transform
    }
    
    let now = frame.timestamp
    // ... rest of existing code
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project sEYEght.xcodeproj -scheme sEYEght -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

---

### Task 2: Create ARNavigationOverlay manager

**Files:**
- Create: `sEYEght/Managers/ARNavigationOverlay.swift`

- [ ] **Step 1: Create the ARNavigationOverlay class**

```swift
//
//  ARNavigationOverlay.swift
//  sEYEght
//

import SceneKit
import CoreLocation
import MapKit

/// Manages SceneKit nodes for AR navigation: ground path line + turn arrows.
/// Nodes are added to the ARSCNView's scene. Coordinates use gravityAndHeading
/// alignment: X=east, Y=up, Z=south.
final class ARNavigationOverlay {
    
    // MARK: - Configuration
    
    /// Neon green color for path and arrows
    private let neonGreen = UIColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
    /// Width of the ground path line in meters
    private let pathWidth: Float = 0.3
    /// Height above ground for turn arrows (meters)
    private let arrowHeight: Float = 2.0
    /// Maximum distance ahead to render path (meters)
    private let maxPathDistance: Double = 50.0
    /// Size of turn arrow (meters)
    private let arrowSize: Float = 1.0
    /// Ground Y offset (phone at chest ~1.5m, ground is below)
    private let groundY: Float = -1.5
    
    // MARK: - State
    
    private weak var scene: SCNScene?
    private var pathNodes: [SCNNode] = []
    private var arrowNodes: [SCNNode] = []
    private let rootNode = SCNNode()
    
    // MARK: - Setup
    
    /// Attach to an ARSCNView's scene
    func attach(to scene: SCNScene) {
        self.scene = scene
        rootNode.name = "navigationOverlay"
        scene.rootNode.addChildNode(rootNode)
    }
    
    /// Remove all navigation nodes from the scene
    func detach() {
        rootNode.removeFromParentNode()
        pathNodes.removeAll()
        arrowNodes.removeAll()
    }
    
    // MARK: - Update
    
    /// Update the AR overlay with current route and user position.
    /// Call this at ~1-2 Hz from the ARSession delegate.
    func update(
        route: MKRoute,
        userLocation: CLLocation,
        currentStepIndex: Int
    ) {
        // Clear old nodes
        clearNodes()
        
        // Get route polyline coordinates
        let pointCount = route.polyline.pointCount
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        route.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        
        // Find closest point on route to user
        let userCoord = userLocation.coordinate
        var closestIndex = 0
        var closestDist = Double.greatestFiniteMagnitude
        for (i, coord) in coordinates.enumerated() {
            let d = distanceMeters(from: userCoord, to: coord)
            if d < closestDist {
                closestDist = d
                closestIndex = i
            }
        }
        
        // Render path segments from closest point forward, up to maxPathDistance
        var totalDist: Double = 0
        for i in closestIndex..<(coordinates.count - 1) {
            let segDist = distanceMeters(from: coordinates[i], to: coordinates[i + 1])
            if totalDist + segDist > maxPathDistance { break }
            
            let startAR = gpsToAR(from: userCoord, to: coordinates[i])
            let endAR = gpsToAR(from: userCoord, to: coordinates[i + 1])
            
            let pathNode = createPathSegment(from: startAR, to: endAR)
            rootNode.addChildNode(pathNode)
            pathNodes.append(pathNode)
            
            totalDist += segDist
        }
        
        // Render turn arrows at step locations
        let steps = route.steps.filter { !$0.instructions.isEmpty }
        let stepsToShow = steps.dropFirst(currentStepIndex).prefix(3)
        
        for step in stepsToShow {
            let stepCoord = step.polyline.coordinate
            let stepDist = distanceMeters(from: userCoord, to: stepCoord)
            guard stepDist < maxPathDistance * 1.5 else { continue }
            
            let arPos = gpsToAR(from: userCoord, to: stepCoord)
            let direction = turnDirection(from: step.instructions)
            let arrowNode = createTurnArrow(at: arPos, direction: direction)
            rootNode.addChildNode(arrowNode)
            arrowNodes.append(arrowNode)
        }
    }
    
    // MARK: - Node Creation
    
    /// Create a glowing path segment between two AR points on the ground
    private func createPathSegment(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let dx = end.x - start.x
        let dz = end.z - start.z
        let length = sqrt(dx * dx + dz * dz)
        guard length > 0.01 else { return SCNNode() }
        
        // Flat box for path segment
        let box = SCNBox(width: CGFloat(pathWidth), height: 0.02, length: CGFloat(length), chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = neonGreen
        material.emission.contents = neonGreen  // Glow effect
        material.emission.intensity = 1.5
        material.transparency = 0.85
        box.materials = [material]
        
        let node = SCNNode(geometry: box)
        
        // Position at midpoint between start and end
        node.position = SCNVector3(
            (start.x + end.x) / 2,
            groundY,
            (start.z + end.z) / 2
        )
        
        // Rotate to align with direction
        let angle = atan2(dx, dz)
        node.eulerAngles.y = angle
        
        return node
    }
    
    /// Create a turn arrow floating above a turn point
    private func createTurnArrow(at position: SCNVector3, direction: TurnDirection) -> SCNNode {
        let node = SCNNode()
        node.position = SCNVector3(position.x, groundY + arrowHeight, position.z)
        
        // Arrow shape: cone pointing in turn direction
        let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(arrowSize / 2), height: CGFloat(arrowSize))
        let material = SCNMaterial()
        material.diffuse.contents = neonGreen
        material.emission.contents = neonGreen
        material.emission.intensity = 2.0
        cone.materials = [material]
        
        let arrowNode = SCNNode(geometry: cone)
        
        // Rotate cone to point in turn direction (cone default points up along Y)
        switch direction {
        case .left:
            arrowNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)  // Point left
        case .right:
            arrowNode.eulerAngles = SCNVector3(0, 0, -Float.pi / 2) // Point right
        case .straight:
            arrowNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)  // Point forward
        }
        
        node.addChildNode(arrowNode)
        
        // Pulsing animation
        let pulse = SCNAction.sequence([
            SCNAction.fadeOpacity(to: 0.5, duration: 0.8),
            SCNAction.fadeOpacity(to: 1.0, duration: 0.8)
        ])
        node.runAction(SCNAction.repeatForever(pulse))
        
        return node
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a GPS coordinate to AR world coordinates relative to user position.
    /// With gravityAndHeading: X = east, Y = up, Z = south
    private func gpsToAR(from userCoord: CLLocationCoordinate2D, to targetCoord: CLLocationCoordinate2D) -> SCNVector3 {
        let latDelta = targetCoord.latitude - userCoord.latitude
        let lonDelta = targetCoord.longitude - userCoord.longitude
        
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(userCoord.latitude * .pi / 180)
        
        let northOffset = Float(latDelta * metersPerDegreeLat)   // positive = north
        let eastOffset = Float(lonDelta * metersPerDegreeLon)     // positive = east
        
        // gravityAndHeading: X = east, Z = south (so north = -Z)
        return SCNVector3(eastOffset, 0, -northOffset)
    }
    
    /// Distance in meters between two coordinates
    private func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
    
    // MARK: - Helpers
    
    private func clearNodes() {
        for node in pathNodes { node.removeFromParentNode() }
        for node in arrowNodes { node.removeFromParentNode() }
        pathNodes.removeAll()
        arrowNodes.removeAll()
    }
    
    enum TurnDirection {
        case left, right, straight
    }
    
    private func turnDirection(from instruction: String) -> TurnDirection {
        let lower = instruction.lowercased()
        if lower.contains("left") { return .left }
        if lower.contains("right") { return .right }
        return .straight
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project sEYEght.xcodeproj -scheme sEYEght -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

---

### Task 3: Update ARCameraView to expose SCNScene

**Files:**
- Modify: `sEYEght/Components/ARCameraView.swift`

- [ ] **Step 1: Add scene callback to ARCameraView**

Replace the current ARCameraView with a version that exposes its SCNScene:

```swift
import SwiftUI
import ARKit

/// Renders the live ARKit camera feed by connecting to an existing ARSession.
struct ARCameraView: UIViewRepresentable {
    let session: ARSession?
    /// Callback providing the SCNScene once the view is created, for adding navigation nodes
    var onSceneReady: ((SCNScene) -> Void)?

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.automaticallyUpdatesLighting = true
        arView.rendersCameraGrain = false
        arView.debugOptions = []
        arView.isUserInteractionEnabled = false
        // Notify that scene is ready for overlay nodes
        onSceneReady?(arView.scene)
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if let session = session, uiView.session !== session {
            uiView.session = session
            // Re-notify after session reconnect
            onSceneReady?(uiView.scene)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project sEYEght.xcodeproj -scheme sEYEght -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

---

### Task 4: Add heading confirmation to NavigationManager

**Files:**
- Modify: `sEYEght/Managers/NavigationManager.swift`

- [ ] **Step 1: Add heading monitoring properties**

Add these properties to NavigationManager (after the existing properties):

```swift
/// Heading confirmation: bearing to next step
private var targetBearing: Double = 0
/// Timer for periodic heading checks
private var headingCheckTimer: Timer?
/// Last time we gave a heading confirmation
private var lastHeadingConfirmation: Date = .distantPast
/// Heading confirmation interval in seconds
private let headingConfirmInterval: TimeInterval = 10.0
```

- [ ] **Step 2: Enable heading updates in startRouteToItem**

After `locationManager.startUpdatingLocation()` in `startRouteToItem`, add:

```swift
locationManager.startUpdatingHeading()
updateTargetBearing()
startHeadingConfirmation()
```

- [ ] **Step 3: Add heading update delegate method**

Add the CLLocationManagerDelegate method:

```swift
func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard isNavigating else { return }
    // Heading is available — used by heading confirmation timer
}
```

- [ ] **Step 4: Add heading confirmation methods**

```swift
// MARK: - Heading Confirmation

private func startHeadingConfirmation() {
    headingCheckTimer?.invalidate()
    headingCheckTimer = Timer.scheduledTimer(withTimeInterval: headingConfirmInterval, repeats: true) { [weak self] _ in
        self?.checkHeading()
    }
}

private func stopHeadingConfirmation() {
    headingCheckTimer?.invalidate()
    headingCheckTimer = nil
}

private func updateTargetBearing() {
    guard let route = currentRoute, let userLoc = locationManager.location else { return }
    let steps = route.steps.filter { !$0.instructions.isEmpty }
    guard currentStepIndex < steps.count else { return }
    
    let step = steps[currentStepIndex]
    let stepCoord = step.polyline.coordinate
    targetBearing = bearing(from: userLoc.coordinate, to: stepCoord)
}

private func checkHeading() {
    guard isNavigating else { return }
    guard let heading = locationManager.heading, heading.headingAccuracy >= 0 else { return }
    
    let userHeading = heading.trueHeading
    var diff = targetBearing - userHeading
    // Normalize to -180...180
    while diff > 180 { diff -= 360 }
    while diff < -180 { diff += 360 }
    
    if abs(diff) < 30 {
        // On track — gentle haptic
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.5)
        #endif
    } else if diff > 30 {
        // Drifting right, need to bear left
        speakInstruction("Bear left.")
    } else {
        // Drifting left, need to bear right
        speakInstruction("Bear right.")
    }
}

/// Calculate bearing in degrees from one coordinate to another
private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
    let lat1 = start.latitude * .pi / 180
    let lat2 = end.latitude * .pi / 180
    let dLon = (end.longitude - start.longitude) * .pi / 180
    
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    
    var bearing = atan2(y, x) * 180 / .pi
    if bearing < 0 { bearing += 360 }
    return bearing
}
```

- [ ] **Step 5: Update stopNavigation to clean up heading**

In `stopNavigation()`, after `locationManager.stopUpdatingLocation()`, add:

```swift
locationManager.stopUpdatingHeading()
stopHeadingConfirmation()
```

- [ ] **Step 6: Update step advancement to refresh target bearing**

In `locationManager(_:didUpdateLocations:)`, after `currentStepIndex += 1` and the next step announcement, add:

```swift
updateTargetBearing()
```

- [ ] **Step 7: Improve turn haptics with distinct left/right patterns**

Replace the existing `playTurnHaptic(for:)` method:

```swift
/// Play a directional haptic pattern for turn instructions
private func playTurnHaptic(for instruction: String) {
    #if canImport(UIKit)
    let lower = instruction.lowercased()
    
    if lower.contains("left") {
        // Left turn: 2 quick pulses
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            gen.impactOccurred(intensity: 1.0)
        }
    } else if lower.contains("right") {
        // Right turn: 3 quick pulses (distinct from left)
        let gen = UIImpactFeedbackGenerator(style: .heavy)
        gen.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            gen.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                gen.impactOccurred(intensity: 1.0)
            }
        }
    } else {
        // Straight / continue: single firm pulse
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred(intensity: 0.8)
    }
    #endif
}
```

- [ ] **Step 8: Expose route data for AR overlay**

Add a public computed property:

```swift
/// Current step index — exposed for AR overlay
var activeStepIndex: Int { currentStepIndex }
```

- [ ] **Step 9: Build and verify**

Run: `xcodebuild -project sEYEght.xcodeproj -scheme sEYEght -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

---

### Task 5: Add compass arrow overlay + wire everything in DashboardView

**Files:**
- Modify: `sEYEght/Views/DashboardView.swift`

- [ ] **Step 1: Add AR overlay and compass state properties**

Add to DashboardView's properties:

```swift
/// AR navigation overlay manager
@State private var arOverlay = ARNavigationOverlay()
/// Compass bearing to next waypoint (degrees, 0=north)
@State private var compassBearing: Double = 0
/// User's current heading (degrees)
@State private var userHeading: Double = 0
/// Distance to next turn in meters
@State private var distanceToNextTurn: Double = 0
/// Next turn instruction text
@State private var nextTurnText: String = ""
/// Timer for updating AR overlay
@State private var arUpdateTimer: Timer?
```

- [ ] **Step 2: Add compass arrow overlay view**

Add this inside the ZStack, after the bottom bar HStack and before `.contentShape(Rectangle())`:

```swift
// Compass arrow overlay (only during navigation)
if navigationManager.isNavigating {
    VStack {
        Spacer()
        
        HStack(spacing: 12) {
            // Rotating arrow pointing toward next waypoint
            Image(systemName: "location.north.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.2))
                .rotationEffect(.degrees(compassBearing - userHeading))
                .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.2).opacity(0.8), radius: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                if !nextTurnText.isEmpty {
                    Text(nextTurnText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                if distanceToNextTurn > 0 {
                    Text(formatCompassDistance(distanceToNextTurn))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.2, green: 1.0, blue: 0.2))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
        .padding(.bottom, 80) // Above the bottom bar
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nextTurnText.isEmpty ? "Navigating" : "\(nextTurnText), \(formatCompassDistance(distanceToNextTurn))")
    }
}
```

- [ ] **Step 3: Add AR overlay scene attachment**

In the ARCameraView usage, add the onSceneReady callback:

```swift
ARCameraView(session: lidarManager.session, onSceneReady: { scene in
    arOverlay.attach(to: scene)
})
```

- [ ] **Step 4: Add AR overlay update timer**

In the `.onAppear` block, after `lidarManager.start()`, add:

```swift
// Start AR overlay update timer during navigation
startAROverlayUpdates()
```

Add the helper methods:

```swift
private func startAROverlayUpdates() {
    arUpdateTimer?.invalidate()
    arUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        updateAROverlay()
        updateCompassArrow()
    }
}

private func updateAROverlay() {
    guard navigationManager.isNavigating,
          let route = navigationManager.currentRoute,
          let userLoc = navigationManager.userLocation else {
        return
    }
    arOverlay.update(
        route: route,
        userLocation: userLoc,
        currentStepIndex: navigationManager.activeStepIndex
    )
}

private func updateCompassArrow() {
    guard navigationManager.isNavigating,
          let route = navigationManager.currentRoute,
          let userLoc = navigationManager.userLocation else {
        compassBearing = 0
        distanceToNextTurn = 0
        nextTurnText = ""
        return
    }
    
    let steps = route.steps.filter { !$0.instructions.isEmpty }
    let stepIdx = navigationManager.activeStepIndex
    guard stepIdx < steps.count else { return }
    
    let step = steps[stepIdx]
    let stepCoord = step.polyline.coordinate
    let stepLoc = CLLocation(latitude: stepCoord.latitude, longitude: stepCoord.longitude)
    
    distanceToNextTurn = userLoc.distance(from: stepLoc)
    nextTurnText = step.instructions
    compassBearing = bearingBetween(userLoc.coordinate, stepCoord)
    
    // Get device heading from ARKit camera
    if lidarManager.isRunning {
        let transform = lidarManager.cameraTransform
        // Extract yaw from camera transform (rotation around Y axis)
        let forward = simd_float3(-transform.columns.2.x, 0, -transform.columns.2.z)
        let heading = atan2(forward.x, -forward.z) * 180 / .pi
        userHeading = Double(heading < 0 ? heading + 360 : heading)
    }
}

private func bearingBetween(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
    let lat1 = from.latitude * .pi / 180
    let lat2 = to.latitude * .pi / 180
    let dLon = (to.longitude - from.longitude) * .pi / 180
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    var b = atan2(y, x) * 180 / .pi
    if b < 0 { b += 360 }
    return b
}

private func formatCompassDistance(_ meters: Double) -> String {
    if meters < 100 {
        return "\(Int(meters))m"
    } else if meters < 1000 {
        return "\(Int(meters / 10) * 10)m"
    } else {
        return String(format: "%.1f km", meters / 1000)
    }
}
```

- [ ] **Step 5: Clean up AR overlay on navigation stop**

In `.onDisappear`, add:

```swift
arUpdateTimer?.invalidate()
arUpdateTimer = nil
arOverlay.detach()
```

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -project sEYEght.xcodeproj -scheme sEYEght -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`

---

### Task 6: Final integration test

- [ ] **Step 1: Full build**

Run: `xcodebuild -project sEYEght.xcodeproj -scheme sEYEght -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build 2>&1 | grep -E "error:|warning:|BUILD"`

- [ ] **Step 2: Verify no regressions**

Ensure LiDAR obstacle detection still works (depth processing unchanged).
Ensure non-navigation mode has no AR overlay nodes.
Ensure navigation start triggers overlay + heading confirmation.
Ensure navigation stop cleans up all nodes + timers.
