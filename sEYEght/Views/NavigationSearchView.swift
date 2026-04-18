//
//  NavigationSearchView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/18/26.
//

import SwiftUI
import MapKit

/// Navigation search screen: text field to find a destination.
/// Blind users use iOS built-in voice dictation keyboard to type by voice.
/// Single tap reads a result aloud; double-tap confirms and starts routing.
struct NavigationSearchView: View {
    @Environment(NavigationManager.self) private var navigationManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var selectedIndex: Int? = nil
    @State private var hasStartedRoute = false

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            SeyeghtTheme.background.ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                Text("Navigate")
                    .font(SeyeghtTheme.title)
                    .foregroundColor(SeyeghtTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .accessibilityAddTraits(.isHeader)

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(SeyeghtTheme.secondaryText)
                        .accessibilityHidden(true)

                    TextField("Search destination", text: $searchText)
                        .font(SeyeghtTheme.body)
                        .foregroundColor(SeyeghtTheme.primaryText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .focused($isTextFieldFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                        .accessibilityLabel("Search destination")
                        .accessibilityHint("Type a place name and press search. Use dictation on the keyboard to speak.")

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(SeyeghtTheme.secondaryText)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                // Status text
                if isSearching {
                    Text("Searching...")
                        .font(SeyeghtTheme.caption)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                }

                // Results list
                if !searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(searchResults.enumerated()), id: \.offset) { index, item in
                                SearchResultRow(
                                    item: item,
                                    index: index,
                                    isSelected: selectedIndex == index,
                                    userLocation: navigationManager.userLocation
                                )
                                .onTapGesture(count: 2) {
                                    confirmSelection(at: index)
                                }
                                .onTapGesture(count: 1) {
                                    selectResult(at: index)
                                }
                            }
                        }
                    }
                } else if !searchText.isEmpty && !isSearching {
                    Text("No results found")
                        .font(SeyeghtTheme.body)
                        .foregroundColor(SeyeghtTheme.secondaryText)
                        .padding(.top, 40)
                }

                Spacer()
            }
            .padding(.horizontal, SeyeghtTheme.horizontalPadding)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(SeyeghtTheme.accent)
                }
                .accessibilityLabel("Cancel search")
                .accessibilityHint("Double tap to go back to camera")
            }
        }
        .onAppear {
            // Focus text field immediately so keyboard appears right away
            isTextFieldFocused = true
            // Speak instruction after a short delay so it doesn't block keyboard input
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                Narrator.shared.speak("Type a destination or use dictation.", rate: 0.5, volume: 0.85)
            }
        }
    }

    // MARK: - Search

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // Stop any ongoing narration (e.g. the intro instructions)
        Narrator.shared.stop()

        isSearching = true
        isTextFieldFocused = false
        searchResults = []

        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            if let location = navigationManager.userLocation {
                request.region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 5000,
                    longitudinalMeters: 5000
                )
            }

            do {
                let search = MKLocalSearch(request: request)
                let response = try await search.start()
                let items = Array(response.mapItems.prefix(5))

                await MainActor.run {
                    searchResults = items
                    isSearching = false

                    if items.isEmpty {
                        Narrator.shared.speak("No results found. Try a different name.", rate: 0.45, volume: 0.85)
                    } else {
                        let count = items.count
                        let firstName = items[0].name ?? "Unknown"
                        Narrator.shared.speak("\(count) results. First is \(firstName). Tap to hear, double tap to go.", rate: 0.45, volume: 0.85)
                    }
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    Narrator.shared.speak("Search failed. Please try again.", rate: 0.45, volume: 0.85)
                }
            }
        }
    }

    // MARK: - Selection

    private func selectResult(at index: Int) {
        selectedIndex = index
        let item = searchResults[index]
        let name = item.name ?? "Unknown"
        let distance = formatDistance(to: item)
        let street = item.placemark.thoroughfare ?? ""
        let streetPart = street.isEmpty ? "" : ", on \(street)"

        // Light haptic on selection
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        Narrator.shared.stop()
        Narrator.shared.speak("\(name)\(streetPart), \(distance) away. Double tap to start navigation.", rate: 0.45, volume: 0.85)
    }

    private func confirmSelection(at index: Int) {
        guard index < searchResults.count else { return }
        hasStartedRoute = true

        // Stop any ongoing narration ("double tap to start navigation" etc.)
        Narrator.shared.stop()

        // Strong haptic confirms
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        let item = searchResults[index]
        Task {
            await navigationManager.selectSearchResultDirect(item)
            await MainActor.run {
                dismiss()
            }
        }
    }

    // MARK: - Helpers

    private func formatDistance(to item: MKMapItem) -> String {
        guard let userLoc = navigationManager.userLocation else { return "" }
        let itemLoc = CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        let meters = userLoc.distance(from: itemLoc)
        if meters < 200 {
            let feet = Int(meters * 3.281)
            return "\(feet) feet"
        } else if meters < 1000 {
            return String(format: "%.0f meters", meters)
        } else {
            let km = meters / 1000
            return String(format: "%.1f km", km)
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let item: MKMapItem
    let index: Int
    let isSelected: Bool
    let userLocation: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(SeyeghtTheme.background)
                .frame(width: 28, height: 28)
                .background(isSelected ? SeyeghtTheme.accent : SeyeghtTheme.secondaryText)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name ?? "Unknown")
                    .font(SeyeghtTheme.body)
                    .foregroundColor(SeyeghtTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let street = item.placemark.thoroughfare, !street.isEmpty {
                        Text(street)
                            .font(SeyeghtTheme.caption)
                            .foregroundColor(SeyeghtTheme.secondaryText)
                            .lineLimit(1)
                    }

                    if let userLoc = userLocation {
                        let itemLoc = CLLocation(
                            latitude: item.placemark.coordinate.latitude,
                            longitude: item.placemark.coordinate.longitude
                        )
                        let meters = userLoc.distance(from: itemLoc)
                        Text(formatDist(meters))
                            .font(SeyeghtTheme.caption)
                            .foregroundColor(SeyeghtTheme.accent)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(SeyeghtTheme.secondaryText)
                .font(.system(size: 12))
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(isSelected ? SeyeghtTheme.accent.opacity(0.15) : Color.white.opacity(0.05))
        .cornerRadius(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double tap to start navigation")
    }

    private var accessibilityText: String {
        let name = item.name ?? "Unknown"
        let street = item.placemark.thoroughfare ?? ""
        let streetPart = street.isEmpty ? "" : " on \(street)"
        var distPart = ""
        if let userLoc = userLocation {
            let itemLoc = CLLocation(
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude
            )
            distPart = ", \(formatDist(userLoc.distance(from: itemLoc))) away"
        }
        return "\(name)\(streetPart)\(distPart)"
    }

    private func formatDist(_ meters: Double) -> String {
        if meters < 200 {
            return "\(Int(meters * 3.281)) feet"
        } else if meters < 1000 {
            return String(format: "%.0f meters", meters)
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
}
