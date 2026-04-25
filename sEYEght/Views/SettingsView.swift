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
    @Environment(AppState.self) private var appState
    @Query private var settingsArray: [UserSettings]
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
            VStack(alignment: .leading, spacing: 28) {

                // ─── Hero header ──────────────────────────────────────────
                // Big left-aligned title (Apple Settings / Mail style) so
                // sighted + low-vision users can read it without squinting.
                HStack(alignment: .firstTextBaseline) {
                    Text("Settings")
                        .font(SeyeghtTheme.largeTitle)
                        .foregroundColor(SeyeghtTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.top, 8)

                // ─── Feedback ─────────────────────────────────────────────
                SettingsSection(title: "FEEDBACK", icon: "waveform") {
                    SettingsToggleRow(
                        icon: "speaker.wave.2.fill",
                        label: "Voice Narration",
                        description: "AI descriptions and spoken alerts",
                        isOn: Binding(
                            get: { settings.voiceEnabled },
                            set: { newValue in
                                if !newValue && !settings.beepsEnabled && !settings.hapticsEnabled {
                                    Narrator.shared.speak("At least one feedback type must stay on for your safety")
                                    return
                                }
                                settings.voiceEnabled = newValue
                                speakSettingChange(newValue ? "Voice on" : "Voice off")
                                try? modelContext.save()
                            }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        icon: "dot.radiowaves.left.and.right",
                        label: "Proximity Beeps",
                        description: "Audio tones for obstacles",
                        isOn: Binding(
                            get: { settings.beepsEnabled },
                            set: { newValue in
                                if !newValue && !settings.voiceEnabled && !settings.hapticsEnabled {
                                    Narrator.shared.speak("At least one feedback type must stay on for your safety")
                                    return
                                }
                                settings.beepsEnabled = newValue
                                hapticsManager.audioToneEnabled = newValue
                                if newValue {
                                    hapticsManager.startAudioToneIfNeeded()
                                } else {
                                    hapticsManager.stopAudioTone()
                                }
                                speakSettingChange(newValue ? "Beeps on" : "Beeps off")
                                try? modelContext.save()
                            }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        icon: "iphone.radiowaves.left.and.right",
                        label: "Haptic Vibrations",
                        description: "Vibration feedback",
                        isOn: Binding(
                            get: { settings.hapticsEnabled },
                            set: { newValue in
                                if !newValue && !settings.voiceEnabled && !settings.beepsEnabled {
                                    Narrator.shared.speak("At least one feedback type must stay on for your safety")
                                    return
                                }
                                settings.hapticsEnabled = newValue
                                hapticsManager.hapticsEnabled = newValue
                                speakSettingChange(newValue ? "Haptics on" : "Haptics off")
                                try? modelContext.save()
                            }
                        )
                    )
                }

                // ─── Obstacle Detection ───────────────────────────────────
                SettingsSection(title: "OBSTACLE DETECTION", icon: "sensor.tag.radiowaves.forward.fill") {
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
                    SettingsDivider()
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
                    SettingsDivider()
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
                }

                // ─── Voice & Speech ───────────────────────────────────────
                SettingsSection(title: "VOICE", icon: "person.wave.2.fill") {
                    GoldSlider(
                        label: "Speech Speed",
                        value: Binding(
                            get: { settings.speechRate },
                            set: { settings.speechRate = $0 }
                        ),
                        range: 0.3...0.7,
                        lowLabel: "Slow",
                        highLabel: "Fast",
                        displayValue: String(format: "%.1fx", settings.speechRate * 2)
                    )
                }

                // ─── About + Setup ────────────────────────────────────────
                SettingsSection(title: "ABOUT", icon: "info.circle.fill") {
                    HStack {
                        Image(systemName: "app.badge.fill")
                            .font(.system(size: 18))
                            .foregroundColor(SeyeghtTheme.accent)
                            .frame(width: 28)
                        Text("Version")
                            .font(SeyeghtTheme.body)
                            .foregroundColor(SeyeghtTheme.primaryText)
                        Spacer()
                        Text("1.0")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Version 1.0")

                    SettingsDivider()

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        UserDefaults.standard.set(false, forKey: "setupComplete")
                        appState.hasCompletedOnboarding = false
                        appState.hasAnnouncedWelcomeThisSession = false
                        navigateToSetup = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(SeyeghtTheme.accent)
                                .frame(width: 28)
                            Text("Redo Setup Tutorial")
                                .font(SeyeghtTheme.body)
                                .foregroundColor(SeyeghtTheme.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SeyeghtTheme.secondaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Redo setup tutorial")
                    .accessibilityHint("Double tap to start the conversational setup again")
                }
            }
            .padding(.horizontal, SeyeghtTheme.horizontalPadding)
            .padding(.bottom, 32)
        }
        .background(SeyeghtTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 36, height: 36)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                }
                .accessibilityLabel("Go back to dashboard")
            }
        }
        .toolbarBackground(SeyeghtTheme.background, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToSetup) {
            ConversationalSetupView()
        }
        .onChange(of: settings.hapticIntensityLevel) { _, newVal in
            hapticsManager.userIntensityLevel = newVal
            speakSettingChange("Haptic intensity \(Int(newVal * 100)) percent")
            try? modelContext.save()
        }
        .onChange(of: settings.radarRangeMeters) { _, newVal in
            hapticsManager.maxRange = newVal
            speakSettingChange(String(format: "Radar range %.1f meters", newVal))
            try? modelContext.save()
        }
        .onChange(of: settings.speechRate) { _, newVal in
            speakSettingChange(String(format: "Speech speed %.1f x", newVal * 2))
            try? modelContext.save()
        }
        .onChange(of: settings.beepVolume) { _, newVal in
            hapticsManager.audioToneVolume = Float(newVal)
            speakSettingChange("Beep volume \(Int(newVal * 200)) percent")
            try? modelContext.save()
        }
        .onAppear {
            // Sync stored settings to live manager values
            hapticsManager.userIntensityLevel = settings.hapticIntensityLevel
            hapticsManager.maxRange = settings.radarRangeMeters
            hapticsManager.audioToneVolume = Float(settings.beepVolume)
            hapticsManager.audioToneEnabled = settings.beepsEnabled
            hapticsManager.hapticsEnabled = settings.hapticsEnabled
        }
        .onDisappear {
            // Prevent any pending debounced setting-change speech from
            // firing after the user has navigated away from this screen.
            speechWorkItem?.cancel()
            speechWorkItem = nil
        }
    }

    /// Debounced speech for slider changes — waits 0.6s after last change to speak.
    /// Uses a cancellable Task so the speech is cancelled if the view is dismissed,
    /// preventing setting announcements from leaking onto the next screen.
    private func speakSettingChange(_ text: String) {
        speechWorkItem?.cancel()
        let item = DispatchWorkItem {
            Narrator.shared.speak(text, rate: 0.5, volume: 0.7)
        }
        speechWorkItem = item
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !item.isCancelled else { return }
            item.perform()
        }
    }
}

/// Sectioned card container — header with icon + grouped rows on a card.
/// One card per group reads as a single VoiceOver region and gives the
/// screen real visual rhythm instead of the previous floating-toggle look.
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(SeyeghtTheme.accent)
                Text(title)
                    .font(SeyeghtTheme.sectionHeader)
                    .tracking(1.2)
                    .foregroundColor(SeyeghtTheme.accent)
            }
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(title.capitalized)

            VStack(spacing: 14) {
                content
            }
            .padding(16)
            .background(SeyeghtTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: SeyeghtTheme.cardCornerRadius)
                    .strokeBorder(SeyeghtTheme.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: SeyeghtTheme.cardCornerRadius))
        }
    }
}

/// Hairline separator between rows inside a SettingsSection card.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Icon + label + description + toggle row for the new card layout.
struct SettingsToggleRow: View {
    let icon: String
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(SeyeghtTheme.accentSoft)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SeyeghtTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SeyeghtTheme.bodyBold)
                    .foregroundColor(SeyeghtTheme.primaryText)
                Text(description)
                    .font(SeyeghtTheme.caption)
                    .foregroundColor(SeyeghtTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: SeyeghtTheme.accent))
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(isOn ? "on" : "off")")
        .accessibilityHint("Double tap to toggle")
    }
}

// MARK: - Legacy (kept for source compatibility, no longer used in body)

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

/// Toggle switch for feedback modes
struct FeedbackToggle: View {
    let label: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(SeyeghtTheme.bodyBold)
                    .foregroundColor(SeyeghtTheme.primaryText)
                Text(description)
                    .font(SeyeghtTheme.caption)
                    .foregroundColor(SeyeghtTheme.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: SeyeghtTheme.accent))
                .labelsHidden()
        }
        .padding(16)
        .background(SeyeghtTheme.cardBackground)
        .cornerRadius(SeyeghtTheme.cardCornerRadius)
        .accessibilityLabel("\(label), \(isOn ? "on" : "off")")
        .accessibilityHint("Double tap to toggle")
    }
}
