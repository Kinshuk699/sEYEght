# Blind UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sEYEght genuinely usable by a blind person — the current version is a functional prototype that "works" but has critical UX gaps in directional feedback, voice quality, startup experience, error clarity, and emergency handling.

**Architecture:** All changes modify existing files. No new files needed. Key areas: HapticsManager (directional audio), Narrator (voice download guidance during setup), sEYEghtApp (startup chime), VisionManager (error specificity), DashboardView (emergency persistence + voice verbal end), ConversationalSetupView (voice download phase).

**Tech Stack:** Swift, SwiftUI, AVFoundation, CoreHaptics, ARKit, AVSpeechSynthesizer

**Excluded:** Paywall removal (keeping 3 free/day + subscription), VoiceOver integration (separate effort), voice-controlled settings (separate effort), voice destination entry (separate effort).

---

### Task 1: Directional Audio/Haptics (Left/Right/Center Feedback)

**Files:**
- Modify: `sEYEght/Managers/HapticsManager.swift`
- Modify: `sEYEght/Views/DashboardView.swift`

This is the #1 blind UX gap. LiDAR already provides `closestNormalizedX` (0=left, 1=right) but this is NEVER communicated to the user. A blind person hears "obstacle 2 feet ahead" but has no idea which direction to dodge.

**Approach:** Use stereo audio panning on the proximity tone. Left obstacle = sound in left ear. Right obstacle = sound in right ear. Center = both ears. Also add directional words to distance announcements.

- [ ] **Step 1: Add stereo panning to HapticsManager**

In `sEYEght/Managers/HapticsManager.swift`, change the audio tone from mono to stereo with panning based on obstacle direction.

Replace the `setupAudioTone()` method and add a `tonePan` property:

```swift
/// Stereo panning: -1.0 = full left, 0.0 = center, 1.0 = full right
private var tonePan: Float = 0.0
```

In `setupAudioTone()`, change the format from mono to stereo:
```swift
let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
```

In the `AVAudioSourceNode` render block, apply panning to left/right channels:
```swift
let leftGain = max(0, 1.0 - self.tonePan) * self.audioToneVolume  // louder on left when pan < 0
let rightGain = max(0, 1.0 + self.tonePan) * self.audioToneVolume // louder on right when pan > 0
// Write to channel 0 (left) and channel 1 (right) separately
```

In `updateForDistance(_:)`, add panning update:
```swift
/// Update with both distance and horizontal position (0=left, 1=right)
func updateForDistance(_ distance: Float, normalizedX: Float = 0.5) {
    // Convert 0..1 → -1..+1 for stereo panning
    tonePan = (normalizedX * 2.0) - 1.0
    // ... existing distance logic
}
```

- [ ] **Step 2: Pass direction from DashboardView**

In `sEYEght/Views/DashboardView.swift`, update the `onChange(of: lidarManager.closestDistance)` to pass direction:

```swift
.onChange(of: lidarManager.closestDistance) { _, distance in
    hapticsManager.updateForDistance(distance, normalizedX: lidarManager.closestNormalizedX)
    speakDistanceIfNeeded(distance)
}
```

- [ ] **Step 3: Add direction words to spoken distance warnings**

In `speakDistanceIfNeeded(_:)` in DashboardView, add direction context:

```swift
let direction: String
let x = lidarManager.closestNormalizedX
if x < 0.35 {
    direction = "to your left"
} else if x > 0.65 {
    direction = "to your right"
} else {
    direction = "ahead"
}

let distanceText: String
switch threshold {
case 0.3: distanceText = "Very close \(direction). Less than 1 foot."
case 0.5: distanceText = "Obstacle \(direction). About 2 feet."
case 1.0: distanceText = "Object \(direction). About 3 feet."
default: return
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme sEYEght -destination 'platform=iOS,id=00008120-00086D562650C01E' -derivedDataPath /tmp/sEYEght-build build 2>&1 | grep -E "error:|BUILD" | tail -5`
Expected: `** BUILD SUCCEEDED **`

---

### Task 2: Enhanced Voice Download Guidance During Setup

**Files:**
- Modify: `sEYEght/Managers/Narrator.swift`
- Modify: `sEYEght/Views/ConversationalSetupView.swift`

Compact voices sound robotic. Enhanced/Premium voices require manual download by the user. A blind user won't know to do this. The setup flow should detect voice quality and guide the user through downloading a better voice.

- [ ] **Step 1: Add voice quality check to Narrator**

In `sEYEght/Managers/Narrator.swift`, add a public computed property:

```swift
/// Whether we're using a high-quality voice (enhanced or premium)
var hasHighQualityVoice: Bool {
    guard let voice = selectedVoice else { return false }
    return voice.quality == .enhanced || voice.quality == .premium
}
```

- [ ] **Step 2: Add voice guidance phase to setup**

In `sEYEght/Views/ConversationalSetupView.swift`, add a voice check between Phase 1 (welcome) and Phase 2 (permissions) in `runConversation()`:

```swift
await phaseWelcome()
guard !Task.isCancelled else { return }

// Guide user to download better voice if using basic compact voice
await phaseVoiceCheck()
guard !Task.isCancelled else { return }

await phasePermissions()
```

Add the new phase method:

```swift
private func phaseVoiceCheck() async {
    if Narrator.shared.hasHighQualityVoice {
        // Already has good voice — skip silently
        return
    }

    statusText = "Voice Quality"

    await Narrator.shared.speakAndWait(
        "Quick tip before we continue. My voice might sound a bit robotic right now. You can make it much better by downloading an enhanced voice. Would you like me to guide you through it? Just wait, and I'll tell you how."
    )
    guard !Task.isCancelled else { return }

    try? await Task.sleep(for: .seconds(1.5))
    guard !Task.isCancelled else { return }

    await Narrator.shared.speakAndWait(
        "Open your iPhone Settings app, then go to Accessibility, then Spoken Content, then Voices, then English, then tap Ava, and download the Enhanced version. It's about 150 megabytes. After it downloads, come back to this app. I'll sound much better."
    )
    guard !Task.isCancelled else { return }

    // Open Settings and wait
    await openSettings()

    // Poll for up to 3 minutes for the user to download the voice
    for _ in 0..<360 {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }

        // Check if voices have updated
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let hasEnhanced = voices.contains { $0.language.hasPrefix("en") && $0.quality == .enhanced }
        if hasEnhanced {
            // Re-initialize narrator with the new voice
            await Narrator.shared.speakAndWait("Great, I have a new voice now. Much better, right? Let's continue with the setup.")
            return
        }
    }

    // They didn't download — no big deal, continue
    await Narrator.shared.speakAndWait("No worries, you can do that anytime later. Let's continue.")
}
```

Note: The Narrator singleton selects voice at `init()`. Since `AVSpeechSynthesisVoice.speechVoices()` returns currently available voices, and the Narrator is already initialized, it won't automatically pick up the new voice. We need to add a refresh method.

- [ ] **Step 3: Add voice refresh to Narrator**

In `sEYEght/Managers/Narrator.swift`, add:

```swift
/// Re-select the best available voice (call after user downloads an enhanced voice)
func refreshVoice() {
    let newVoice = Self.pickBestVoice()
    // Use reflection to update private property — or make selectedVoice a var
    // Simplest: make selectedVoice a private(set) var instead of let
}
```

Actually, change `selectedVoice` from `let` to `var`:
```swift
private var selectedVoice: AVSpeechSynthesisVoice?
```

And add the refresh:
```swift
func refreshVoice() {
    selectedVoice = Self.pickBestVoice()
    if let voice = selectedVoice {
        print("[Narrator] 🔄 Voice refreshed: \(voice.name) quality=\(voice.quality.rawValue)")
    }
}
```

Then in the setup phase, call `Narrator.shared.refreshVoice()` after detecting the enhanced voice.

- [ ] **Step 4: Build and verify**

Run build command. Expected: BUILD SUCCEEDED.

---

### Task 3: Immediate Startup Chime

**Files:**
- Modify: `sEYEght/sEYEghtApp.swift`

When a blind user opens the app, there's a delay before "Seyeght ready" plays. During that gap, they don't know if the app actually launched. Play an immediate audio chime so they know the app is alive.

- [ ] **Step 1: Add startup chime to app entry**

In `sEYEght/sEYEghtApp.swift`, in the `.onAppear` block, immediately play a short haptic + spoken chime BEFORE any hardware initialization:

```swift
.onAppear {
    // Immediate feedback so blind users know the app opened
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)

    // Configure audio session
    try? AVAudioSession.sharedInstance().setCategory(
        .playAndRecord, mode: .default,
        options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
    )
    try? AVAudioSession.sharedInstance().setActive(true)
}
```

Also in the setup flow (`ConversationalSetupView`), the welcome phase already speaks immediately, so that's covered. But for returning users going straight to Dashboard, the haptic pulse at launch + the "Seyeght ready" speech (already 1.5s delay) is fine — just add the haptic.

- [ ] **Step 2: Add startup haptic to DashboardView**

In `sEYEght/Views/DashboardView.swift`, add an immediate haptic at the top of `.onAppear`:

```swift
.onAppear {
    // Immediate haptic so blind user knows the screen loaded
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)

    appState.hasCompletedOnboarding = true
    // ... rest of existing code
}
```

- [ ] **Step 3: Build and verify**

Run build command. Expected: BUILD SUCCEEDED.

---

### Task 4: Better Error Messages (Network vs API vs Key)

**Files:**
- Modify: `sEYEght/Managers/VisionManager.swift`

Currently all API failures say generic messages. A blind user needs specific feedback: "No internet" vs "API error" vs "Scene too dark."

- [ ] **Step 1: Differentiate error types in VisionManager**

In `sEYEght/Managers/VisionManager.swift`, replace the generic error handling in `sendToOpenAI`:

```swift
if let error = error {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            print("[VisionManager] ❌ No internet connection")
            self?.speakText("No internet connection. I need internet to describe your surroundings.")
        case NSURLErrorTimedOut:
            print("[VisionManager] ❌ Request timed out")
            self?.speakText("The request timed out. Try again.")
        default:
            print("[VisionManager] ❌ Network error: \(error.localizedDescription)")
            self?.speakText("Network error. Check your connection and try again.")
        }
    } else {
        print("[VisionManager] ❌ API error: \(error.localizedDescription)")
        self?.speakText("Sorry, I couldn't analyze the scene right now.")
    }
    return
}
```

Also check HTTP status codes for API-specific errors:
```swift
if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
    print("[VisionManager] ❌ HTTP \(httpResponse.statusCode)")
    switch httpResponse.statusCode {
    case 401:
        self?.speakText("My vision system needs reconfiguration. Please contact support.")
    case 429:
        self?.speakText("I'm getting too many requests right now. Please wait a moment and try again.")
    case 500...599:
        self?.speakText("The vision service is temporarily down. Try again in a moment.")
    default:
        self?.speakText("Sorry, something went wrong analyzing the scene.")
    }
    return
}
```

- [ ] **Step 2: Build and verify**

Run build command. Expected: BUILD SUCCEEDED.

---

### Task 5: Emergency Mode Persistence + Verbal Dismissal

**Files:**
- Modify: `sEYEght/Views/DashboardView.swift`

Currently emergency mode auto-expires after 8 seconds silently. A person in distress should have the mode persist until they dismiss it. At minimum, warn before ending.

- [ ] **Step 1: Change emergency mode to persist + verbal end**

In `sEYEght/Views/DashboardView.swift`, replace the `handleEmergencyTripleTap()` method:

```swift
private func handleEmergencyTripleTap() {
    if isEmergencyActive {
        // Triple-tap again to EXIT emergency mode
        isEmergencyActive = false
        speak("Emergency mode ended. Resuming normal navigation.", priority: true)
        print("[DashboardView] 🚨 Emergency mode deactivated by user")
        return
    }

    isEmergencyActive = true

    // Strong haptic burst
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.warning)

    // Stop ALL current speech and announce emergency mode
    speak("Emergency mode activated. Your location is being announced. Triple-tap again to exit.", priority: true)

    // Speak current location after the emergency message
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
        guard self.isEmergencyActive else { return }
        navigationManager.speakCurrentLocation()
    }

    // Repeat location every 30 seconds while emergency mode is active
    DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
        guard self.isEmergencyActive else { return }
        navigationManager.speakCurrentLocation()
    }

    print("[DashboardView] 🚨 Emergency triple-tap activated — persists until dismissed")
}
```

Remove the old 8-second auto-expire `DispatchQueue.main.asyncAfter`.

- [ ] **Step 2: Build and verify**

Run build command. Expected: BUILD SUCCEEDED.

---

### Task 6: Build, Install, Test on Device

**Files:** None (verification only)

- [ ] **Step 1: Clean build for device**

```bash
cd /Users/Kinshuk/Developer/Seyeght/sEYEght
xcodebuild -scheme sEYEght -destination 'platform=iOS,id=00008120-00086D562650C01E' -derivedDataPath /tmp/sEYEght-build build 2>&1 | grep -E "error:|BUILD" | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Install on device**

```bash
xcrun devicectl device install app --device 00008120-00086D562650C01E /tmp/sEYEght-build/Build/Products/Debug-iphoneos/sEYEght.app 2>&1 | tail -5
```
Expected: Successful install with databaseSequenceNumber.

---
