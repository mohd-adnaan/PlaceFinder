//
//  DataExportManager.swift
//  IndoorNavigationTACME
//
//  Created by Mohammad Adnaan on 2026-03-15.
//
//  Handles exporting acceleration/step data as CSV, navigation summaries,
//  and debug logs — matching Android's export capabilities for research.
//

import Foundation
import UIKit

class DataExportManager {
    
    static let shared = DataExportManager()
    private init() {}
    
    // MARK: - Step Data CSV Export (Android parity)
    
    /// Export acceleration samples as CSV matching Android's format:
    /// SampleIndex,Timestamp,RawMagnitude,FilteredMagnitude,IsPeak,IsValley,IsConfirmedStep,StepLength,StepNumber,PeakValleyDiff
    func exportStepDataCSV(samples: [AccelerationSample]) -> URL? {
        let fileName = "step_data_\(Int(Date().timeIntervalSince1970 * 1000)).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        var csv = "SampleIndex,Timestamp,X,Y,Z,RawMagnitude,FilteredMagnitude,IsPeak,IsValley,IsConfirmedStep,StepLength,StepNumber,PeakValleyDiff\n"
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for sample in samples {
            let ts = formatter.string(from: sample.timestamp)
            let stepLen = sample.stepLength.map { String(format: "%.4f", $0) } ?? ""
            let stepNum = sample.stepNumber.map { "\($0)" } ?? ""
            let pvDiff = sample.peakValleyDiff.map { String(format: "%.6f", $0) } ?? ""
            
            csv += "\(sample.sampleIndex),"
            csv += "\(ts),"
            csv += "\(String(format: "%.6f", sample.x)),"
            csv += "\(String(format: "%.6f", sample.y)),"
            csv += "\(String(format: "%.6f", sample.z)),"
            csv += "\(String(format: "%.6f", sample.magnitude)),"
            csv += "\(String(format: "%.6f", sample.filtered)),"
            csv += "\(sample.isPeak),"
            csv += "\(sample.isValley),"
            csv += "\(sample.isConfirmedStep),"
            csv += "\(stepLen),"
            csv += "\(stepNum),"
            csv += "\(pvDiff)\n"
        }
        
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            DebugLogger.shared.log(.export, .success, "Step data CSV exported: \(samples.count) samples → \(fileName)")
            return tempURL
        } catch {
            DebugLogger.shared.error(.export, "Failed to write step CSV: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Step Metrics Export
    
    func exportStepMetrics(
        metrics: [String: Any],
        bearingStats: [String: Any],
        sensorStatus: [String: Any],
        loggerStats: (totalSamples: Int, peakCount: Int, valleyCount: Int, confirmedStepCount: Int, timeSpanMs: Int64)
    ) -> URL? {
        let fileName = "step_metrics_\(Int(Date().timeIntervalSince1970 * 1000)).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        var text = "=== Step Detection Metrics ===\n"
        text += "Exported: \(Date())\n\n"
        
        text += "--- Step Detection ---\n"
        for (key, value) in metrics.sorted(by: { $0.key < $1.key }) {
            text += "  \(key): \(value)\n"
        }
        
        text += "\n--- Bearing Correction ---\n"
        for (key, value) in bearingStats.sorted(by: { $0.key < $1.key }) {
            text += "  \(key): \(value)\n"
        }
        
        text += "\n--- Sensor Status ---\n"
        for (key, value) in sensorStatus.sorted(by: { $0.key < $1.key }) {
            text += "  \(key): \(value)\n"
        }
        
        text += "\n--- Logger Statistics ---\n"
        text += "  totalSamples: \(loggerStats.totalSamples)\n"
        text += "  peakCount: \(loggerStats.peakCount)\n"
        text += "  valleyCount: \(loggerStats.valleyCount)\n"
        text += "  confirmedStepCount: \(loggerStats.confirmedStepCount)\n"
        text += "  timeSpanMs: \(loggerStats.timeSpanMs)\n"
        
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            DebugLogger.shared.log(.export, .success, "Step metrics exported → \(fileName)")
            return tempURL
        } catch {
            DebugLogger.shared.error(.export, "Failed to write metrics: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Navigation Summary Export
    
    func exportNavigationSummary(summary: [String: Any]) -> URL? {
        let fileName = "nav_summary_\(Int(Date().timeIntervalSince1970 * 1000)).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        var text = "=== Navigation Summary ===\n"
        text += "Exported: \(Date())\n\n"
        
        for (key, value) in summary.sorted(by: { $0.key < $1.key }) {
            text += "  \(key): \(value)\n"
        }
        
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            DebugLogger.shared.log(.export, .success, "Navigation summary exported → \(fileName)")
            return tempURL
        } catch {
            DebugLogger.shared.error(.export, "Failed to write nav summary: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Debug Logs Export
    
    func exportDebugLogs() -> URL? {
        let fileName = "debug_logs_\(Int(Date().timeIntervalSince1970 * 1000)).txt"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        let text = DebugLogger.shared.exportLogsAsText()
        
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            DebugLogger.shared.log(.export, .success, "Debug logs exported → \(fileName)")
            return tempURL
        } catch {
            DebugLogger.shared.error(.export, "Failed to write debug logs: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Full Research Bundle Export
    
    /// Exports everything: step CSV, metrics, nav summary, and debug logs.
    /// Returns array of file URLs to share.
    func exportFullResearchBundle(
        sensorManager: IMUSensorManager,
        navigationManager: NavigationManager
    ) -> [URL] {
        var urls: [URL] = []
        
        // 1. Step data CSV
        let samples = sensorManager.getAccelerationSamples()
        if let csvURL = exportStepDataCSV(samples: samples) {
            urls.append(csvURL)
        }
        
        // 2. Step metrics
        let metrics = sensorManager.getStepDetectionMetrics()
        let bearingStats = sensorManager.getBearingCorrectionStats()
        let sensorStatus = sensorManager.getSensorStatus()
        let loggerStats = sensorManager.getAccelerationLoggerStatistics()
        if let metricsURL = exportStepMetrics(
            metrics: metrics,
            bearingStats: bearingStats,
            sensorStatus: sensorStatus,
            loggerStats: loggerStats
        ) {
            urls.append(metricsURL)
        }
        
        // 3. Navigation summary
        let summary = navigationManager.getNavigationSummary()
        if let navURL = exportNavigationSummary(summary: summary) {
            urls.append(navURL)
        }
        
        // 4. Debug logs
        if let logsURL = exportDebugLogs() {
            urls.append(logsURL)
        }
        
        DebugLogger.shared.log(.export, .success, "Full research bundle: \(urls.count) files")
        return urls
    }
    
    // MARK: - Share via UIActivityViewController
    
    func shareFiles(_ urls: [URL], from viewController: UIViewController? = nil) {
        guard !urls.isEmpty else { return }
        
        let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
        
        guard let presenter = vc else { return }
        
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        
        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY - 50, width: 0, height: 0)
        }
        
        presenter.present(activityVC, animated: true)
    }
}
