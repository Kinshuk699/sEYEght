//
//  SettingsView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI
import SwiftData

/// S-004: Settings screen with sliders and subscription access.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HapticsManager.self) private var hapticsManager
    @Query private var settingsArray: [UserSettings]
    @State private var navigateToSubscription = false
    @State private var navigateToSetup = false
    @State private var speechWorkItem: DispatchWorkItem?

    private var settings: UserSettings {
        if let existing = settingsArray.first {
            return existing
        }
        let new = UserSettings()
        modelContext.insert(new)
        return new
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Obstacle Detection
                SectionHeader(title: "OBSTACLE DETECTION")

                GoldSlider(
                    label: "Haptic Intensity",
                    value: Binding(
                        get: { settings.hapticIntensityLevel },
                        set: { settings.hapticIntensityLevel = $0 }
                    ),
                    range: 0...1,
                    lowLabel: "Low",
                    highLabel: "High"
                )

                GoldSlider(
                    label: "Radar Range",
                    value: Binding(
                        get: { settings.radarRangeMeters },
                        set: { settings.radarRangeMeters = $0 }
                    ),
                    range: 1...3,
                    lowLabel: "1m",
                    highLabel: "3m",
                    displayValue: String(format: "%.1fm", settings.radarRangeMeters)
                )

                GoldSlider(
                    label: "Beep Volume",
                    value: Binding(
                        get: { settings.beepVolume },
                        set: { settings.beepVolume = $0 }
                    ),
                    range: 0...0.5,
                    lowLabel: "Off",
                    highLabel: "Loud",
                    displayValue: String(format: "%.0f%%", settings.beepVolume * 200)
                )

                // MARK: - Voice & Speech
                SectionHeader(title: "VOICE & SPEECH")

                GoldSlider(
                    label: "AI Speech Speed",
                    value: Binding(
                        get: { settings.speechRate },
                        set: { settings.speechRate = $0 }
                    ),
                    range: 0.3...0.7,
                    lowLabel: "Slow",
                    highLabel: "Fast",
                    displayValue: String(format: "%.1fx", settings.speechRate * 2)
                )

                // Wake Phrase (read-only)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wake Phrase")
                            .font(SeyeghtTheme.bodyBold)
                            .foregroundColor(SeyeghtTheme.primaryText)
                    }
                    Spacer()
                    Text("Hey Sight")
                        .font(SeyeghtTheme.body)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                }
                .padding(20)
                .background(SeyeghtTheme.cardBackground)
                .cornerRadius(SeyeghtTheme.cardCornerRadius)
                .accessibilityLabel("Wake phrase: Hey Sight. Read only.")

                // MARK: - AI Vision
                SectionHeader(title: "AI VISION")

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    print("[SettingsView] Manage Subscription tapped")
                    navigateToSubscription = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Manage Subscription")
                                .font(SeyeghtTheme.bodyBold)
                                .foregroundColor(SeyeghtTheme.primaryText)
                            Text("Unlock scene descriptions")
                                .font(SeyeghtTheme.caption)
                                .foregroundColor(SeyeghtTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SeyeghtTheme.accent)
                            .accessibilityHidden(true)
                    }
                    .padding(20)
                    .background(SeyeghtTheme.cardBackground)
                    .cornerRadius(SeyeghtTheme.cardCornerRadius)
                }
                .accessibilityLabel("Manage Subscription")
                .accessibilityHint("Double tap to manage AI Vision subscription")

                // MARK: - About
                SectionHeader(title: "ABOUT")

                HStack {
                    Text("Version 1.0")
                        .font(SeyeghtTheme.body)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                    Spacer()
                }
                .padding(20)
                .background(SeyeghtTheme.cardBackground)
                .cornerRadius(SeyeghtTheme.cardCornerRadius)
                .accessibilityLabel("Version 1.0")

                // MARK: - Setup
                SectionHeader(title: "SETUP")

                HapticButton("Redo Setup Tutorial") {
                    UserDefaults.standard.set(false, forKey: "setupComplete")
                    navigateToSetup = true
                }
            }
            .padding(.horizontal, SeyeghtTheme.horizontalPadding)
            .padding(.top, 8)
        }
        .background(SeyeghtTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(SeyeghtTheme.title)
                    .foregroundColor(SeyeghtTheme.primaryText)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(SeyeghtTheme.accent)
                }
                .accessibilityLabel("Go back to dashboard")
            }
        }
        .toolbarBackground(SeyeghtTheme.background, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToSubscription) {
            SubscriptionView()
        }
        .navigationDestination(isPresented: $navigateToSetup) {
            ConversationalSetupView()
        }
        .onChange(of: settings.hapticIntensityLevel) { _, newVal in
            hapticsManager.userIntensityLevel = newVal
            speakSettingChange("Haptic intensity \(Int(newVal * 100)) percent")
        }
        .onChange(of: settings.radarRangeMeters) { _, newVal in
            hapticsManager.maxRange = newVal
            speakSettingChange(String(format: "Radar range %.1f meters", newVal))
        }
        .onChange(of: settings.speechRate) { _, newVal in
            speakSettingChange(String(format: "Speech speed %.1f x", newVal * 2))
        }
        .onChange(of: settings.beepVolume) { _, newVal in
            hapticsManager.audioToneVolume = Float(newVal)
            speakSettingChange("Beep volume \(Int(newVal * 200)) percent")
        }
        .onAppear {
            // Sync stored settings to live manager values
            hapticsManager.userIntensityLevel = settings.hapticIntensityLevel
            hapticsManager.maxRange = settings.radarRangeMeters
            hapticsManager.audioToneVolume = Float(settings.beepVolume)
        }
    }

    /// Debounced speech for slider changes — waits 0.6s after last change to speak
    private func speakSettingChange(_ text: String) {
        speechWorkItem?.cancel()
        let item = DispatchWorkItem {
            Narrator.shared.speak(text, rate: 0.5, volume: 0.7)
        }
        speechWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }
}

/// Gold section header label
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(SeyeghtTheme.sectionHeader)
            .foregroundColor(SeyeghtTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
