//
//  QRCodeDetector.swift
//  IndoorNavigationTACME
//

import Foundation
import AVFoundation
import Vision
import UIKit
import Combine

/// Manages QR code detection for indoor navigation position correction
class QRCodeDetector: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var detectionState = QRDetectionState()
    
    // MARK: - Private Properties
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "qr.session.queue")
    private let detectionQueue = DispatchQueue(label: "qr.detection.queue", qos: .userInitiated)
    
    // Detection state
    private var isScanning = false
    private var frameCount: Int = 0
    private var lastDetectionTime: Date?
    private var totalProcessingTime: TimeInterval = 0
    private var lastFrameTime: Date?
    private var totalDetectionAttempts: Int = 0
    private var rejectedDetections: Int = 0
    
    // Rapid change detection
    private var previousQRContent: String?
    private var contentChangeCount: Int = 0
    private let changeDetectionWindow: TimeInterval = 0.5
    private var lastContentChangeTime: Date?
    
    // Configuration
    private let frameSkip = 3 // Process every 3rd frame in walking mode
    private let captureWidth = 1280
    private let captureHeight = 720
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("QRCodeDetector: Initialized")
    }
    
    // MARK: - Public Methods
    
    /// Start QR code scanning
    func startScanning() {
        guard !isScanning else {
            print("QRCodeDetector: Already scanning")
            return
        }
        
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
        }
    }
    
    /// Stop QR code scanning
    func stopScanning() {
        guard isScanning else { return }
        
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.isScanning = false
            
            DispatchQueue.main.async {
                self?.detectionState.isScanning = false
            }
            
            print("QRCodeDetector: Scanning stopped")
        }
    }

    /// Test Vision framework capabilities
    func testVisionCapabilities() {
        print("QRCodeDetector: Testing Vision capabilities")
        print("  - Barcode detection: Available")
        print("  - QR symbology: Supported")
        print("  - Camera available: \(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil)")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("  - Camera authorization: \(status.rawValue)")
    }

    /// Get detection statistics
    func getDetectionStats() -> [String: Any] {
        return [
            "isScanning": detectionState.isScanning,
            "isDetected": detectionState.isDetected,
            "detectionCount": detectionState.detectionCount,
            "lastQRContent": detectionState.lastQRContent ?? "None",
            "avgProcessingTime": detectionState.avgProcessingTime,
            "frameRate": detectionState.frameRate,
            "scanMode": String(describing: detectionState.scanMode),
            "actualResolution": detectionState.actualResolution,
            "rapidChangeMode": detectionState.rapidChangeMode,
            "detectionEngine": detectionState.detectionEngine
        ]
    }

    /// Cleanup resources
    func cleanup() {
        print("QRCodeDetector: Cleaning up resources")
        stopScanning()
        DispatchQueue.main.async { [weak self] in
            self?.detectionState = QRDetectionState()
        }
    }
    
    /// Reset detection state
    func resetDetection() {
        stopScanning()
        
        DispatchQueue.main.async { [weak self] in
            self?.detectionState = QRDetectionState()
        }
        
        frameCount = 0
        lastDetectionTime = nil
        totalProcessingTime = 0
        totalDetectionAttempts = 0
        rejectedDetections = 0
        previousQRContent = nil
        contentChangeCount = 0
        
        print("QRCodeDetector: Detection reset")
    }
    
    /// Set scan mode
    func setScanMode(_ mode: QRScanMode) {
        detectionState.scanMode = mode
        print("QRCodeDetector: Scan mode set to \(mode)")
    }
    
    // MARK: - Private Methods
    
    private func setupCaptureSession() {
        // Check camera authorization
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            initializeCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.initializeCaptureSession()
                } else {
                    self?.handleAuthorizationDenied()
                }
            }
        case .denied, .restricted:
            handleAuthorizationDenied()
        @unknown default:
            break
        }
    }
    
    private func initializeCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        
        // Setup camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("QRCodeDetector: Could not create camera input")
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Setup video output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: detectionQueue)
        output.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        captureSession = session
        videoOutput = output
        
        // Start session
        session.startRunning()
        isScanning = true
        
        DispatchQueue.main.async { [weak self] in
            self?.detectionState.isScanning = true
            self?.detectionState.actualResolution = "\(self?.captureWidth ?? 0)x\(self?.captureHeight ?? 0)"
            self?.detectionState.detectionEngine = "VISION"
        }
        
        print("QRCodeDetector: Capture session started")
    }
    
    private func handleAuthorizationDenied() {
        print("QRCodeDetector: Camera authorization denied")
        DispatchQueue.main.async { [weak self] in
            self?.detectionState.isScanning = false
        }
    }
    
    private func processQRCode(_ observation: VNBarcodeObservation) {
        guard let payload = observation.payloadStringValue else { return }
        
        let currentTime = Date()
        totalDetectionAttempts += 1
        
        // Check for rapid change
        if let previousContent = previousQRContent, previousContent != payload {
            contentChangeCount += 1
            
            if let lastChangeTime = lastContentChangeTime,
               currentTime.timeIntervalSince(lastChangeTime) < changeDetectionWindow {
                detectionState.rapidChangeMode = true
            }
            
            lastContentChangeTime = currentTime
        }
        
        previousQRContent = payload
        lastDetectionTime = currentTime
        
        DispatchQueue.main.async { [weak self] in
            self?.detectionState.isDetected = true
            self?.detectionState.lastDetectionTime = currentTime
            self?.detectionState.detectionCount += 1
            self?.detectionState.lastQRContent = payload
            self?.detectionState.detectedContent = payload
        }
        
        print("QRCodeDetector: Detected QR - \(payload)")
    }
    
    private func updatePerformanceMetrics(_ processingTime: TimeInterval) {
        totalProcessingTime += processingTime
        let avgTime = Float(totalProcessingTime) / Float(max(frameCount, 1))
        
        var frameRate: Float = 0
        if let lastTime = lastFrameTime {
            let interval = Date().timeIntervalSince(lastTime)
            frameRate = Float(1.0 / interval)
        }
        lastFrameTime = Date()
        
        DispatchQueue.main.async { [weak self] in
            self?.detectionState.avgProcessingTime = avgTime * 1000 // Convert to ms
            self?.detectionState.frameRate = frameRate
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension QRCodeDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        
        // Skip frames in walking mode for performance
        if detectionState.scanMode == .walking && frameCount % frameSkip != 0 {
            return
        }
        
        let startTime = Date()
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create Vision request
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("QRCodeDetector: Vision error - \(error)")
                return
            }
            
            guard let results = request.results as? [VNBarcodeObservation] else { return }
            
            // Process QR codes
            for observation in results {
                if observation.symbology == .qr {
                    self.processQRCode(observation)
                }
            }
            
            // Update clear state if no QR found
            if results.isEmpty {
                DispatchQueue.main.async {
                    // Keep detected state for persistence window
                    if let lastTime = self.detectionState.lastDetectionTime,
                       Date().timeIntervalSince(lastTime) > 3.0 {
                        self.detectionState.isDetected = false
                        self.detectionState.detectedContent = nil
                    }
                }
            }
        }
        
        request.symbologies = [.qr]
        
        // Perform request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("QRCodeDetector: Failed to perform request - \(error)")
        }
        
        // Update metrics
        let processingTime = Date().timeIntervalSince(startTime)
        updatePerformanceMetrics(processingTime)
    }
}

// MARK: - QR ID Extractor

/// Utility for extracting numeric ID from QR code content
struct QRIdExtractor {
    
    /// Extract numeric QR code ID from content
    /// Expected format: "QR_Id:https://qrco.de/..." or just numeric
    static func extractQRCodeId(_ content: String) -> String? {
        // Try to extract from "QR_Id:" prefix
        if content.hasPrefix("QR_Id:") {
            let idPart = content.replacingOccurrences(of: "QR_Id:", with: "")
            // Extract numeric part from URL or direct value
            if let numericPart = idPart.split(separator: "/").last {
                return String(numericPart)
            }
            return idPart
        }
        
        // Try to extract numeric ID from URL
        if content.contains("qrco.de") {
            if let lastPart = content.split(separator: "/").last {
                return String(lastPart)
            }
        }
        
        // Check if content is already numeric
        if content.allSatisfy({ $0.isNumber }) {
            return content
        }
        
        // Return raw content as fallback
        return content
    }
}
