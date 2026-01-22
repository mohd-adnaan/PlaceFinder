/* MainActivity.kt - Updated with Proper Timeouts for Remote Ollama
package com.example.imunavigation

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.example.imunavigation.api.NavigationAPI
import com.example.imunavigation.calibration.IMUCalibrationManager
import com.example.imunavigation.conversation.ConversationManager
import com.example.imunavigation.conversation.OllamaAPI
import com.example.imunavigation.navigation.NavigationManager
import com.example.imunavigation.sensors.IMUSensorManager
import com.example.imunavigation.tts.TTSManager
import com.example.imunavigation.qr.QRCodeDetector
import com.example.imunavigation.screens.NavigationScreen
import com.example.imunavigation.ui.theme.IMUNavigationTheme
import com.example.imunavigation.utils.POIExtractor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit

/**
 * Main Activity - Enhanced with AI Conversation Support
 */
@androidx.camera.core.ExperimentalGetImage
class MainActivity : ComponentActivity() {

    // Managers - initialized in onCreate
    private lateinit var calibrationManager: IMUCalibrationManager
    private lateinit var sensorManager: IMUSensorManager
    private lateinit var ttsManager: TTSManager
    private lateinit var navigationManager: NavigationManager
    private lateinit var qrDetector: QRCodeDetector
    private lateinit var conversationManager: ConversationManager
    private var poiNames: List<String> = emptyList()

    // OkHttp client for Navigation API (short timeouts)
    private val navigationHttpClient by lazy {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }

        OkHttpClient.Builder()
            .addInterceptor(loggingInterceptor)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()
    }

    // OkHttp client for Ollama API (LONG timeouts for remote server)
    private val ollamaHttpClient by lazy {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BODY
        }

        OkHttpClient.Builder()
            .addInterceptor(loggingInterceptor)
            // Extended timeouts for remote Ollama server and LLM inference
            .connectTimeout(30, TimeUnit.SECONDS)      // Time to connect to remote server
            .readTimeout(120, TimeUnit.SECONDS)        // CRITICAL: Time to wait for LLM response
            .writeTimeout(30, TimeUnit.SECONDS)        // Time to send request
            .callTimeout(150, TimeUnit.SECONDS)        // Total time for entire call
            .build()
    }

    // API setup - Separate APIs for different services with proper timeouts
    private val navigationRetrofit by lazy {
        Retrofit.Builder()
            .baseUrl("http://192.168.2.11:5000/")  // Your navigation server
            .client(navigationHttpClient)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private val ollamaRetrofit by lazy {
        Retrofit.Builder()
            .baseUrl("https://ollama.pegasus.cim.mcgill.ca/")  // Remote Ollama serverhttps://ollama.pegasus.cim.mcgill.ca https://ollama.martian.cim.mcgill.ca/
            .client(ollamaHttpClient)  // CRITICAL: Use client with long timeouts
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private val navigationAPI by lazy {
        navigationRetrofit.create(NavigationAPI::class.java)
    }

    private val ollamaAPI by lazy {
        ollamaRetrofit.create(OllamaAPI::class.java)
    }

    // Enhanced permission handling for microphone, camera, and sensors
    private val requestMultiplePermissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val sensorsGranted = permissions[Manifest.permission.BODY_SENSORS] ?: false
        val cameraGranted = permissions[Manifest.permission.CAMERA] ?: false
        val microphoneGranted = permissions[Manifest.permission.RECORD_AUDIO] ?: false

        when {
            sensorsGranted && cameraGranted && microphoneGranted -> {
                Log.d(TAG, "All permissions granted - full functionality enabled")
                initializeSensors()
                initializeQRDetector()
                initializeConversationManager()
            }
            sensorsGranted && cameraGranted -> {
                Log.w(TAG, "Sensors and camera granted but microphone denied - voice input disabled")
                initializeSensors()
                initializeQRDetector()
                initializeConversationManager()
                showError("Microphone permission denied - voice input disabled, text chat still available")
            }
            sensorsGranted && microphoneGranted -> {
                Log.w(TAG, "Sensors and microphone granted but camera denied - QR detection disabled")
                initializeSensors()
                initializeConversationManager()
                showError("Camera permission denied - QR drift correction disabled")
            }
            sensorsGranted -> {
                Log.w(TAG, "Only sensors granted")
                initializeSensors()
                initializeConversationManager()
                showError("Camera and microphone permissions denied - limited functionality")
            }
            else -> {
                Log.e(TAG, "Critical permissions denied")
                showError("Sensor permissions are required for navigation")
            }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
        private val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.BODY_SENSORS,
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(TAG, "Creating MainActivity with AI Conversation Support")

        // Initialize managers
        loadPOINames()
        initializeManagers()

        // Check and request permissions
        checkPermissions()

        // Set up UI
        setContent {
            IMUNavigationTheme {
                NavigationScreen(
                    navigationManager = navigationManager,
                    sensorManager = sensorManager,
                    calibrationManager = calibrationManager,
                    ttsManager = ttsManager,
                    qrDetector = qrDetector,
                    conversationManager = conversationManager,
                    poiNames = poiNames
                )
            }
        }

        Log.d(TAG, "MainActivity created successfully with AI conversation support")
    }

    /**
     * Initialize all manager instances including conversation manager
     */
    private fun initializeManagers() {
        try {
            // Order matters - some managers depend on others
            calibrationManager = IMUCalibrationManager()
            sensorManager = IMUSensorManager(this, calibrationManager)
            calibrationManager.setSensorManager(sensorManager)
            ttsManager = TTSManager(this)
            qrDetector = QRCodeDetector(this)

            // NavigationManager with QR detector
            navigationManager = NavigationManager(
                navigationAPI = navigationAPI,
                calibrationManager = calibrationManager,
                sensorManager = sensorManager,
                ttsManager = ttsManager,
                qrDetector = qrDetector
            )

            // ConversationManager with separate APIs - with timeout configuration
            conversationManager = ConversationManager(
                context = this,
                navigationAPI = navigationAPI,
                ollamaAPI = ollamaAPI,
                ttsManager = ttsManager,
                apiKey = BuildConfig.OLLAMA_API_KEY
            )

            Log.d(TAG, "All managers including AI conversation initialized successfully")
            Log.d(TAG, "Ollama endpoint: https://ollama.martian.cim.mcgill.ca/")
            Log.d(TAG, "Navigation endpoint: http://192.168.2.11:5000/")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize managers: ${e.message}", e)
            showError("Failed to initialize navigation system: ${e.message}")
        }
    }

    /**
     * Check and request necessary permissions (sensors + camera + microphone)
     */
    private fun checkPermissions() {
        val permissionsToRequest = mutableListOf<String>()

        // Check each required permission
        for (permission in REQUIRED_PERMISSIONS) {
            if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(permission)
            }
        }

        when {
            permissionsToRequest.isEmpty() -> {
                // All permissions already granted
                initializeSensors()
                initializeQRDetector()
                initializeConversationManager()
            }
            permissionsToRequest.any { shouldShowRequestPermissionRationale(it) } -> {
                // Show explanation and request permissions
                showPermissionRationale(permissionsToRequest)
            }
            else -> {
                // Request permissions directly
                requestMultiplePermissions.launch(permissionsToRequest.toTypedArray())
            }
        }
    }

    /**
     * Initialize sensor systems after permissions are granted
     */
    private fun initializeSensors() {
        try {
            val success = sensorManager.initialize()
            if (success) {
                Log.d(TAG, "Sensors initialized successfully")
            } else {
                showError("Failed to initialize sensors - some sensors may not be available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Sensor initialization failed: ${e.message}", e)
            showError("Sensor initialization failed: ${e.message}")
        }
    }

    /**
     * Initialize QR detector
     */
    private fun initializeQRDetector() {
        try {
            // Configure QR detector for rapid change detection
            qrDetector.enableRapidChangeMode()
            qrDetector.enableNavigationMode()
            qrDetector.enableWalkingMode()

            Log.d(TAG, "QR detector ready with smart sync capabilities")

        } catch (e: Exception) {
            Log.e(TAG, "QR detector initialization failed: ${e.message}", e)
            showError("QR detector initialization failed: ${e.message}")
        }
    }

    /**
     * Initialize conversation manager - NEW
     */
    private fun initializeConversationManager() {
        try {
            // Conversation manager is ready to use
            Log.d(TAG, "AI Conversation manager ready")
            Toast.makeText(this, "Navigation system ready with AI Chat", Toast.LENGTH_SHORT).show()

        } catch (e: Exception) {
            Log.e(TAG, "Conversation manager initialization failed: ${e.message}", e)
            showError("AI conversation initialization failed: ${e.message}")
        }
    }

    /**
     * Show permission rationale to user with enhanced explanation
     */
    private fun showPermissionRationale(permissionsToRequest: List<String>) {
        val message = buildString {
            append("This app needs the following permissions for full functionality:\n\n")
            if (permissionsToRequest.contains(Manifest.permission.BODY_SENSORS)) {
                append("• Sensors: For tracking your movement and orientation\n")
            }
            if (permissionsToRequest.contains(Manifest.permission.CAMERA)) {
                append("• Camera: For QR code detection to prevent drift\n")
            }
            if (permissionsToRequest.contains(Manifest.permission.RECORD_AUDIO)) {
                append("• Microphone: For voice-based navigation questions\n")
            }
            append("\nAI Chat allows you to ask natural language questions about navigation, ")
            append("get directions, and receive personalized assistance.")
        }

        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("AI Navigation Permissions")
            .setMessage(message)
            .setPositiveButton("Grant Permissions") { _, _ ->
                requestMultiplePermissions.launch(permissionsToRequest.toTypedArray())
            }
            .setNegativeButton("Cancel") { dialog, _ ->
                dialog.dismiss()
                showError("Some permissions denied - limited functionality available")
            }
            .show()
    }

    private fun loadPOINames() {
        poiNames = POIExtractor.extractPOINames(this)
        Log.d(TAG, "Loaded ${poiNames.size} POI names from GeoJSON")

        // Optional: Show diagnostic info
        if (poiNames.isEmpty()) {
            val diagnostic = POIExtractor.getDiagnosticInfo(this)
            Log.w(TAG, "No POIs found. Diagnostic info:\n$diagnostic")
        }
    }

    /**
     * Show error message to user
     */
    private fun showError(message: String) {
        Log.e(TAG, "Error: $message")
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "Resuming MainActivity with AI conversation")

        // Restart sensors if they were initialized
        if (::sensorManager.isInitialized) {
            try {
                sensorManager.initialize()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resume sensors: ${e.message}")
            }
        }

        // Resume QR detection if navigation is active
        if (::navigationManager.isInitialized &&
            navigationManager.navigationState.value.isNavigating) {
            try {
                navigationManager.resumeQRDetection(this)
                Log.d(TAG, "QR detection resumed")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resume QR detection: ${e.message}")
            }
        }
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "Pausing MainActivity")

        // Stop sensors to save battery
        if (::sensorManager.isInitialized) {
            try {
                sensorManager.stop()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause sensors: ${e.message}")
            }
        }

        // Pause QR detection to save battery
        if (::qrDetector.isInitialized) {
            try {
                qrDetector.stopScanning()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause QR detection: ${e.message}")
            }
        }

        // Stop conversation listening to save battery
        if (::conversationManager.isInitialized) {
            try {
                conversationManager.stopListening()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause conversation: ${e.message}")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Destroying MainActivity")

        // Cleanup all resources
        try {
            if (::navigationManager.isInitialized) {
                navigationManager.cleanup()
            }

            if (::sensorManager.isInitialized) {
                sensorManager.stop()
            }

            if (::ttsManager.isInitialized) {
                ttsManager.cleanup()
            }

            if (::qrDetector.isInitialized) {
                qrDetector.cleanup()
            }

            if (::conversationManager.isInitialized) {
                conversationManager.cleanup()
            }

            Log.d(TAG, "AI conversation cleanup completed successfully")

        } catch (e: Exception) {
            Log.e(TAG, "Error during cleanup: ${e.message}", e)
        }
    }

    /**
     * Handle back button press with navigation awareness
     */
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (::navigationManager.isInitialized &&
            navigationManager.navigationState.value.isNavigating
        ) {

            // Show confirmation dialog if navigation is active
            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("Stop AI Navigation?")
                .setMessage("Navigation with AI assistance is currently active. Do you want to stop it and exit?")
                .setPositiveButton("Stop & Exit") { _, _ ->
                    navigationManager.stopNavigation()
                    if (::conversationManager.isInitialized) {
                        conversationManager.stopConversationMode()
                    }
                    @Suppress("DEPRECATION")
                    super.onBackPressed()
                }
                .setNegativeButton("Continue Navigation", null)
                .show()
        } else {
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }
}*/