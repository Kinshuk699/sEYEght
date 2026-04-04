//
//  SubscriptionView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/3/26.
//

import SwiftUI

/// S-005: AI Vision subscription/paywall screen.
struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: SubscriptionPlan = .annual

    enum SubscriptionPlan {
        case monthly, annual
    }

    private let features: [String] = [
        "Instant scene descriptions in under 10 seconds",
        "Identifies obstacles, signs, and layouts",
        "100% hands-free, triggered by voice"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 48))
                    .foregroundColor(SeyeghtTheme.accent)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                Text("AI Vision")
                    .font(SeyeghtTheme.largeTitle)
                    .foregroundColor(SeyeghtTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Say 'Hey Seyeght' and get an instant spoken description of your surroundings, powered by AI.")
                    .font(SeyeghtTheme.body)
                    .foregroundColor(SeyeghtTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                // Feature bullets
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(SeyeghtTheme.accent)
                                .accessibilityHidden(true)
                            Text(feature)
                                .font(SeyeghtTheme.body)
                                .foregroundColor(SeyeghtTheme.primaryText)
                        }
                        .accessibilityLabel(feature)
                    }
                }
                .padding(.horizontal, 8)

                // Pricing options
                VStack(spacing: 12) {
                    PricingOption(
                        title: "Monthly",
                        price: "$4.99/month",
                        isSelected: selectedPlan == .monthly
                    ) {
                        selectedPlan = .monthly
                        print("[SubscriptionView] Selected monthly plan")
                    }

                    PricingOption(
                        title: "Annual",
                        price: "$39.99/year",
                        badge: "Save 33%",
                        isSelected: selectedPlan == .annual
                    ) {
                        selectedPlan = .annual
                        print("[SubscriptionView] Selected annual plan")
                    }
                }

                HapticButton("Subscribe Now") {
                    print("[SubscriptionView] Subscribe tapped — plan: \(selectedPlan)")
                    // TODO: Wire to SubscriptionManager.purchase() in Phase 5
                }

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    print("[SubscriptionView] Restore Purchase tapped")
                    // TODO: Wire to SubscriptionManager.restore() in Phase 5
                } label: {
                    Text("Restore Purchase")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                }
                .accessibilityLabel("Restore Purchase")
                .accessibilityHint("Double tap to restore a previous purchase")
                .padding(.bottom, 24)
            }
            .padding(.horizontal, SeyeghtTheme.horizontalPadding)
        }
        .background(SeyeghtTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .foregroundColor(SeyeghtTheme.accent)
                }
                .accessibilityLabel("Go back to settings")
            }
            ToolbarItem(placement: .principal) {
                Text("Seyeght")
                    .font(SeyeghtTheme.bodyBold)
                    .foregroundColor(SeyeghtTheme.primaryText)
            }
        }
        .toolbarBackground(SeyeghtTheme.background, for: .navigationBar)
    }
}

/// A selectable pricing option card.
struct PricingOption: View {
    let title: String
    let price: String
    var badge: String? = nil
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(title) —")
                        .font(SeyeghtTheme.bodyBold)
                        .foregroundColor(SeyeghtTheme.primaryText)
                    Text(price)
                        .font(SeyeghtTheme.body)
                        .foregroundColor(SeyeghtTheme.primaryText)
                }
                Spacer()
                if let badge = badge {
                    Text(badge)
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(SeyeghtTheme.accent)
                        .italic()
                }
            }
            .padding(20)
            .background(SeyeghtTheme.cardBackground)
            .cornerRadius(SeyeghtTheme.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: SeyeghtTheme.cardCornerRadius)
                    .stroke(isSelected ? SeyeghtTheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .accessibilityLabel("\(title), \(price)\(badge != nil ? ", \(badge!)" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select this plan")
    }
}
