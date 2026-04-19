# AR Navigation Overlay + Heading Confirmation — Design Spec

**Date:** 2026-04-19  
**Status:** Approved

## Problem

During active navigation, the user has no visual or spatial sense of which direction to go. Turn-by-turn voice instructions say "turn left on Main Street" but:
1. Partially sighted / legally blind users can't see environmental cues
2. Between turns, there's no confirmation the user is heading the right way
3. Turn haptics are identical for left and right (both are 2 pulses)

## Solution

Four-part navigation overlay system:

### 1. AR Ground Path Line
- Thick neon green line (~0.3m wide) rendered on the ground in AR along the MKRoute polyline
- Shows the next ~50m of route from user's current position
- Glow/emission effect for maximum visibility on any surface
- Updates as user walks — segments behind the user are removed
- Only visible during active navigation

### 2. 3D Turn Arrows at Turn Points
- Large floating arrow nodes (~1m wide) at ~2m height above each turn point
- Arrow direction matches the turn (left-pointing, right-pointing, or straight)
- Neon green with pulsing opacity animation
- Show next 2-3 upcoming turns; remove passed turns
- Only visible during active navigation

### 3. Compass Arrow SwiftUI Overlay
- Persistent small arrow at bottom of camera feed
- Always points toward the next waypoint direction
- Shows distance to next turn: "↑ 50m" or "← 20m Turn left"
- Backup for when camera isn't pointing at ground

### 4. Heading Confirmation Between Turns
- Every ~10 seconds on straight segments: gentle haptic pulse if heading is correct (within 30° of route bearing)
- If heading drifts >30° from route bearing: spoken "bear left" or "bear right"
- At turns (<20m from turn point): distinct haptic pattern + voice announcement
- Approaching destination (<20m): increasing haptic frequency

## Technical Design

### ARKit World Alignment
- Change `ARWorldTrackingConfiguration.worldAlignment` from `.gravity` (default) to `.gravityAndHeading`
- This aligns: Y = up (gravity), X ≈ east, Z ≈ south
- Enables direct GPS → AR coordinate mapping

### GPS → AR Coordinate Conversion
For a route point at (lat, lon) relative to user at (userLat, userLon):
- `deltaLat = (lat - userLat)` → north offset in meters: `deltaLat * 111_320`
- `deltaLon = (lon - userLon)` → east offset in meters: `deltaLon * 111_320 * cos(userLat)`
- AR position: `SCNVector3(eastOffset, groundY, -northOffset)` (Z points south, so north = negative Z)
- `groundY` = approximately -1.5 (phone at chest = ~1.5m above ground)

### New Files
- `Managers/ARNavigationOverlay.swift` — manages SceneKit nodes for path line + turn arrows + coordinate conversion
- Dashboard gets a new compass arrow SwiftUI overlay

### Modified Files
- `Components/ARCameraView.swift` — accept callback for adding/updating navigation nodes
- `Managers/NavigationManager.swift` — heading confirmation logic, expose route geometry
- `Views/DashboardView.swift` — compass arrow overlay + wire overlay to navigation state
- `Managers/LiDARManager.swift` — switch to `.gravityAndHeading` alignment

## Color
- Neon green: `UIColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)`
- Glow via SCNMaterial emission property
- Maximum contrast for legally blind users

## Activation
- AR overlay and heading confirmation only activate during `navigationManager.isNavigating == true`
- When navigation stops, all nodes are removed from the scene
- Compass overlay hides when not navigating
