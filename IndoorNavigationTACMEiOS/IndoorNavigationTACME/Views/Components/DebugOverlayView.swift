//
//  DebugOverlayView.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-15.
//
//  Floating bug button (bottom-right) that toggles an overlay showing
//  live debug logs: API calls/responses, navigation events, errors, etc.
//  Also provides export buttons for research data.
//

import SwiftUI

// MARK: - Debug Overlay

struct DebugOverlayView: View {
    @ObservedObject private var logger = DebugLogger.shared
    @EnvironmentObject var sensorManager: IMUSensorManager
    @EnvironmentObject var navigationManager: NavigationManager
    
    @State private var isExpanded: Bool = false
    @State private var selectedCategories: Set<LogCategory> = []
    @State private var showExportSheet: Bool = false
    @State private var exportURLs: [URL] = []
    @State private var autoScroll: Bool = true
    @State private var showDetail: DebugLogEntry? = nil
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Log panel (shown when expanded)
            if isExpanded {
                logPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            
            // Bug button
            bugButton
        }
        .sheet(isPresented: $showExportSheet) {
            if !exportURLs.isEmpty {
                ActivityViewController(activityItems: exportURLs)
            }
        }
        .sheet(item: $showDetail) { entry in
            DetailSheet(entry: entry)
        }
    }
    
    // MARK: - Bug Button
    
    private var bugButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(isExpanded
                          ? Color.red.opacity(0.9)
                          : Color.white.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                
                Image(systemName: isExpanded ? "xmark" : "ladybug.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isExpanded ? .white : .orange)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .accessibilityLabel(isExpanded ? "Close debug log" : "Open debug log")
    }
    
    // MARK: - Log Panel
    
    private var logPanel: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
            
            // Category filter chips
            categoryFilterBar
            
            // Log entries
            logList
            
            // Bottom toolbar with export
            bottomToolbar
        }
        .background(Color.black.opacity(0.92))
        .cornerRadius(16)
        .padding(.horizontal, 8)
        .padding(.bottom, 72) // Above the bug button
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack {
            Image(systemName: "ant.fill")
                .foregroundColor(.orange)
            Text("Debug Log")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("\(filteredEntries.count) entries")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
            
            Button(action: { autoScroll.toggle() }) {
                Image(systemName: autoScroll ? "arrow.down.to.line" : "arrow.down.to.line.compact")
                    .font(.system(size: 12))
                    .foregroundColor(autoScroll ? .green : .gray)
            }
            .accessibilityLabel(autoScroll ? "Auto-scroll on" : "Auto-scroll off")
            
            Button(action: { logger.clear() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.7))
            }
            .accessibilityLabel("Clear logs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
    }
    
    // MARK: - Category Filter
    
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" chip
                FilterChip(
                    label: "All",
                    isSelected: selectedCategories.isEmpty,
                    action: { selectedCategories.removeAll() }
                )
                
                ForEach(LogCategory.allCases, id: \.rawValue) { cat in
                    FilterChip(
                        label: "\(cat.emoji) \(cat.rawValue)",
                        isSelected: selectedCategories.contains(cat),
                        action: {
                            if selectedCategories.contains(cat) {
                                selectedCategories.remove(cat)
                            } else {
                                selectedCategories.insert(cat)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.white.opacity(0.03))
    }
    
    // MARK: - Log List
    
    private var filteredEntries: [DebugLogEntry] {
        logger.entries(for: selectedCategories)
    }
    
    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                            .onTapGesture {
                                if entry.detail != nil {
                                    showDetail = entry
                                }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: logger.entries.count) { _ in
                if autoScroll, let last = filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // Export step data CSV
            Button(action: exportStepData) {
                Label("Steps CSV", systemImage: "tablecells")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.cyan)
            
            // Export debug logs
            Button(action: exportLogs) {
                Label("Logs", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.cyan)
            
            // Export full research bundle
            Button(action: exportFullBundle) {
                Label("Export All", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.orange)
            
            Spacer()
            
            // Show step metrics
            Button(action: showMetrics) {
                Label("Metrics", systemImage: "gauge")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
    }
    
    // MARK: - Actions
    
    private func exportStepData() {
        let samples = sensorManager.getAccelerationSamples()
        if let url = DataExportManager.shared.exportStepDataCSV(samples: samples) {
            exportURLs = [url]
            showExportSheet = true
        }
    }
    
    private func exportLogs() {
        if let url = DataExportManager.shared.exportDebugLogs() {
            exportURLs = [url]
            showExportSheet = true
        }
    }
    
    private func exportFullBundle() {
        let urls = DataExportManager.shared.exportFullResearchBundle(
            sensorManager: sensorManager,
            navigationManager: navigationManager
        )
        if !urls.isEmpty {
            exportURLs = urls
            showExportSheet = true
        }
    }
    
    private func showMetrics() {
        let metrics = sensorManager.getStepDetectionMetrics()
        let stats = sensorManager.getAccelerationLoggerStatistics()
        var msg = "Steps: \(metrics["totalSteps"] ?? 0), "
        msg += "AvgLen: \(metrics["averageStepLength"] ?? "?"), "
        msg += "Peaks: \(stats.peakCount), "
        msg += "Valleys: \(stats.valleyCount), "
        msg += "Samples: \(stats.totalSamples)"
        DebugLogger.shared.log(.sensor, .info, msg)
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: DebugLogEntry
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            
            Text(entry.category.emoji)
                .font(.system(size: 10))
                .frame(width: 16)
            
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(colorForLevel(entry.level))
                .lineLimit(2)
            
            Spacer(minLength: 0)
            
            if entry.detail != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            entry.level == .error
                ? Color.red.opacity(0.08)
                : Color.clear
        )
        .cornerRadius(4)
    }
    
    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .white.opacity(0.8)
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.orange : Color.white.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

// MARK: - Detail Sheet

private struct DetailSheet: View {
    let entry: DebugLogEntry
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Entry header
                    HStack {
                        Text(entry.category.emoji)
                        Text(entry.category.rawValue)
                            .font(.headline)
                        Text("/ \(entry.level.rawValue)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(entry.message)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    if let detail = entry.detail {
                        Divider()
                        Text("Detail:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView(.horizontal) {
                            Text(detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Log Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        var text = "[\(entry.category.rawValue)/\(entry.level.rawValue)] \(entry.message)"
                        if let detail = entry.detail {
                            text += "\n\n\(detail)"
                        }
                        UIPasteboard.general.string = text
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

// MARK: - UIKit ActivityViewController wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
