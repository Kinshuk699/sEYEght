//
//  DashboardChrome.swift
//  sEYEght
//
//  Step 4 polish — shared dashboard UI atoms.
//
//  Design rationale (per ui-ux-pro-max + Apple HIG + low-vision research):
//   • Pure black + bright amber accent for max contrast (~12.4:1 WCAG AAA).
//   • SF Rounded for warmth — reduces the "AI generated" feel.
//   • Touch targets ≥ 88×88pt for users who can only roughly aim.
//   • Icons paired with text labels (`nav-label-icon`).
//   • Soft pulse on active status — peripheral vision can confirm "it's on".
//   • These views are PURELY VISUAL. The dashboard wraps them with
//     `.navigable()` so VoiceOver-style speak-then-activate works for
//     everyone (single-tap → speak label, double-tap → activate).
//

import SwiftUI

// MARK: - StatusPill

struct StatusPill: View {
    let isActive: Bool
    let text: String

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? SeyeghtTheme.accent : SeyeghtTheme.danger)
                .frame(width: 10, height: 10)
                .opacity(isActive && pulse ? 0.45 : 1.0)
                .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                (isActive ? SeyeghtTheme.accent : SeyeghtTheme.danger).opacity(0.55),
                lineWidth: 1
            )
        )
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isActive ? "Sight is active" : "Camera off")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - BigIconButton (label-only — caller wraps with .navigable())

/// Visual atom for primary dashboard chrome buttons. NO action handler —
/// the parent attaches behavior via `.navigable()` so single-tap speaks
/// and double-tap activates (preventing accidental nav for blind users).
struct BigIconButton: View {
    let systemName: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().strokeBorder(SeyeghtTheme.accent.opacity(0.7), lineWidth: 1.5)
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: systemName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(SeyeghtTheme.accent)
            }
            Text(label)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
        }
        .frame(minWidth: 88, minHeight: 96)
        .contentShape(Rectangle())
    }
}
