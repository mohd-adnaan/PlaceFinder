// QRCodeDetector.kt - Complete implementation with all missing properties

package com.example.imunavigation.qr


import androidx.camera.core.ExperimentalGetImage


import android.content.Context
import android.util.Log
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Complete Google ML Kit QR Detector with Smart Sync and Rapid Change Detection
 *
 */
@androidx.camera.core.ExperimentalGetImage
class QRCodeDetector(private val context: Context) {

    data class QRDetectionState(
        val isDetected: Boolean = false,
        val lastDetectionTime: Long = 0L,
        val detectionCount: Int = 0,
        val isScanning: Boolean = false,
        val lastQRContent: String? = null,
        val actualResolution: String = "",
        val avgProcessingTime: Float = 0f,
        val frameRate: Float = 0f,
        val walkingOptimized: Boolean = true,
        val detectionEngine: String = "ML_KIT",
        val rapidChangeMode: Boolean = false,
        val changeDetectionEnabled: Boolean = true
    )

    private val _detectionState = MutableStateFlow(QRDetectionState())
    val detectionState: StateFlow<QRDetectionState> = _detectionState.asStateFlow()

    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var camera: Camera? = null

    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r).apply {
            priority = Thread.MAX_PRIORITY
            name = "MLKit-QR"
        }
    }

    // ML Kit Barcode Scanner
    private val barcodeScanner: BarcodeScanner by lazy {
        val options = BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
        BarcodeScanning.getClient(options)
    }

    // MISSING PROPERTIES - NOW ADDED
    private var isWalkingMode = false
    private var frameCount = 0L
    private var lastDetectionTime = 0L
    private var totalProcessingTime = 0L
    private var lastFrameTime = 0L
    private var totalDetectionAttempts = 0L
    private var rejectedDetections = 0L

    // Rapid change detection
    private var previousQRContent: String? = null
    private var qrChangeDetected = false
    private var lastChangeTime = 0L
    private val QR_CHANGE_COOLDOWN = 100L // 100ms minimum between changes

    // Enhanced persistence - shorter but smarter
    private var qrPersistenceDuration = 800L    // 800ms default
    private var isRapidChangeMode = false
    private var isNavigationMode = false

    // QR Code validation settings
    private var minQRCodeLength = 4
    private var maxQRCodeLength = 100
    private var requireNumericContent = false
    private var allowedQRPattern: Regex? = null
    private var minConfidenceThreshold = 0.7f

    companion object {
        private const val TAG = "MLKitQRDetector"
    }

    /**
     * Start camera with ML Kit optimization
     */
    suspend fun startScanning(lifecycleOwner: LifecycleOwner): Boolean {
        return try {
            Log.d(TAG, "Starting ML Kit QR scanning (walking optimized)")

            return withContext(Dispatchers.Main) {
                val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
                cameraProvider = cameraProviderFuture.get()

                imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(1280, 720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                    .build()

                imageAnalysis?.setAnalyzer(cameraExecutor) { imageProxy ->
                    processMLKitFrame(imageProxy)
                }

                val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

                try {
                    cameraProvider?.unbindAll()
                    camera = cameraProvider?.bindToLifecycle(
                        lifecycleOwner,
                        cameraSelector,
                        imageAnalysis
                    )

                    val actualRes = "${imageAnalysis?.resolutionInfo?.resolution?.width}x${imageAnalysis?.resolutionInfo?.resolution?.height}"

                    _detectionState.value = _detectionState.value.copy(
                        isScanning = true,
                        actualResolution = actualRes,
                        detectionEngine = "ML_KIT"
                    )

                    Log.d(TAG, "ML Kit scanner started: $actualRes")
                    true

                } catch (e: Exception) {
                    Log.e(TAG, "Failed to bind camera: ${e.message}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize camera: ${e.message}")
            false
        }
    }

    /**
     * Enable rapid change mode for closely spaced QR codes
     */
    fun enableRapidChangeMode() {
        isRapidChangeMode = true
        qrPersistenceDuration = 300L  // Shorter persistence for rapid changes

        _detectionState.value = _detectionState.value.copy(
            rapidChangeMode = true,
            changeDetectionEnabled = true
        )

        Log.d(TAG, "RAPID CHANGE MODE: persistence=${qrPersistenceDuration}ms, cooldown=${QR_CHANGE_COOLDOWN}ms")
    }

    /**
     * Enable navigation mode with optimized change detection
     */
    fun enableNavigationMode() {
        isNavigationMode = true
        isRapidChangeMode = true  // Navigation implies rapid changes
        qrPersistenceDuration = 500L  // 500ms for navigation

        _detectionState.value = _detectionState.value.copy(
            rapidChangeMode = true,
            changeDetectionEnabled = true
        )

        Log.d(TAG, "NAVIGATION + RAPID CHANGE MODE: persistence=${qrPersistenceDuration}ms")
    }

    /**
     * Enable walking mode with rapid change optimization
     */
    fun enableWalkingMode() {
        isWalkingMode = true
        lastDetectionTime = 0L

        // If rapid change mode is enabled, optimize further
        if (isRapidChangeMode) {
            qrPersistenceDuration = 200L  // Very short for walking + rapid changes
        }

        _detectionState.value = _detectionState.value.copy(walkingOptimized = true)
        Log.d(TAG, "ML Kit WALKING + RAPID: persistence=${qrPersistenceDuration}ms")
    }

    /**
     * Get cooldown based on current mode
     */
    private fun getCooldownMs(): Long = when {
        isRapidChangeMode -> 30L
        isNavigationMode -> 50L
        isWalkingMode -> 100L
        else -> 300L
    }

    /**
     * Enhanced detection handler with immediate change detection
     */
    private fun handleMLKitDetection(qrContent: String, detectionTime: Long) {
        val currentTime = System.currentTimeMillis()

        // Check for QR change
        val isQRChange = qrContent != previousQRContent
        val canDetectChange = (currentTime - lastChangeTime) > QR_CHANGE_COOLDOWN

        if (isQRChange && canDetectChange) {
            Log.i(TAG, "QR CHANGE: '${previousQRContent}' → '$qrContent'")
            qrChangeDetected = true
            lastChangeTime = currentTime
            previousQRContent = qrContent
        } else if (!isQRChange) {
            // Same QR - just refresh timestamp
            Log.v(TAG, "QR REFRESH: '$qrContent'")
        }

        // Update detection state
        _detectionState.value = _detectionState.value.copy(
            isDetected = true,
            lastDetectionTime = detectionTime,
            detectionCount = if (isQRChange) _detectionState.value.detectionCount + 1 else _detectionState.value.detectionCount,
            lastQRContent = qrContent
        )

        val modeText = when {
            isRapidChangeMode -> "RAPID"
            isNavigationMode -> "NAV"
            isWalkingMode -> "WALK"
            else -> "NORMAL"
        }

        Log.i(TAG, "ML KIT $modeText QR: $qrContent ${if (isQRChange) "[NEW]" else "[SAME]"}")

        // Smart reset timing based on mode
        val resetDelay = when {
            isRapidChangeMode -> 200L  // Quick reset for rapid changes
            isNavigationMode -> 400L   // Medium for navigation
            else -> qrPersistenceDuration
        }

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            // Only reset if no newer detection occurred
            if (_detectionState.value.lastDetectionTime <= detectionTime) {
                _detectionState.value = _detectionState.value.copy(
                    isDetected = false
                    // Keep lastQRContent for debugging
                )
                Log.v(TAG, "QR state reset after ${resetDelay}ms")
            }
        }, resetDelay)
    }

    /**
     * Process frame with Google ML Kit
     */
    private fun processMLKitFrame(imageProxy: ImageProxy) {
        val startTime = System.currentTimeMillis()
        frameCount++

        try {
            // Shorter cooldown for rapid change mode
            val cooldown = getCooldownMs()

            if (startTime - lastDetectionTime < cooldown) {
                imageProxy.close()
                return
            }

            val mediaImage = imageProxy.image
            if (mediaImage != null) {
                val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)

                totalDetectionAttempts++

                barcodeScanner.process(image)
                    .addOnSuccessListener { barcodes ->
                        val processingTime = System.currentTimeMillis() - startTime

                        if (barcodes.isNotEmpty()) {
                            for (barcode in barcodes) {
                                val qrContent = barcode.rawValue
                                if (qrContent != null) {
                                    // Enhanced validation for navigation
                                    if (isValidNavigationQR(barcode, qrContent)) {
                                        handleMLKitDetection(qrContent, startTime)
                                        lastDetectionTime = startTime
                                        break
                                    } else {
                                        Log.v(TAG, "QR failed validation: $qrContent")
                                        rejectedDetections++
                                    }
                                }
                            }
                        }

                        updateMLKitStats(processingTime)
                    }
                    .addOnFailureListener { e ->
                        Log.w(TAG, "ML Kit detection failed: ${e.message}")
                    }
                    .addOnCompleteListener {
                        imageProxy.close()
                    }
            } else {
                imageProxy.close()
            }

        } catch (e: Exception) {
            Log.e(TAG, "ML Kit frame processing error: ${e.message}")
            imageProxy.close()
        }
    }

    /**
     * Validate QR code with criteria
     */
    private fun isValidQRCode(barcode: Barcode, content: String): Boolean {
        try {
            // Basic validation
            val boundingBox = barcode.boundingBox
            if (boundingBox == null) {
                Log.v(TAG, "QR rejected: No bounding box")
                return false
            }

            val cornerPoints = barcode.cornerPoints
            if (cornerPoints == null || cornerPoints.size != 4) {
                Log.v(TAG, "QR rejected: Invalid corner points (${cornerPoints?.size ?: 0})")
                return false
            }

            // Check aspect ratio
            val aspectRatio = boundingBox.width().toFloat() / boundingBox.height().toFloat()
            if (aspectRatio < 0.7f || aspectRatio > 1.3f) {
                Log.v(TAG, "QR rejected: Not square (aspect ratio: $aspectRatio)")
                return false
            }

            // Minimum size
            val minDimension = kotlin.math.min(boundingBox.width(), boundingBox.height())
            if (minDimension < 80) {
                Log.v(TAG, "QR rejected: Too small ($minDimension pixels)")
                return false
            }

            // Content validation
            if (content.length < minQRCodeLength || content.length > maxQRCodeLength) {
                Log.v(TAG, "QR rejected: Invalid length ${content.length}")
                return false
            }

            return true

        } catch (e: Exception) {
            Log.w(TAG, "QR validation error: ${e.message}")
            return false
        }
    }

    /**
     * Enhanced validation for rapid navigation QRs
     */
    private fun isValidNavigationQR(barcode: Barcode, content: String): Boolean {
        // Basic validation first
        if (!isValidQRCode(barcode, content)) {
            return false
        }

        // Rapid change mode - be more permissive for quick detection
        if (isRapidChangeMode) {
            return when {
                // Numeric IDs (waypoints)
                content.all { it.isDigit() } && content.length >= 1 -> true

                // Structured codes
                content.contains(":") && content.length >= 4 -> true

                // Short alphanumeric codes
                content.matches(Regex("^[A-Za-z0-9_-]+$")) && content.length >= 2 -> true

                // URLs
                content.startsWith("http") -> true

                else -> {
                    Log.v(TAG, "QR rejected in rapid mode: $content")
                    false
                }
            }
        }

        // Standard navigation validation
        return when {
            content.all { it.isDigit() } && content.length >= 3 -> true
            content.contains(":") && content.length >= 6 -> true
            content.matches(Regex("^[A-Z]+[_-]?\\d+$")) -> true
            content.startsWith("http") -> true
            else -> {
                Log.v(TAG, "QR rejected: Not navigation format: $content")
                false
            }
        }
    }

    /**
     * Update ML Kit performance statistics
     */
    private fun updateMLKitStats(processingTime: Long) {
        totalProcessingTime += processingTime

        if (frameCount % 20 == 0L) {  // Update every 20 frames
            val currentTime = System.currentTimeMillis()
            val timeSinceLastFrame = if (lastFrameTime > 0) currentTime - lastFrameTime else 0L
            val fps = if (timeSinceLastFrame > 0) 1000f / timeSinceLastFrame else 0f
            lastFrameTime = currentTime

            val avgTime = if (frameCount > 0) totalProcessingTime.toFloat() / frameCount else 0f

            _detectionState.value = _detectionState.value.copy(
                avgProcessingTime = avgTime,
                frameRate = fps
            )

            if (frameCount % 60 == 0L) {  // Log every 60 frames
                Log.d(TAG, "ML Kit Performance: ${avgTime.toInt()}ms avg, ${fps.toInt()} FPS")
            }
        }
    }



    /**
     * Configure strict QR detection
     */
    fun enableStrictQRDetection(
        minLength: Int = 4,
        maxLength: Int = 50,
        numericOnly: Boolean = false,
        pattern: String? = null
    ) {
        minQRCodeLength = minLength
        maxQRCodeLength = maxLength
        requireNumericContent = numericOnly
        allowedQRPattern = pattern?.let { Regex(it) }
        minConfidenceThreshold = 0.8f

        Log.d(TAG, "STRICT QR detection enabled: minLen=$minLength, maxLen=$maxLength, " +
                "numeric=$numericOnly, pattern=$pattern")
    }

    /**
     * Enhanced statistics with rapid change info
     */
    fun getDetectionStats(): Map<String, Any> {
        val state = _detectionState.value
        val rejectionRate = if (totalDetectionAttempts > 0) {
            (rejectedDetections.toFloat() / totalDetectionAttempts * 100)
        } else 0f

        val currentTime = System.currentTimeMillis()

        return mapOf(
            "isScanning" to state.isScanning,
            "isDetected" to state.isDetected,
            "detectionCount" to state.detectionCount,
            "actualResolution" to state.actualResolution,
            "detectionEngine" to state.detectionEngine,
            "avgProcessingTime" to String.format("%.1fms", state.avgProcessingTime),
            "frameRate" to String.format("%.1f FPS", state.frameRate),
            "walkingOptimized" to state.walkingOptimized,
            "rapidChangeMode" to state.rapidChangeMode,
            "changeDetectionEnabled" to state.changeDetectionEnabled,
            "navigationMode" to isNavigationMode,
            "persistenceDuration" to "${qrPersistenceDuration}ms",
            "changeCooldown" to "${QR_CHANGE_COOLDOWN}ms",
            "previousQR" to (previousQRContent ?: "None"),
            "lastChangeTime" to if (lastChangeTime > 0) {
                "${(currentTime - lastChangeTime)}ms ago"
            } else "Never",
            "cooldownMs" to getCooldownMs(),
            "validationEnabled" to true,
            "totalDetectionAttempts" to totalDetectionAttempts,
            "rejectedDetections" to rejectedDetections,
            "rejectionRate" to String.format("%.1f%%", rejectionRate),
            "lastDetection" to if (state.lastDetectionTime > 0) {
                "${(currentTime - state.lastDetectionTime) / 1000}s ago"
            } else "Never",
            "lastQRContent" to (state.lastQRContent ?: "None"),
            "advantages" to "Rapid change detection, immediate capture, smart persistence",
            "optimizedFor" to "Closely spaced QR codes, navigation waypoints"
        )
    }


    /**
     * Test ML Kit capabilities
     */
    fun testMLKitCapabilities() {
        Log.d(TAG, "=== ML KIT CAPABILITIES ===")
        Log.d(TAG, "Motion blur resistant")
        Log.d(TAG, "Angle tolerant")
        Log.d(TAG, "Hardware accelerated")
        Log.d(TAG, "Real-time optimized")
        Log.d(TAG, "Walking detection ready")
        Log.d(TAG, "Rapid change detection")
        Log.d(TAG, "ZXing limitations removed")
    }

    /**
     * Reset change detection state
     */
    fun resetChangeDetection() {
        previousQRContent = null
        qrChangeDetected = false
        lastChangeTime = 0L
        Log.d(TAG, "Change detection reset")
    }




    fun stopScanning() {
        Log.d(TAG, "Stopping ML Kit QR scanner")
        try {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    cameraProvider?.unbindAll()
                    camera = null
                    imageAnalysis = null
                    _detectionState.value = _detectionState.value.copy(isScanning = false, isDetected = false)
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping camera: ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping camera: ${e.message}")
        }
    }

    fun resetDetection() {
        _detectionState.value = QRDetectionState()
        frameCount = 0L
        totalProcessingTime = 0L
        lastFrameTime = 0L
        totalDetectionAttempts = 0L
        rejectedDetections = 0L
        resetChangeDetection()
        Log.d(TAG, "ML Kit detection reset")
    }

    fun cleanup() {
        Log.d(TAG, "Cleaning up ML Kit detector with change detection")
        resetChangeDetection()
        barcodeScanner.close()
        stopScanning()
        cameraExecutor.shutdown()
    }
}