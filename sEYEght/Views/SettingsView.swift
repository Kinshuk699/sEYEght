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
    @Query private var settingsArray: [UserSettings]
    @State private var navigateToSubscription = false

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
                    Text("Hey Seyeght")
                        .font(SeyeghtTheme.body)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                }
                .padding(20)
                .background(SeyeghtTheme.cardBackground)
                .cornerRadius(SeyeghtTheme.cardCornerRadius)
                .accessibilityLabel("Wake phrase: Hey Seyeght. Read only.")

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
            }
            .padding(.horizontal, SeyeghtTheme.horizontalPadding)
            .padding(.top, 8)
        }
        .background(SeyeghtTheme.background)
        .navigationBarTitleDisplayMode(.inline)
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
