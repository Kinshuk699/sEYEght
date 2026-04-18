//
//  NavigationSearchView.swift
//  sEYEght
//
//  Created by Kinshuk on 4/18/26.
//

import SwiftUI
import MapKit
import Speech

/// Navigation search screen: text field + mic button to find a destination.
/// Single tap reads a result aloud; double-tap confirms and starts routing.
struct NavigationSearchView: View {
    @Environment(NavigationManager.self) private var navigationManager
    @Environment(SpeechManager.self) private var speechManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var isListening = false
    @State private var selectedIndex: Int? = nil
    @State private var hasStartedRoute = false

    // Speech recognition for mic button
    @State private var speechRecognizer = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var micAudioEngine = AVAudioEngine()

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

                // Search bar + mic button
                HStack(spacing: 12) {
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
                            .accessibilityHint("Type a place name and press search")

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

                    // Mic button
                    Button {
                        if isListening {
                            stopMicListening()
                        } else {
                            startMicListening()
                        }
                    } label: {
                        Image(systemName: isListening ? "mic.fill" : "mic")
                            .font(.system(size: 20))
                            .foregroundColor(isListening ? .red : SeyeghtTheme.accent)
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(isListening ? "Stop listening" : "Speak destination")
                    .accessibilityHint(isListening ? "Double tap to stop" : "Double tap to speak a destination")
                }

                // Status text
                if isListening {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Listening...")
                            .font(SeyeghtTheme.caption)
                            .foregroundColor(SeyeghtTheme.secondaryText)
                    }
                    .accessibilityLabel("Listening for destination")
                } else if isSearching {
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
                } else if !searchText.isEmpty && !isSearching && !isListening {
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
                    stopMicListening()
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
            // Stop SpeechManager to release the mic for NavigationSearchView's local engine
            speechManager.stopListening()

            // Auto-focus the text field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
            Narrator.shared.speak("Search for a destination. Type or tap the microphone to speak.", rate: 0.45, volume: 0.85)
        }
        .onDisappear {
            stopMicListening()
            // Restart SpeechManager so wake-word detection resumes on Dashboard
            speechManager.startListening()
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

    // MARK: - Mic Listening

    private func startMicListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            Narrator.shared.speak("Speech recognition is not available.", rate: 0.45, volume: 0.85)
            return
        }

        isListening = true
        isTextFieldFocused = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = micAudioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            isListening = false
            Narrator.shared.speak("Microphone not available.", rate: 0.45, volume: 0.85)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest?.append(buffer)
        }

        do {
            try micAudioEngine.start()
        } catch {
            isListening = false
            return
        }

        // Auto-stop after 5 seconds of listening
        let autoStopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, isListening else { return }
            stopMicListening()
            if !searchText.isEmpty {
                performSearch()
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [self] result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    searchText = text
                }

                // If final result, stop and search
                if result.isFinal {
                    autoStopTask.cancel()
                    Task { @MainActor in
                        stopMicListening()
                        performSearch()
                    }
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Ignore "no speech" timeout
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                    autoStopTask.cancel()
                    Task { @MainActor in
                        stopMicListening()
                        if !searchText.isEmpty {
                            performSearch()
                        }
                    }
                }
            }
        }

        Narrator.shared.stop()
        // Small haptic to confirm mic is on
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func stopMicListening() {
        guard isListening else { return }
        isListening = false

        micAudioEngine.stop()
        micAudioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
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
