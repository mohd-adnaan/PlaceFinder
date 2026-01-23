//
//  NavigationInputSection.swift
//  IndoorNavigationTACME
//
//  Navigation input fields with POI autocomplete
//

import SwiftUI

struct NavigationInputSection: View {
    @Binding var source: String
    @Binding var destination: String
    @Binding var useClockDirections: Bool
    @Binding var useLandmarks: Bool
    
    let ttsEnabled: Bool
    let poiNames: [String]
    let onTtsEnabledChange: (Bool) -> Void
    
    @State private var showSourceSuggestions = false
    @State private var showDestinationSuggestions = false
    @FocusState private var sourceFieldFocused: Bool
    @FocusState private var destinationFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Source input
            VStack(alignment: .leading, spacing: 8) {
                Label("Source", systemImage: "mappin.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                POITextField(
                    text: $source,
                    placeholder: "Enter source location",
                    suggestions: filteredSuggestions(for: source),
                    showSuggestions: $showSourceSuggestions,
                    isFocused: _sourceFieldFocused,
                    onSelect: { selected in
                        source = selected
                        showSourceSuggestions = false
                    }
                )
            }
            
            // Destination input
            VStack(alignment: .leading, spacing: 8) {
                Label("Destination", systemImage: "flag.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                POITextField(
                    text: $destination,
                    placeholder: "Enter destination location",
                    suggestions: filteredSuggestions(for: destination),
                    showSuggestions: $showDestinationSuggestions,
                    isFocused: _destinationFieldFocused,
                    onSelect: { selected in
                        destination = selected
                        showDestinationSuggestions = false
                    }
                )
            }
            
            // Options toggles
            VStack(spacing: 12) {
                // Clock directions toggle
                HStack {
                    Toggle(isOn: $useClockDirections) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            Text("Use Clock Directions")
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                }
                
                // Landmarks toggle
                HStack {
                    Toggle(isOn: $useLandmarks) {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.purple)
                            Text("Use Landmarks")
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                }
                
                // TTS toggle
                HStack {
                    Toggle(isOn: Binding(
                        get: { ttsEnabled },
                        set: { onTtsEnabledChange($0) }
                    )) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                            Text("Voice Guidance")
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func filteredSuggestions(for input: String) -> [String] {
        guard !input.isEmpty else { return poiNames }
        
        let lowercasedInput = input.lowercased()
        return poiNames.filter { poi in
            poi.lowercased().contains(lowercasedInput)
        }.prefix(5).map { $0 }
    }
}

// MARK: - POI TextField with Autocomplete

struct POITextField: View {
    @Binding var text: String
    let placeholder: String
    let suggestions: [String]
    @Binding var showSuggestions: Bool
    @FocusState var isFocused: Bool
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isFocused)
                .autocapitalization(.words)
                .disableAutocorrection(true)
                .onChange(of: text) { _ in
                    showSuggestions = isFocused && !text.isEmpty
                }
                .onChange(of: isFocused) { focused in
                    showSuggestions = focused && !text.isEmpty
                }
                .accessibilityHint("Type to search locations")
            
            // Suggestions dropdown
            if showSuggestions && !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: {
                                onSelect(suggestion)
                                isFocused = false
                            }) {
                                HStack {
                                    Image(systemName: "mappin")
                                        .foregroundColor(.blue)
                                    Text(suggestion)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .background(Color(.systemBackground))
                            
                            if suggestion != suggestions.last {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
        }
    }
}

// MARK: - Preview

struct NavigationInputSection_Previews: PreviewProvider {
    static var previews: some View {
        NavigationInputSection(
            source: .constant(""),
            destination: .constant(""),
            useClockDirections: .constant(false),
            useLandmarks: .constant(true),
            ttsEnabled: true,
            poiNames: ["Room 101", "Room 102", "Elevator", "Exit", "Bathroom", "Office A"],
            onTtsEnabledChange: { _ in }
        )
        .padding()
    }
}
