// NavigationManager.kt
package com.example.imunavigation.navigation

import android.util.Log
import androidx.lifecycle.LifecycleOwner
import com.example.imunavigation.api.NavigationAPI
import com.example.imunavigation.calibration.IMUCalibrationManager
import com.example.imunavigation.sensors.IMUSensorManager
import com.example.imunavigation.tts.TTSManager
import com.example.imunavigation.qr.QRCodeDetector
import com.example.imunavigation.qr.QRIdExtractor
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.abs
import com.example.imunavigation.language.LanguageManager

/**
 * Complete NavigationManager with Smart QR Synchronization

 */
@androidx.camera.core.ExperimentalGetImage
class NavigationManager(
    private val navigationAPI: NavigationAPI,
    private val calibrationManager: IMUCalibrationManager,
    private val sensorManager: IMUSensorManager,
    private val ttsManager: TTSManager,
    private val qrDetector: QRCodeDetector,
    private val languageManager: LanguageManager,
    private var lastStepCount: Int = 0
) {


    init {
        calibrationManager.setSensorManager(sensorManager)
        Log.d(TAG, "NavigationManager initialized - calibration manager connected to sensor manager (no magnetometer)")
    }

    /**
     * Navigation session state with QR sync info
     */
    data class NavigationState(
        val isNavigating: Boolean = false,
        val isInitialized: Boolean = false,
        val isCalibrated: Boolean = false,
        val currentInstruction: String = "Ready to navigate",
        val serverResponse: String? = null,
        val source: String = "",
        val destination: String = "",
        val useClockDirections: Boolean = false,
        val useLandmarks: Boolean = false,
        val lastUpdateTime: Long = 0L,
        val errorMessage: String? = null,
        val initializationStep: InitStep = InitStep.NOT_STARTED,
        // Enhanced QR state
        val qrDetectionActive: Boolean = false,
        val lastQRDetectionTime: Long = 0L,
        val qrDetectionCount: Int = 0,
        val currentQRId: String? = null,
        val lastSentQRId: String? = null,
        val qrSyncMode: String = "SMART_SYNC",
        // Bearing correction state
        val currentSegmentId: Int = -1,
        val trueBearing: Double? = null,
        val bearingCorrectionApplied: Boolean = false,
        val bearingCorrectionCount: Int = 0

    )

    enum class InitStep {
        NOT_STARTED,
        INITIALIZED,
        NAVIGATING,
        ERROR
    }

    private val sessionId = "android_session_${System.currentTimeMillis()}"
    private val navigationScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Navigation state
    private val _navigationState = MutableStateFlow(NavigationState())
    val navigationState: StateFlow<NavigationState> = _navigationState.asStateFlow()

    // Update job for continuous position updates
    private var updateJob: Job? = null

    // Store calibration data from server
    private var tempCalibrationData: CalibrationData? = null

    // QR detection monitoring
    private var qrMonitoringJob: Job? = null

    // SMART QR SYNC STATE
    private var currentQRId: String? = null
    private var currentQRDetectionTime: Long = 0L
    private var lastSentQRId: String? = null
    private val QR_PERSISTENCE_WINDOW = 3000L  // 3 seconds persistence
    private val QR_CHANGE_DETECTION_WINDOW = 200L  // 200ms for change detection

    // BEARING CORRECTION SYSTEM
    private var pathBearings: List<Double> = emptyList()
    private var currentSegmentId: Int = -1
    private val BEARING_CORRECTION_THRESHOLD = 25.0  // degrees
    private var bearingCorrectionCount = 0

    companion object {
        private const val TAG = "NavigationManager"
        private const val UPDATE_INTERVAL_MS = 50L
        private const val MAX_RETRY_ATTEMPTS = 3
        private const val RETRY_DELAY_MS = 2000L
    }


    /**
     * Store path bearings received from server during initialization
     */

    private fun storePathBearings(bearings: List<Double>) {
        pathBearings = bearings

        // Immediately provide to sensor manager for position calculations
        sensorManager.setBearingCorrectionData(bearings, currentSegmentId)

        Log.d(TAG, "Stored ${bearings.size} path path bearings: $bearings")
    }




    /**
     * Update current segment ID from server response
     */

    private fun updateCurrentSegmentId(segmentId: Int) {
        if (segmentId != currentSegmentId) {
            currentSegmentId = segmentId

            // Update sensor manager immediately so next step uses correct bearing
            sensorManager.setBearingCorrectionData(pathBearings, segmentId)

            Log.d(TAG, "Segment ID updated: $currentSegmentId - sensor manager notified")

            _navigationState.value = _navigationState.value.copy(
                currentSegmentId = currentSegmentId
            )
        }
    }


    /**
     * Step 1: Initialize navigation session with server
     */
    suspend fun initializeWithServer(
        source: String,
        destination: String,
        useClockDirections: Boolean = false,
        useLandmarks: Boolean = false,
        conversationMode: Boolean = false
    ): Result<String> {
        return withContext(Dispatchers.IO) {
            try {

                Log.d(TAG, "Clearing accumulated data before initialization...")
                sensorManager.clearAccumulatedData()

                // Reset step counter to prevent issues
                lastStepCount = 0
                Log.d(TAG, "Step 1: Initializing with server: $source -> $destination")

                // Validate inputs
                if (source.isBlank() || destination.isBlank()) {
                    return@withContext Result.failure(
                        IllegalArgumentException("Source and destination cannot be empty")
                    )
                }

                val englishSource = if (languageManager.isFrench()) {
                    languageManager.translateLocationName(source)
                } else {
                    source.replace(" ", "").lowercase()
                }

                val englishDestination = if (languageManager.isFrench()) {
                    languageManager.translateLocationName(destination)
                } else {
                    destination.replace(" ", "").lowercase()
                }

                Log.d(TAG, "Translated for backend: $englishSource -> $englishDestination")

                // Update state
                val connectingMsg = languageManager.getString("Connecting to server...")

                // Update state to show initialization in progress
                _navigationState.value = _navigationState.value.copy(
                    source = source,
                    destination = destination,
                    useClockDirections = useClockDirections,
                    useLandmarks = useLandmarks,
                    currentInstruction = connectingMsg,
                    initializationStep = InitStep.NOT_STARTED,
                    errorMessage = null
                )

                // Call API to initialize navigation
                val response = navigationAPI.initialize(
                    InitializeRequest(
                        source = source,
                        destination = destination,
                        useClockDirections = useClockDirections,
                        useLandmarks = useLandmarks,
                        conversationMode = conversationMode
                    ),
                    sessionId
                )

                Log.d(TAG, "Server response: status=${response.status}, message=${response.message}")

                if (response.status == "success") {
                    val serverMessage = response.instructions ?: response.message ?: "Server connection successful"

                    val localizedMessage = if (languageManager.isFrench()) {
                        languageManager.translateFromEnglish(serverMessage)
                    } else {
                        serverMessage
                    }
                    // Store path bearings from server response
                    response.pathBearings?.let { bearings ->
                        storePathBearings(bearings)
                    }

                    val readyMsg = languageManager.getString("Server connected! Ready to start navigation.")
                    // Update state - initialized and ready for navigation
                    _navigationState.value = _navigationState.value.copy(
                        isInitialized = true,
                        serverResponse = localizedMessage,
                        currentInstruction = readyMsg,
                        initializationStep = InitStep.INITIALIZED,
                        errorMessage = null
                    )

                    // Store calibration data for later use
                    tempCalibrationData = response.calibration
                    val serverConnected = languageManager.getString("Server connected")
                    handleInstructionAnnouncement("$serverConnected. $localizedMessage")

                    Log.d(TAG, "Server initialization successful: $localizedMessage")
                    Result.success(localizedMessage)

                } else {
                    val serverFailed = languageManager.getString("Server initialization failed")
                    val errorMsg = "$serverFailed: ${response.message}"
                    _navigationState.value = _navigationState.value.copy(
                        errorMessage = errorMsg,
                        initializationStep = InitStep.ERROR
                    )
                    val connFailed = languageManager.getString("Server connection failed")
                    ttsManager.speakCritical(connFailed)

                    Log.e(TAG, errorMsg)
                    Result.failure(Exception(errorMsg))

                }

            } catch (e: Exception) {
                val networkError = languageManager.getString("Network error")
                val errorMsg = "$networkError: ${e.message}"
                _navigationState.value = _navigationState.value.copy(
                    errorMessage = errorMsg,
                    initializationStep = InitStep.ERROR
                )
                val connError = languageManager.getString("Network connection error")
                ttsManager.speakCritical(connError)

                Log.e(TAG, errorMsg, e)
                Result.failure(e)
            }
        }
    }


    /**
     * Performs calibration and starts navigation
     */
    suspend fun startNavigationWithCalibration(lifecycleOwner: LifecycleOwner): Result<String> {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "Step 2: Starting navigation with automatic calibration")

                if (!_navigationState.value.isInitialized) {
                    val errorMsg = "Must initialize with server first"
                    ttsManager.speakCritical(errorMsg)
                    return@withContext Result.failure(Exception(errorMsg))
                }

                if (tempCalibrationData == null) {
                    val errorMsg = "No calibration data available from server"
                    ttsManager.speakCritical("Calibration data missing")
                    return@withContext Result.failure(Exception(errorMsg))
                }

                // Update state to show we're starting navigation
                _navigationState.value = _navigationState.value.copy(
                    currentInstruction = "Starting navigation: calibrating sensors...",
                    errorMessage = null
                )

                // Announce start
                ttsManager.speak("Starting navigation with automatic calibration", force = true)

                // Reset position to ensure clean start
                Log.d(TAG, "Resetting sensor position for clean calibration")
                sensorManager.resetPosition()

                // Small delay to ensure reset is complete
                delay(200)

                // Perform calibration with server data
                val currentPosition = sensorManager.getCurrentPosition()
                val calibrationData = tempCalibrationData!!

                Log.d(TAG, "Performing calibration with server data")
                val calibrationSuccess = calibrationManager.calibrateWithMapPosition(
                    currentImuPosition = currentPosition,
                    mapX = calibrationData.mapStartX,
                    mapY = calibrationData.mapStartY,
                    mapBearing = calibrationData.initialBearing,
                    stepCount = sensorManager.imuState.value.stepCount
                )

                if (!calibrationSuccess) {
                    val errorMsg = "Calibration failed"
                    _navigationState.value = _navigationState.value.copy(
                        errorMessage = errorMsg,
                        initializationStep = InitStep.ERROR
                    )
                    ttsManager.speakCritical(errorMsg)
                    return@withContext Result.failure(Exception(errorMsg))
                }

                Log.d(TAG, "Calibration successful, starting navigation systems")

                // Start QR detection
                withContext(Dispatchers.Main) {
                    startQRDetection(lifecycleOwner)
                }

                // Initialize QR sync state
                resetQRSyncState()

                // Reset one-time instruction tracking for new navigation session
                ttsManager.resetOneTimeInstructions()

                // Configure QR detector
                try {
                    Log.d(TAG, "Configuring QR detector...")
                    qrDetector.enableWalkingMode()
                    qrDetector.enableRapidChangeMode()
                    qrDetector.enableNavigationMode()
                    Log.d(TAG, "QR detector configured successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "Error configuring QR detector: ${e.message}", e)
                }

                // Update final state - navigation active
                _navigationState.value = _navigationState.value.copy(
                    isNavigating = true,
                    isCalibrated = true,
                    currentInstruction = "Navigation started! Follow voice instructions.",
                    initializationStep = InitStep.NAVIGATING,
                    errorMessage = null,
                    qrDetectionActive = true,
                    qrSyncMode = "SMART_SYNC"
                )

                // Start continuous position updates
                startSmartPositionUpdates()

                // Start smart QR monitoring
                startSmartQRMonitoring()

                val successMessage = "Journey Begins!"
                ttsManager.speakPriority(successMessage)

                Log.i(TAG, "Combined navigation start completed successfully")
                Result.success(successMessage)

            } catch (e: Exception) {
                val errorMsg = "Failed to start navigation: ${e.message}"
                _navigationState.value = _navigationState.value.copy(
                    errorMessage = errorMsg,
                    initializationStep = InitStep.ERROR
                )

                ttsManager.speakCritical("Navigation start failed")
                Log.e(TAG, errorMsg, e)
                Result.failure(e)
            }
        }
    }


    /**
     * Start continuous navigation with Smart QR Sync

     */
    fun startContinuousNavigation() {
        if (!_navigationState.value.isInitialized) {
            Log.e(TAG, "Cannot start navigation - not initialized with server")
            ttsManager.speakCritical("Must initialize with server first")
            return
        }

        if (!_navigationState.value.isCalibrated) {
            Log.e(TAG, "Cannot start navigation - not calibrated")
            ttsManager.speakCritical("Must calibrate sensors first")
            return
        }

        Log.d(TAG, "Step 3: Starting navigation with Smart QR Sync")

        // Reset QR sync state
        resetQRSyncState()

        // Reset one-time instruction tracking for new navigation session
        ttsManager.resetOneTimeInstructions()

        _navigationState.value = _navigationState.value.copy(
            isNavigating = true,
            currentInstruction = "Navigation started! Smart QR Sync active!",
            initializationStep = InitStep.NAVIGATING,
            errorMessage = null,
            qrDetectionActive = true,
            qrSyncMode = "SMART_SYNC"
        )

        // Configure QR detector with DIRECT method calls
        try {
            Log.d(TAG, "Configuring QR detector with direct method calls...")

            // Direct method calls - these will work properly
            qrDetector.enableWalkingMode()
            qrDetector.enableRapidChangeMode()
            qrDetector.enableNavigationMode()

            Log.d(TAG, "QR detector configured successfully with direct calls")

        } catch (e: Exception) {
            Log.e(TAG, "Error configuring QR detector: ${e.message}", e)
        }

        // Start continuous position updates with smart QR sync
        startSmartPositionUpdates()

        // Start smart QR monitoring
        startSmartQRMonitoring()

        Log.i(TAG, "Smart QR Navigation started successfully")
    }

    /**
     * Start ML Kit QR detection for the navigation session
     *
     */
    fun startQRDetection(lifecycleOwner: LifecycleOwner) {
        navigationScope.launch {
            try {
                Log.d(TAG, "Starting QR detection with direct method call...")

                // Direct method call
                val success = qrDetector.startScanning(lifecycleOwner)

                if (success) {
                    Log.d(TAG, "ML Kit QR detection started successfully")
                    _navigationState.value = _navigationState.value.copy(
                        qrDetectionActive = true
                    )

                    // Direct method call for testing capabilities
                    qrDetector.testMLKitCapabilities()

                } else {
                    Log.w(TAG, "Failed to start ML Kit QR detection - continuing without QR correction")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error starting ML Kit QR detection: ${e.message}", e)
            }
        }
    }

    /**
     * Resume QR detection (called from activity onResume)
     */
    fun resumeQRDetection(lifecycleOwner: LifecycleOwner) {
        if (_navigationState.value.isNavigating && _navigationState.value.qrDetectionActive) {
            startQRDetection(lifecycleOwner)
        }
    }

    /**
     * SMART QR SYNCHRONIZATION LOGIC
     */

    private fun getSmartQRState(): Pair<Boolean, String?> {
        val currentTime = System.currentTimeMillis()
        val qrState = qrDetector.detectionState.value

        // Check for NEW QR detection (immediate capture)
        if (qrState.isDetected && qrState.lastQRContent != null) {
            val newQRId = QRIdExtractor.extractQRCodeId(qrState.lastQRContent)

            if (newQRId != null) {
                // Check if this is a DIFFERENT QR than what we currently have
                if (newQRId != currentQRId) {
                    Log.i(TAG, "NEW QR DETECTED: '$currentQRId' → '$newQRId'")
                    currentQRId = newQRId
                    currentQRDetectionTime = currentTime

                    // Update state immediately
                    _navigationState.value = _navigationState.value.copy(
                        currentQRId = newQRId,
                        lastQRDetectionTime = currentTime,
                        qrDetectionCount = _navigationState.value.qrDetectionCount + 1
                    )

                    // Optional: Audio feedback for QR change
                    if (currentQRId != lastSentQRId) {
                        //ttsManager.speakPriority("New QR detected: $newQRId")
                        Log.d(TAG,"New QR detected: $newQRId")
                    }

                    return Pair(true, newQRId)
                } else {
                    // Same QR - just update timestamp to keep it fresh
                    currentQRDetectionTime = currentTime
                    Log.v(TAG, "QR REFRESHED: $newQRId")
                    return Pair(true, newQRId)
                }
            }
        }

        // No immediate detection - check if we have a recent persistent QR
        if (currentQRId != null) {
            val timeSinceDetection = currentTime - currentQRDetectionTime

            if (timeSinceDetection < QR_PERSISTENCE_WINDOW) {
                Log.v(TAG, "QR PERSISTED: $currentQRId (${timeSinceDetection}ms ago)")
                return Pair(true, currentQRId)
            } else {
                Log.d(TAG, "QR EXPIRED: $currentQRId (${timeSinceDetection}ms ago)")
                currentQRId = null
                currentQRDetectionTime = 0L

                // Update state
                _navigationState.value = _navigationState.value.copy(
                    currentQRId = null
                )
            }
        }

        return Pair(false, null)
    }

    /**
     * Start smart position updates that handle both steps and QR changes
     */
    private fun startSmartPositionUpdates() {
        updateJob?.cancel()

        updateJob = navigationScope.launch {
            var retryCount = 0

            while (isActive && _navigationState.value.isNavigating) {
                try {
                    val currentStepCount = sensorManager.imuState.value.stepCount

                    // Reset lastStepCount to 0 during zero update
                    if (currentStepCount == 0) {
                        lastStepCount = 0
                    }

                    // Get smart QR state
                    val (qrDetected, qrId) = getSmartQRState()
                    val hasNewQR = qrDetected && qrId != null && qrId != lastSentQRId
                    val hasNewStep = currentStepCount > lastStepCount

                    // Send update on new step OR if we have a new QR that hasn't been sent
                    if (hasNewStep || hasNewQR) {

                        // Update step count only if it's actually a new step
                        if (hasNewStep) {
                            lastStepCount = currentStepCount
                        }

                        val currentPosition = sensorManager.getCurrentMapPosition()
                        if (currentPosition == null) {
                            delay(UPDATE_INTERVAL_MS)
                            continue
                        }

                        // Get current bearing from sensors
                        //var currentBearing = currentPosition.
                        var currentBearing = sensorManager.getLastCorrectedBearing()


                        Log.i(TAG, "SMART UPDATE: Step: $currentStepCount")
                        Log.i(TAG, "Position: (${String.format("%.2f", currentPosition.x)}, ${String.format("%.2f", currentPosition.y)})")
                        Log.i(TAG, "Bearing: ${String.format("%.1f", currentBearing)}° (already corrected in sensor)")

                        // Determine update trigger
                        val updateTrigger = when {
                            hasNewStep && hasNewQR -> "STEP + NEW_QR"
                            hasNewStep -> "NEW_STEP"
                            hasNewQR -> "NEW_QR_ONLY"
                            else -> "UNKNOWN"
                        }

                        // Enhanced debug logging
                        Log.i(TAG, "SMART UPDATE: $updateTrigger")
                        Log.i(TAG, "Step: $currentStepCount")
                        Log.i(TAG, "Position: (${String.format("%.2f", currentPosition.x)}, ${String.format("%.2f", currentPosition.y)})")
                        Log.i(TAG, "QR: detected=$qrDetected, id='$qrId'")
                        Log.i(TAG, "Last sent QR: '$lastSentQRId'")

                        if (qrDetected && qrId != null) {
                            val timeSinceDetection = System.currentTimeMillis() - currentQRDetectionTime
                            Log.i(TAG, "QR age: ${timeSinceDetection}ms")
                        }

                        // Send update to server
                        val response = try {
                            navigationAPI.updatePosition(
                                UpdateRequest(
                                    currentX = currentPosition.x,
                                    currentY = currentPosition.y,
                                    currentBearing = currentBearing, //currentPosition.bearing,
                                    qrDetected = qrDetected,
                                    qrCodeId = qrId
                                ),
                                sessionId
                            )
                        } catch (e: Exception) {
                            Log.e(TAG, "API call failed: ${e.message}")
                            throw e
                        }


                        // Extract and update current segment ID from server response
                        response.segmentInfo?.segmentIndex?.let { segmentId ->
                            updateCurrentSegmentId(segmentId)
                        }

                        // Log successful transmission
                        Log.d(TAG, "Server response: ${response.status}")
                        if (qrDetected && qrId != null) {
                            Log.i(TAG, "QR TRANSMITTED:")
                            Log.i(TAG, "Trigger: $updateTrigger")
                            Log.i(TAG, "QR ID: '$qrId'")
                            Log.i(TAG, "Response: ${response.status}")

                            // Mark this QR as sent, but keep it in currentQRId for potential refreshes
                            lastSentQRId = qrId

                            // Update state
                            _navigationState.value = _navigationState.value.copy(
                                lastSentQRId = qrId
                            )
                        }

                        // Handle segment-based recalibration
                        if (response.status == "segment_change" && response.new_map_position != null) {
                            handleSegmentRecalibration(response, "segment_change")
                        }

                        if (response.status == "segment_ending" && response.new_map_position != null) {
                            handleSegmentRecalibration(response, "segment_ending")
                        }

                        // Handle response
                        val newInstruction = response.message ?: response.instructions

                        when {
                            newInstruction != null -> {
                                val translatedInstruction = translateInstruction(newInstruction)
                                withContext(Dispatchers.Main) {
                                    val instructionText = if (qrDetected && qrId != null) {
                                        "$translatedInstruction (QR: $qrId)"
                                    } else {
                                        translatedInstruction
                                    }

                                    _navigationState.value = _navigationState.value.copy(
                                        currentInstruction = instructionText,
                                        lastUpdateTime = System.currentTimeMillis(),
                                        errorMessage = null
                                    )
                                }

                                handleInstructionAnnouncement(translatedInstruction)
                                Log.d(TAG, "Navigation update: $newInstruction")

                                // Check for destination arrival AFTER TTS announcement and stop server update
                                if (newInstruction.contains("Arrived! Destination")) {
                                    Log.i(TAG, "Destination reached - stopping navigation after announcement")
                                    _navigationState.value = _navigationState.value.copy(isNavigating = false)
                                    return@launch
                                }
                            }

                            response.status == "error" -> {
                                val errorMsg = "Server error: ${response.message ?: "Unknown error"}"
                                Log.e(TAG, errorMsg)
                                withContext(Dispatchers.Main) {
                                    _navigationState.value = _navigationState.value.copy(
                                        errorMessage = errorMsg
                                    )
                                }
                                ttsManager.speakCritical("Navigation error occurred")
                            }

                            else -> {
                                Log.w(TAG, "Received response but no message/instructions: $response")
                                withContext(Dispatchers.Main) {
                                    _navigationState.value = _navigationState.value.copy(
                                        currentInstruction = "No instruction received from server"
                                    )
                                }
                            }
                        }
                    }

                    retryCount = 0

                } catch (e: Exception) {
                    retryCount++
                    Log.e(TAG, "Position update failed (attempt $retryCount): ${e.message}")

                    if (retryCount >= MAX_RETRY_ATTEMPTS) {
                        val errorMsg = "Connection lost after $retryCount attempts"
                        withContext(Dispatchers.Main) {
                            _navigationState.value = _navigationState.value.copy(
                                errorMessage = errorMsg
                            )
                        }
                        ttsManager.speakCritical("Connection lost")
                        retryCount = 0
                        delay(RETRY_DELAY_MS * 2)
                    } else {
                        delay(RETRY_DELAY_MS)
                    }
                }

                delay(UPDATE_INTERVAL_MS)
            }
        }
    }

    /**
     * Start smart QR monitoring with change detection
     */
    private fun startSmartQRMonitoring() {
        qrMonitoringJob?.cancel()

        qrMonitoringJob = navigationScope.launch {
            qrDetector.detectionState.collect { qrState ->
                if (qrState.isDetected && _navigationState.value.isNavigating) {
                    val currentTime = System.currentTimeMillis()
                    val numericId = QRIdExtractor.extractQRCodeId(qrState.lastQRContent)

                    if (numericId != null) {
                        // Check if this is a NEW QR (different from current)
                        val isNewQR = numericId != currentQRId

                        if (isNewQR) {
                            Log.i(TAG, "QR CHANGE DETECTED:")
                            Log.i(TAG, "OLD: '$currentQRId'")
                            Log.i(TAG, "NEW: '$numericId'")
                            Log.i(TAG, "Will trigger smart update")

                            // The smart update will be handled by getSmartQRState() in the update loop

                        } else {
                            // Same QR - just refresh the timestamp
                            currentQRDetectionTime = currentTime
                            Log.v(TAG, "QR REFRESHED: $numericId")
                        }
                    } else {
                        Log.w(TAG, "QR detected but no valid numeric ID: ${qrState.lastQRContent}")
                    }
                }
            }
        }
    }


    /**
     * Handle TTS announcements (instruction already translated)
     */
    private fun handleInstructionAnnouncement(translatedInstruction: String) {
        val lowerInstruction = translatedInstruction.lowercase().trim()

        val skipPhrases = listOf(
            "no value return",
            "you are on track",
            "pas de valeur de retour",
            "Aucune valeur de retour",
            "valeur de retour",
            "on track",
            "vous êtes sur la bonne voie",
            "sur la bonne voie"
        )

        if (skipPhrases.any { lowerInstruction.contains(it) } || translatedInstruction.isBlank()) {
            Log.d(TAG, "Filtered unwanted phrase: $translatedInstruction")
            return
        }

        Log.d(TAG, "Speaking instruction: $translatedInstruction")
        ttsManager.speak(translatedInstruction)
    }

    /**
     * Determine if a regular instruction should be announced via TTS
     */
    private fun shouldAnnounceInstruction(instruction: String): Boolean {
        val currentState = _navigationState.value

        // Don't announce if same as current instruction
        if (instruction == currentState.currentInstruction) {
            return false
        }

        // Only announce if it contains important non-priority keywords
        val regularImportantKeywords = listOf(
            "continue", "maintain", "proceed"
        )

        return regularImportantKeywords.any { keyword ->
            instruction.lowercase().contains(keyword)
        }
    }

    /**
     * Handle segment recalibration
     */
    private suspend fun handleSegmentRecalibration(response: NavigationResponse, reason: String = "segment_change") {
        try {
            val newMapPosition = response.new_map_position
            if (newMapPosition == null || newMapPosition.size < 2) {
                Log.w(TAG, "Invalid new_map_position received: $newMapPosition")
                return
            }

            val mapX = newMapPosition[0]
            val mapY = newMapPosition[1]

            val mapBearing = when (reason) {
                "segment_ending" -> {
                    val currentMapPosition = sensorManager.getCurrentMapPosition()
                    val preservedBearing = currentMapPosition?.bearing
                    Log.d(TAG, "Segment ending: will preserve current bearing: ${preservedBearing}°")
                    preservedBearing
                }
                "segment_change" -> {
                    //if (newMapPosition.size >= 3) newMapPosition[2] else null
                    val currentMapPosition = sensorManager.getCurrentMapPosition()
                    currentMapPosition?.bearing
                }
                else -> {
                    val currentMapPosition = sensorManager.getCurrentMapPosition()
                    currentMapPosition?.bearing
                }
            }

            val reasonText = when (reason) {
                "segment_change" -> "Segment transition"
                "segment_ending" -> "Segment ending"
                else -> "Position update"
            }

            val bearingText = when (reason) {
                "segment_ending" -> "preserving current bearing ${mapBearing}°"
                else -> if (mapBearing != null) "with new bearing ${mapBearing}°" else "without bearing"
            }
            Log.d(TAG, "$reasonText detected - recalibrating to map position: ($mapX, $mapY) $bearingText")

            // Reset IMU position to origin for fresh start
            Log.d(TAG, "Resetting IMU position to origin")
            sensorManager.resetPosition()

            delay(100)

            val resetImuPosition = sensorManager.getCurrentPosition()
            Log.d(TAG, "Reset IMU position: (${resetImuPosition.x}, ${resetImuPosition.y})")

            // Perform recalibration with new map position
            val success = calibrationManager.calibrateWithMapPosition(
                currentImuPosition = resetImuPosition,
                mapX = mapX,
                mapY = mapY,
                mapBearing = mapBearing,
                stepCount = sensorManager.imuState.value.stepCount
            )

            if (success) {

                val calibrationType = when (reason) {
                    "segment_ending" -> "position only, bearing preserved"
                    "segment_change" -> "position + bearing"
                    else -> "full recalibration"
                }
                Log.d(TAG, "$reasonText recalibration successful ($calibrationType)")

                withContext(Dispatchers.Main) {
                    _navigationState.value = _navigationState.value.copy(
                        currentInstruction = "${response.message} (Position recalibrated - $reasonText)",
                        lastUpdateTime = System.currentTimeMillis()
                    )
                }

            } else {
                Log.e(TAG, "$reasonText recalibration failed")

                withContext(Dispatchers.Main) {
                    _navigationState.value = _navigationState.value.copy(
                        errorMessage = "$reasonText recalibration failed, continuing with current calibration"
                    )
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error during $reason recalibration: ${e.message}", e)

            withContext(Dispatchers.Main) {
                _navigationState.value = _navigationState.value.copy(
                    errorMessage = "Recalibration error: ${e.message}"
                )
            }
        }
    }

    /**
     * Force a position update (useful for testing)
     */
    suspend fun forcePositionUpdate(): Result<String> {
        return withContext(Dispatchers.IO) {
            try {
                val currentPosition = sensorManager.getCurrentMapPosition()
                    ?: return@withContext Result.failure(Exception("No calibrated position available"))

                val (qrDetected, qrId) = getSmartQRState()

                Log.d(TAG, "FORCING SMART UPDATE:")
                Log.d(TAG, "QR detected: $qrDetected")
                Log.d(TAG, "QR ID: $qrId")

                val response = navigationAPI.updatePosition(
                    UpdateRequest(
                        currentX = currentPosition.x,
                        currentY = currentPosition.y,
                        currentBearing = currentPosition.bearing,
                        qrDetected = qrDetected,
                        qrCodeId = qrId
                    ),
                    sessionId
                )

                response.message?.let { instruction ->
                    _navigationState.value = _navigationState.value.copy(
                        currentInstruction = instruction,
                        lastUpdateTime = System.currentTimeMillis()
                    )

                    handleInstructionAnnouncement(instruction)

                    Result.success(instruction)
                } ?: Result.failure(Exception("No instruction received"))

            } catch (e: Exception) {
                Log.e(TAG, "Force update failed: ${e.message}")
                Result.failure(e)
            }
        }
    }

    /**
     * Reset QR synchronization state
     */
    private fun resetQRSyncState() {
        currentQRId = null
        currentQRDetectionTime = 0L
        lastSentQRId = null

        _navigationState.value = _navigationState.value.copy(
            currentQRId = null,
            lastSentQRId = null,
            qrDetectionCount = 0,
            lastQRDetectionTime = 0L
        )

        Log.d(TAG, "QR sync state reset")
    }

    /**
     * Stop navigation and reset all states
     */
    fun stopNavigation() {
        Log.d(TAG, "Stopping navigation")

        updateJob?.cancel()
        updateJob = null

        qrMonitoringJob?.cancel()
        qrMonitoringJob = null

        // Stop ML Kit QR detection
        qrDetector.stopScanning()

        // Reset QR sync state
        resetQRSyncState()

        _navigationState.value = _navigationState.value.copy(
            isNavigating = false,
            isInitialized = false,
            isCalibrated = false,
            currentInstruction = "Navigation stopped",
            initializationStep = InitStep.NOT_STARTED,
            errorMessage = null,
            qrDetectionActive = false,
            qrSyncMode = "DISABLED"
        )

        ttsManager.speakPriority("Navigation stopped")

        // Reset sensors and calibration
        sensorManager.resetPosition()
        calibrationManager.resetCalibration()
        tempCalibrationData = null
    }



    /**
     * Get comprehensive smart QR state information (fixed return types)
     */
    fun getSmartQRInfo(): Map<String, Any> {
        val qrState = qrDetector.detectionState.value
        val (smartDetected, smartId) = getSmartQRState()
        val currentTime = System.currentTimeMillis()

        return mapOf(
            // Instant camera state
            "cameraDetected" to qrState.isDetected,
            "cameraContent" to (qrState.lastQRContent ?: "None"),

            // Smart persistent state
            "smartDetected" to smartDetected,
            "smartId" to (smartId ?: "None"),
            "currentQRId" to (currentQRId ?: "None"),
            "lastSentQRId" to (lastSentQRId ?: "None"),

            // Timing information
            "qrAge" to if (currentQRDetectionTime > 0) {
                "${currentTime - currentQRDetectionTime}ms"
            } else "N/A",
            "hasNewQR" to (smartDetected && smartId != null && smartId != lastSentQRId),

            // Configuration
            "persistenceWindow" to "${QR_PERSISTENCE_WINDOW}ms",
            "changeDetectionWindow" to "${QR_CHANGE_DETECTION_WINDOW}ms",

            // Status
            "updateTriggers" to "NEW_STEP or NEW_QR",
            "syncStrategy" to "IMMEDIATE_CAPTURE + SMART_PERSISTENCE",
            "detectionCount" to _navigationState.value.qrDetectionCount,
            "syncMode" to _navigationState.value.qrSyncMode,

            // Statistics
            "navigationActive" to _navigationState.value.isNavigating,
            "qrDetectionActive" to _navigationState.value.qrDetectionActive,
            "lastUpdateTime" to _navigationState.value.lastUpdateTime
        )
    }

    /**
     * Test rapid QR changes simulation
     */
    fun testRapidQRChanges() {
        Log.d(TAG, "=== TESTING RAPID QR CHANGES ===")

        navigationScope.launch {
            // Simulate rapid QR detections
            val testQRs = listOf("QR001", "QR002", "QR003", "QR001", "QR004")

            testQRs.forEachIndexed { index, qrId ->
                Log.d(TAG, "Simulating QR detection $index: $qrId")

                // Simulate the detection by temporarily setting state

                currentQRId = qrId
                currentQRDetectionTime = System.currentTimeMillis()

                delay(150) // 150ms between detections

                val (detected, id) = getSmartQRState()
                Log.d(TAG, "Smart state: detected=$detected, id='$id', lastSent='$lastSentQRId'")

                if (detected && id != null && id != lastSentQRId) {
                    Log.d(TAG, "Would trigger update for: $id")
                    // In real scenario, this would trigger the update in the main loop
                    lastSentQRId = id // Simulate sending
                } else {
                    Log.d(TAG, "No update needed")
                }
            }

            Log.d(TAG, "=== RAPID QR TEST COMPLETE ===")
        }
    }

    /**
     * Get bearing correction information for debugging
     */
    fun getBearingCorrectionInfo(): Map<String, Any> {
        val currentState = _navigationState.value
        return mapOf(
            "pathBearingsCount" to pathBearings.size,
            "currentSegmentId" to currentSegmentId,
            "trueBearing" to (currentState.trueBearing ?: "None"),
            "bearingCorrectionApplied" to currentState.bearingCorrectionApplied,
            "bearingCorrectionCount" to currentState.bearingCorrectionCount,
            "bearingThreshold" to BEARING_CORRECTION_THRESHOLD,
            "pathBearings" to pathBearings.take(10) // Show first 10 for debugging
        )
    }



    /**
     * Get comprehensive navigation summary with bearing correction info
     */
    fun getNavigationSummary(): Map<String, Any> {
        val state = _navigationState.value
        val currentPosition = sensorManager.getCurrentPosition()
        val mapPosition = sensorManager.getCurrentMapPosition()
        val sensorBearingStats = sensorManager.getBearingCorrectionStats()

        val qrStats = try {
            qrDetector.getDetectionStats()
        } catch (e: Exception) {
            emptyMap()
        }
        val smartQRInfo = getSmartQRInfo()
        val bearingCorrectionInfo = getBearingCorrectionInfo()

        return mapOf(
            "isNavigating" to state.isNavigating,
            "isInitialized" to state.isInitialized,
            "instruction" to state.currentInstruction,
            "route" to "${state.source} → ${state.destination}",
            "imuPosition" to "(${String.format("%.2f", currentPosition.x)}, ${String.format("%.2f", currentPosition.y)})",
            "mapPosition" to if (mapPosition != null) "(${String.format("%.2f", mapPosition.x)}, ${String.format("%.2f", mapPosition.y)})" else "Not calibrated",
            "bearing" to "${String.format("%.1f", currentPosition.bearing)}°",
            "lastUpdate" to if (state.lastUpdateTime > 0) {
                "${(System.currentTimeMillis() - state.lastUpdateTime) / 1000}s ago"
            } else "Never",
            "ttsStatus" to ttsManager.getStatus(),
            "qrDetectionActive" to state.qrDetectionActive,
            "currentQRId" to (state.currentQRId ?: "None"),
            "lastSentQRId" to (state.lastSentQRId ?: "None"),
            "qrDetectionCount" to state.qrDetectionCount,
            "qrEngine" to "ML_KIT",
            "qrSyncMode" to state.qrSyncMode,
            "qrStats" to qrStats,
            "smartQRInfo" to smartQRInfo,
            "bearingCorrectionInfo" to bearingCorrectionInfo,
            "currentSegmentId" to state.currentSegmentId,
            "sensorBearingCorrection" to sensorBearingStats,
            "updateMode" to "BEARING_CORRECTED_AT_STEP_CALCULATION"
        )
    }


    fun testQRDetection() {
        Log.d(TAG, "Testing ML Kit QR detection system with Smart Sync")

        val qrStats = try {
            // FIXED: Direct method call instead of reflection
            qrDetector.getDetectionStats()
        } catch (e: Exception) {
            emptyMap()
        }
        Log.d(TAG, "ML Kit QR Stats: $qrStats")

        // FIXED: Direct method call for testing capabilities
        qrDetector.testMLKitCapabilities()

        val smartQRInfo = getSmartQRInfo()
        Log.d(TAG, "Smart QR Info: $smartQRInfo")

        // Test rapid changes
        testRapidQRChanges()
    }
    /**
     * Translate instruction if needed (single point of translation)
     */
    private suspend fun translateInstruction(englishInstruction: String): String {
        return if (languageManager.isFrench()) {
            try {
                languageManager.translateFromEnglish(englishInstruction)
            } catch (e: Exception) {
                Log.e(TAG, "Translation failed: ${e.message}")
                englishInstruction // Fallback to English
            }
        } else {
            englishInstruction
        }
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        Log.d(TAG, "Cleaning up navigation manager with Smart QR Sync")
        updateJob?.cancel()
        qrMonitoringJob?.cancel()
        qrDetector.cleanup()
        resetQRSyncState()
        navigationScope.cancel()
    }
}

// Data classes for API communication

data class InitializeRequest(
    val action: String = "initialize",
    val source: String,
    val destination: String,
    val useClockDirections: Boolean = false,
    val useLandmarks: Boolean = false,
    val conversationMode: Boolean = false
)

data class UpdateRequest(
    val action: String = "update",
    val currentX: Double,
    val currentY: Double,
    val currentBearing: Double,
    val qrDetected: Boolean = false,
    val qrCodeId: String? = null
)

data class NavigationResponse(
    val status: String,
    val message: String? = null,
    val instructions: String? = null,
    val navigationStarted: Boolean? = null,
    val pathCoordinates: List<List<Double>>? = null,
    val pathBearings: List<Double>? = null,
    val calibration: CalibrationData? = null,
    val waypoint: List<Double>? = null,
    val distance_passed: Double? = null,
    val return_turn: String? = null,
    val return_angle: Double? = null,
    val correct_turn: String? = null,
    val correct_angle: Double? = null,
    val deviation_type: String? = null,
    val correction_point: List<Double>? = null,
    val new_map_position: List<Double>? = null,
    val conversation_mode: Boolean? = null,
    val conversation_data: Any? = null,
    val segmentInfo: SegmentInfo? = null
)

data class CalibrationData(
    val mapStartX: Double,
    val mapStartY: Double,
    val initialBearing: Double? = null
)

data class SegmentInfo(
    val segmentIndex: Int,
    val isSignificantTurn: Boolean? = null
)