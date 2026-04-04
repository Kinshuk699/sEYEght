//
//  AudioSessionManager.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import AVFoundation

/// Centralized audio session manager. Prevents MapKit audio, LLM speech,
/// and wake word listening from stepping on each other.
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {
        print("[AudioSessionManager] Initialized")
    }

    /// Configure for simultaneous playback + recording
    func configureForActiveSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            print("[AudioSessionManager] Active session configured with ducking")
        } catch {
            print("[AudioSessionManager] ❌ Failed to configure session: \(error)")
        }
    }

    /// Duck other audio when AI Vision is speaking
    func beginSpeaking() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            print("[AudioSessionManager] Speaking mode — other audio ducked")
        } catch {
            print("[AudioSessionManager] ❌ Failed to set speaking mode: \(error)")
        }
    }

    /// Restore normal audio after AI Vision finishes speaking
    func endSpeaking() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true, options: [])
            print("[AudioSessionManager] Normal mode restored")
        } catch {
            print("[AudioSessionManager] ❌ Failed to restore normal mode: \(error)")
        }
    }
}
