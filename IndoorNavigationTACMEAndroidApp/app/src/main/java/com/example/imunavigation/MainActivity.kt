// MainActivity.kt - Updated with Separate APIs
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
import com.example.imunavigation.conversation.OpenAIAPI
import com.example.imunavigation.navigation.NavigationManager
import com.example.imunavigation.sensors.IMUSensorManager
import com.example.imunavigation.tts.TTSManager
import com.example.imunavigation.qr.QRCodeDetector
import com.example.imunavigation.screens.NavigationScreen
import com.example.imunavigation.ui.theme.IMUNavigationTheme
import com.example.imunavigation.utils.POIExtractor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import com.example.imunavigation.language.LanguageManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
/**
 * Main Activity - Enhanced with AI Conversation Support
 */
@androidx.camera.core.ExperimentalGetImage
class MainActivity : ComponentActivity() {

    // Initialize Managers
    private lateinit var calibrationManager: IMUCalibrationManager
    private lateinit var sensorManager: IMUSensorManager
    private lateinit var ttsManager: TTSManager
    private lateinit var navigationManager: NavigationManager
    private lateinit var qrDetector: QRCodeDetector
    private lateinit var conversationManager: ConversationManager
    private lateinit var languageManager: LanguageManager
    private var poiNames: List<String> = emptyList()

    // API setup
    private val navigationRetrofit by lazy {
        Retrofit.Builder()
            .baseUrl("https://indoornavigationtacme-production.up.railway.app")// 172.28.48.1//http://192.168.2.11:5000/https://indoornavigationtacme-production.up.railway.app/("https://jennet-crisp-molly.ngrok-free.app/") // "http://192.168.2.11:5000/"Your navigation server
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private val openAIRetrofit by lazy {
        Retrofit.Builder()
            .baseUrl("https://api.openai.com/") // OpenAI API base URL
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    private val navigationAPI by lazy {
        navigationRetrofit.create(NavigationAPI::class.java)
    }

    private val openAIAPI by lazy {
        openAIRetrofit.create(OpenAIAPI::class.java)
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
                    conversationManager = conversationManager ,
                    languageManager = languageManager,
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

            languageManager = LanguageManager(
                context = this,
                openAIAPI = openAIAPI,
                apiKey = BuildConfig.OPENAI_API_KEY
            )

            Log.d(TAG, "Language manager initialized with OpenAI")


            navigationManager = NavigationManager(
                navigationAPI = navigationAPI,
                calibrationManager = calibrationManager,
                sensorManager = sensorManager,
                ttsManager = ttsManager,
                qrDetector = qrDetector,
                languageManager = languageManager
            )


            conversationManager = ConversationManager(
                context = this,
                navigationAPI = navigationAPI,
                openAIAPI = openAIAPI,
                ttsManager = ttsManager,
                languageManager = languageManager,
                apiKey = BuildConfig.OPENAI_API_KEY
                //availablePOIs = poiNames
            )
            ttsManager.setLanguageManager(languageManager)

            // Preload common phrases in background
            CoroutineScope(Dispatchers.IO).launch {
                languageManager.preloadCommonPhrases()
            }

            Log.d(TAG, "All managers initialized with bilingual support")


            Log.d("API_KEY_CHECK", "Key loaded: ${BuildConfig.OPENAI_API_KEY.take(10)}...")
            Log.d("API_KEY_CHECK", "Key length: ${BuildConfig.OPENAI_API_KEY.length}")

            Log.d(TAG, "All managers including AI conversation initialized successfully")

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

                initializeSensors()
                initializeQRDetector()
                initializeConversationManager()
            }
            permissionsToRequest.any { shouldShowRequestPermissionRationale(it) } -> {

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
     * Initialize conversation manager
     */
    private fun initializeConversationManager() {
        try {

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

        //Show diagnostic info
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


        if (::sensorManager.isInitialized) {
            try {
                sensorManager.stop()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause sensors: ${e.message}")
            }
        }


        if (::qrDetector.isInitialized) {
            try {
                qrDetector.stopScanning()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to pause QR detection: ${e.message}")
            }
        }


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

            if (::languageManager.isInitialized) {
                languageManager.clearCache()
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
}