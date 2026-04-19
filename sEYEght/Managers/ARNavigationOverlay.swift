//
//  ARNavigationOverlay.swift
//  sEYEght
//
//  Created by Kinshuk on 4/19/26.
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
        // Don't double-attach
        if self.scene === scene { return }
        detach()
        self.scene = scene
        rootNode.name = "navigationOverlay"
        scene.rootNode.addChildNode(rootNode)
        print("[ARNavigationOverlay] Attached to scene")
    }

    /// Remove all navigation nodes from the scene
    func detach() {
        clearNodes()
        rootNode.removeFromParentNode()
        scene = nil
    }

    // MARK: - Update

    /// Update the AR overlay with current route and user position.
    /// Call this at ~1-2 Hz from a timer.
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

        // Position at midpoint between start and end, on the ground
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
