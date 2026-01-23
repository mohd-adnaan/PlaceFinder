//
//  QRCodeDetector.swift
//  IndoorNavigationTACME
//
//  QR Code detection using iOS Vision framework
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
    
    // Walking optimization
    private var isWalkingMode: Bool = false
    
    // Vision request
    private lazy var detectBarcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            self?.handleBarcodeDetection(request: request, error: error)
        }
        request.symbologies = [.qr]
        return request
    }()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        print("QRCodeDetector: Initialized")
    }
    
    deinit {
        stopScanning()
    }
    
    // MARK: - Public Methods
    
    /// Start QR code scanning
    func startScanning() {
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
            self?.captureSession?.startRunning()
            DispatchQueue.main.async {
                self?.isScanning = true
                self?.detectionState.isScanning = true
                print("QRCodeDetector: Scanning started")
            }
        }
    }
    
    /// Stop QR code scanning
    func stopScanning() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isScanning = false
                self?.detectionState.isScanning = false
                print("QRCodeDetector: Scanning stopped")
            }
        }
    }
    
    /// Reset detection state
    func resetDetection() {
        DispatchQueue.main.async {
            self.detectionState = QRDetectionState()
            self.previousQRContent = nil
            self.contentChangeCount = 0
            self.lastContentChangeTime = nil
            self.frameCount = 0
            self.totalProcessingTime = 0
            self.totalDetectionAttempts = 0
            self.rejectedDetections = 0
            print("QRCodeDetector: Detection reset")
        }
    }
    
    /// Enable walking optimization mode
    func setWalkingMode(_ enabled: Bool) {
        isWalkingMode = enabled
    }
    
    /// Get detection statistics
    func getDetectionStats() -> [String: Any] {
        let avgProcessingTime = totalDetectionAttempts > 0 ?
            totalProcessingTime / Double(totalDetectionAttempts) * 1000 : 0
        
        let frameRate: Double
        if let lastFrame = lastFrameTime {
            let elapsed = Date().timeIntervalSince(lastFrame)
            frameRate = elapsed > 0 ? 1.0 / elapsed : 0
        } else {
            frameRate = 0
        }
        
        return [
            "totalFrames": frameCount,
            "detectionCount": detectionState.detectionCount,
            "avgProcessingTimeMs": String(format: "%.1f", avgProcessingTime),
            "frameRate": String(format: "%.1f", frameRate),
            "rejectedDetections": rejectedDetections,
            "successRate": totalDetectionAttempts > 0 ?
                String(format: "%.1f%%", Double(detectionState.detectionCount) / Double(totalDetectionAttempts) * 100) : "0%",
            "walkingMode": isWalkingMode,
            "rapidChangeMode": detectionState.rapidChangeMode
        ]
    }
    
    /// Test Vision capabilities
    func testVisionCapabilities() {
        print("QRCodeDetector: Testing Vision capabilities")
        print("  - Supported symbologies: \(VNDetectBarcodesRequest.supportedSymbologies)")
        print("  - QR Code supported: \(VNDetectBarcodesRequest.supportedSymbologies.contains(.qr))")
    }
    
    /// Cleanup resources
    func cleanup() {
        stopScanning()
        captureSession = nil
        videoOutput = nil
        resetDetection()
        print("QRCodeDetector: Cleaned up")
    }
    
    // MARK: - Private Methods
    
    private func setupCaptureSession() {
        guard captureSession == nil else { return }
        
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        
        // Setup camera input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("QRCodeDetector: Failed to setup camera input")
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        // Setup video output
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: detectionQueue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        // Configure focus for QR detection
        do {
            try videoDevice.lockForConfiguration()
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            videoDevice.unlockForConfiguration()
        } catch {
            print("QRCodeDetector: Failed to configure camera: \(error)")
        }
        
        captureSession = session
        videoOutput = output
        
        DispatchQueue.main.async {
            self.detectionState.actualResolution = "1280x720"
        }
        
        print("QRCodeDetector: Capture session configured")
    }
    
    private func handleBarcodeDetection(request: VNRequest, error: Error?) {
        if let error = error {
            print("QRCodeDetector: Detection error: \(error)")
            return
        }
        
        guard let results = request.results as? [VNBarcodeObservation] else { return }
        
        let processingEnd = Date()
        let processingTime = lastFrameTime.map { processingEnd.timeIntervalSince($0) } ?? 0
        totalProcessingTime += processingTime
        totalDetectionAttempts += 1
        
        // Find QR code with highest confidence
        let qrResults = results.filter { $0.symbology == .qr }
        
        if let bestResult = qrResults.max(by: { $0.confidence < $1.confidence }),
           let payload = bestResult.payloadStringValue {
            
            let currentTime = Date()
            
            // Check for rapid change
            let isRapidChange: Bool
            if let prevContent = previousQRContent, prevContent != payload {
                if let lastChangeTime = lastContentChangeTime {
                    isRapidChange = currentTime.timeIntervalSince(lastChangeTime) < changeDetectionWindow
                } else {
                    isRapidChange = false
                }
                contentChangeCount += 1
                lastContentChangeTime = currentTime
            } else {
                isRapidChange = false
            }
            
            previousQRContent = payload
            
            DispatchQueue.main.async {
                self.detectionState.isDetected = true
                self.detectionState.lastDetectionTime = currentTime
                self.detectionState.detectionCount += 1
                self.detectionState.lastQRContent = payload
                self.detectionState.avgProcessingTime = Float(processingTime * 1000)
                self.detectionState.rapidChangeMode = isRapidChange
                
                if let lastFrame = self.lastFrameTime {
                    let elapsed = currentTime.timeIntervalSince(lastFrame)
                    self.detectionState.frameRate = elapsed > 0 ? Float(1.0 / elapsed) : 0
                }
            }
            
            #if DEBUG
            print("QRCodeDetector: Detected QR: \(payload) (confidence: \(bestResult.confidence))")
            #endif
        } else {
            DispatchQueue.main.async {
                self.detectionState.isDetected = false
            }
        }
        
        lastFrameTime = processingEnd
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension QRCodeDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        frameCount += 1
        
        // Skip frames in walking mode for performance
        if isWalkingMode && frameCount % 3 != 0 {
            return
        }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try requestHandler.perform([detectBarcodeRequest])
        } catch {
            print("QRCodeDetector: Failed to perform detection: \(error)")
        }
    }
}

// MARK: - QR ID Extractor

/// Utility for extracting numeric IDs from QR content
enum QRIdExtractor {
    
    /// Extract numeric ID from QR content
    static func extractQRCodeId(_ qrContent: String?) -> String? {
        guard let content = qrContent, !content.isEmpty else { return nil }
        
        // Handle specific format: "QR_Id:https://qrco.de/bgErvr"
        if content.hasPrefix("QR_Id:") && content.contains("qrco.de/") {
            if let urlCode = content.components(separatedBy: "qrco.de/").last {
                return convertUrlCodeToNumber(urlCode)
            }
        }
        
        // Look for existing numbers in content
        let numberPattern = try? NSRegularExpression(pattern: "\\d+", options: [])
        if let matches = numberPattern?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let firstMatch = matches.first,
           let range = Range(firstMatch.range, in: content) {
            return String(content[range])
        }
        
        // Hash any other content to a consistent number
        return hashToNumber(content)
    }
    
    private static func convertUrlCodeToNumber(_ urlCode: String) -> String {
        guard !urlCode.isEmpty else { return "0" }
        
        var numericValue: Int = 0
        
        for (index, char) in urlCode.enumerated() {
            let charValue: Int
            if char.isNumber {
                charValue = char.wholeNumberValue ?? 0
            } else if char.isLetter {
                charValue = Int(char.lowercased().unicodeScalars.first!.value) - Int(Unicode.Scalar("a").value) + 10
            } else {
                charValue = Int(char.unicodeScalars.first?.value ?? 0) % 36
            }
            numericValue += charValue * (36 * index + 1)
        }
        
        return String(abs(numericValue) % 999999)
    }
    
    private static func hashToNumber(_ content: String) -> String {
        let hash = content.hashValue
        return String(abs(hash) % 999999)
    }
}
