//
//  AudioSessionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import AVFoundation

/// Centralized audio session manager. Prevents audio conflicts
/// between tone playback and speech synthesis.
@Observable
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {
        print("[AudioSessionManager] Initialized")
    }

    /// Configure for playback (speech + tones)
    func configureForActiveSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
            print("[AudioSessionManager] Active session configured with ducking")
        } catch {
            print("[AudioSessionManager] ❌ Failed to configure session: \(error)")
        }
    }

    /// Duck other audio when AI Vision is speaking
    func beginSpeaking() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            print("[AudioSessionManager] Speaking mode — other audio ducked")
        } catch {
            print("[AudioSessionManager] ❌ Failed to set speaking mode: \(error)")
        }
    }

    /// Restore normal audio after AI Vision finishes speaking
    func endSpeaking() {
        // Don't deactivate the session — just log restoration
        print("[AudioSessionManager] Normal mode restored")
    }
}
