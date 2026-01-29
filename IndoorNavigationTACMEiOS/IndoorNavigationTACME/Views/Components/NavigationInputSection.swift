//
//  NavigationInputSection.swift
//  IndoorNavigationTACME
//
//  Navigation input fields with PROPER dropdown menus
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
    
    var body: some View {
        VStack(spacing: 16) {
            // Source input with dropdown
            VStack(alignment: .leading, spacing: 8) {
                Label("Source", systemImage: "mappin.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                POIDropdownMenu(
                    selectedValue: $source,
                    placeholder: "Enter source location",
                    options: poiNames
                )
            }
            
            // Destination input with dropdown
            VStack(alignment: .leading, spacing: 8) {
                Label("Destination", systemImage: "flag.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                
                POIDropdownMenu(
                    selectedValue: $destination,
                    placeholder: "Enter destination location",
                    options: poiNames
                )
            }
            
            // Options toggles
            VStack(spacing: 12) {
                // Clock directions toggle
                Toggle(isOn: $useClockDirections) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("Use Clock Directions")
                            .font(.subheadline)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                
                // Landmarks toggle
                Toggle(isOn: $useLandmarks) {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(.purple)
                        Text("Use Landmarks")
                            .font(.subheadline)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .purple))
                
                // Voice guidance toggle
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
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - POI Dropdown Menu (Android-style dropdown)

struct POIDropdownMenu: View {
    @Binding var selectedValue: String
    let placeholder: String
    let options: [String]
    
    @State private var isExpanded = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    private var filteredOptions: [String] {
        if searchText.isEmpty {
            return options
        }
        return options.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main button/text field
            HStack {
                // Text field for typing/searching
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { newValue in
                        if !newValue.isEmpty {
                            isExpanded = true
                        }
                        // If exact match found, select it
                        if options.contains(where: { $0.lowercased() == newValue.lowercased() }) {
                            selectedValue = options.first(where: { $0.lowercased() == newValue.lowercased() }) ?? newValue
                        }
                    }
                    .onTapGesture {
                        isExpanded = true
                    }
                
                // Dropdown arrow button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isExpanded ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            // Dropdown list
            if isExpanded && !filteredOptions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredOptions, id: \.self) { option in
                            Button(action: {
                                selectedValue = option
                                searchText = option
                                isExpanded = false
                                isSearchFocused = false
                            }) {
                                HStack {
                                    Image(systemName: "mappin")
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    
                                    Text(option)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if option == selectedValue {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .background(option == selectedValue ? Color.blue.opacity(0.1) : Color.clear)
                            
                            if option != filteredOptions.last {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
            }
        }
        .onAppear {
            // Initialize search text with selected value
            if !selectedValue.isEmpty {
                searchText = selectedValue
            }
        }
        .onChange(of: selectedValue) { newValue in
            searchText = newValue
        }
    }
}

// MARK: - Legacy POI TextField (for backward compatibility)

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
            poiNames: ["Room 101", "Room 102", "Room 201", "Elevator A", "Elevator B", "Exit North", "Exit South", "Bathroom", "Office A", "Office B", "Conference Room 1", "Conference Room 2", "Cafeteria", "Lobby"],
            onTtsEnabledChange: { _ in }
        )
        .padding()
    }
}
