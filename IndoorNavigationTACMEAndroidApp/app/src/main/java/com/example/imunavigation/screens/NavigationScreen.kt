// NavigationScreen.kt
package com.example.imunavigation.screens

import androidx.camera.core.ExperimentalGetImage
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.imunavigation.calibration.IMUCalibrationManager
import com.example.imunavigation.conversation.ConversationManager
import com.example.imunavigation.conversation.ConversationCard
import com.example.imunavigation.navigation.NavigationManager
import com.example.imunavigation.sensors.IMUSensorManager
import com.example.imunavigation.tts.TTSManager
import com.example.imunavigation.qr.QRCodeDetector
import kotlinx.coroutines.launch
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import kotlinx.coroutines.delay
import com.example.imunavigation.ui.components.Autocomplete
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedWriter
import java.io.FileWriter
import com.example.imunavigation.language.LanguageManager

@Composable
fun DoubleTapDetector(
    onDoubleTap: () -> Unit,
    content: @Composable () -> Unit
) {
    val hapticFeedback = LocalHapticFeedback.current
    var lastTapTime by remember { mutableStateOf(0L) }
    var tapCount by remember { mutableStateOf(0) }
    val multiTapTimeout = 500L

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = {
                        val currentTime = System.currentTimeMillis()
                        val timeSinceLastTap = currentTime - lastTapTime


                        if (timeSinceLastTap < multiTapTimeout) {
                            tapCount++

                            if (tapCount in 2..4) {  // Accept 2-4 taps instead of just 2
                                hapticFeedback.performHapticFeedback(HapticFeedbackType.LongPress)
                                onDoubleTap()

                                tapCount = 0
                                lastTapTime = 0L
                            } else if (tapCount > 4) {
                                tapCount = 0
                                lastTapTime = 0L
                            }
                        } else {

                            tapCount = 1
                            lastTapTime = currentTime
                        }
                    }
                )
            }
    ) {
        content()
    }
}

@androidx.annotation.OptIn(ExperimentalGetImage::class)
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NavigationScreen(
    navigationManager: NavigationManager,
    sensorManager: IMUSensorManager,
    calibrationManager: IMUCalibrationManager,
    ttsManager: TTSManager,
    qrDetector: QRCodeDetector,
    conversationManager: ConversationManager,
    languageManager: LanguageManager,
    poiNames: List<String> = emptyList()
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    // Collect state from all managers
    val navigationState by navigationManager.navigationState.collectAsState()
    val imuState by sensorManager.imuState.collectAsState()
    val ttsState by ttsManager.ttsState.collectAsState()
    val qrDetectionState by qrDetector.detectionState.collectAsState()
    val conversationState by conversationManager.conversationState.collectAsState()

    // Local UI state
    var source by remember { mutableStateOf("") }
    var destination by remember { mutableStateOf("") }
    var useClockDirections by remember { mutableStateOf(false) }
    var useLandmarks by remember { mutableStateOf(false) }
    var showAdvancedInfo by remember { mutableStateOf(false) }


    var showDoubleTapFeedback by remember { mutableStateOf(false) }

    // Function to handle voice input activation
    val activateVoiceInput: () -> Unit = {
        if (conversationState.isActive) {
            if (conversationState.isListening) {
                conversationManager.stopListening()
                android.widget.Toast.makeText(
                    context,
                    "Voice input stopped",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            } else {
                conversationManager.startListening()
                android.widget.Toast.makeText(
                    context,
                    "Voice input activated by double-tap",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            }

            // Show visual feedback
            showDoubleTapFeedback = true
            scope.launch {
                delay(2000)
                showDoubleTapFeedback = false
            }
        } else {
            android.widget.Toast.makeText(
                context,
                "Enable AI Chat first to use voice input",
                android.widget.Toast.LENGTH_SHORT
            ).show()
        }
    }
    var currentLanguage by remember { mutableStateOf(languageManager.getCurrentLanguage()) }

    DoubleTapDetector(
        onDoubleTap = activateVoiceInput
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Title with Reset Button
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "TACMET",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )

                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            // NEW: Language Toggle Button
                            LanguageToggleButton(
                                currentLanguage = currentLanguage,
                                onLanguageChange = { newLanguage ->
                                    scope.launch {
                                        currentLanguage = newLanguage
                                        languageManager.setLanguage(newLanguage)
                                        ttsManager.changeLanguage(newLanguage)

                                        val message = when (newLanguage) {
                                            LanguageManager.Language.ENGLISH ->
                                                "Language: English"

                                            LanguageManager.Language.FRENCH ->
                                                "Langue : Français"
                                        }

                                        android.widget.Toast.makeText(
                                            context,
                                            message,
                                            android.widget.Toast.LENGTH_SHORT
                                        ).show()
                                    }
                                }
                            )

                            // Reset/Refresh Button
                            IconButton(
                                onClick = {
                                    scope.launch {
                                        try {
                                            // Stop all active processes first
                                            navigationManager.stopNavigation()
                                            conversationManager.stopConversationMode()

                                            // Reset all managers
                                            sensorManager.resetPosition()
                                            calibrationManager.resetCalibration()
                                            qrDetector.resetDetection()
                                            ttsManager.resetInstruction()

                                            // Clear local UI state
                                            source = ""
                                            destination = ""
                                            useClockDirections = false
                                            useLandmarks = false
                                            showAdvancedInfo = false

                                            // Show confirmation
                                            val msg =
                                                languageManager.getString("Interface reset successfully")
                                            android.widget.Toast.makeText(
                                                context,
                                                msg,
                                                android.widget.Toast.LENGTH_SHORT
                                            ).show()

                                        } catch (e: Exception) {
                                            android.widget.Toast.makeText(
                                                context,
                                                "Reset error: ${e.message}",
                                                android.widget.Toast.LENGTH_LONG
                                            ).show()
                                        }
                                    }
                                },
                                colors = IconButtonDefaults.iconButtonColors(
                                    containerColor = MaterialTheme.colorScheme.errorContainer
                                )
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Refresh,
                                    contentDescription = "Reset Interface",
                                    tint = MaterialTheme.colorScheme.onErrorContainer
                                )
                            }
                        }
                    }

                    // Double-tap instruction text
                    if (conversationState.isActive) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = if (currentLanguage == LanguageManager.Language.FRENCH) {
                                "Double-cliquez pour activer la saisie vocale"
                            } else {
                                "Double-tap anywhere to activate voice input"
                            },
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            textAlign = TextAlign.Center
                        )
                    }
                }

                // Status indicator with conversation support
                StatusIndicator(
                    isNavigating = navigationState.isNavigating,
                    isCalibrated = navigationState.isCalibrated,
                    ttsReady = ttsState.isReady,
                    qrDetectionActive = navigationState.qrDetectionActive,
                    qrDetected = qrDetectionState.isDetected,
                    conversationActive = conversationState.isActive
                )

                // Navigation input section
                NavigationInputSection(
                    source = source,
                    destination = destination,
                    useClockDirections = useClockDirections,
                    useLandmarks = useLandmarks,
                    ttsEnabled = ttsState.isEnabled,
                    poiNames = poiNames,
                    onSourceChange = { source = it },
                    onDestinationChange = { destination = it },
                    onClockDirectionsChange = { useClockDirections = it },
                    onLandmarksChange = { useLandmarks = it },
                    onTtsEnabledChange = { ttsManager.setEnabled(it) },
                    languageManager = languageManager
                )

                StepCalibrationCard(
                    imuState = imuState,
                    onStartCalibration = {
                        sensorManager.startStepCalibration()
                    },
                    onCompleteCalibration = {
                        sensorManager.completeStepCalibration()
                        android.widget.Toast.makeText(
                            context,
                            "Calibration complete! Beta: ${String.format("%.3f", imuState.userBeta)}",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    },
                    onStopCalibration = {
                        sensorManager.stopStepCalibration()
                        val message = if (imuState.isStepCalibrationValid) {
                            "Calibration stopped. Beta calculated: ${String.format("%.3f", imuState.userBeta)}"
                        } else {
                            "Calibration stopped. Not enough data collected."
                        }
                        android.widget.Toast.makeText(
                            context,
                            message,
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    },
                    onCancelCalibration = {
                        sensorManager.cancelStepCalibration()
                        android.widget.Toast.makeText(
                            context,
                            "Calibration cancelled",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                )


                // AI Conversation feature
                ConversationCard(
                    conversationState = conversationState,
                    onStartConversation = { conversationManager.startConversationMode() },
                    onStopConversation = { conversationManager.stopConversationMode() },
                    onStartListening = { conversationManager.startListening() },
                    onStopListening = { conversationManager.stopListening() },
                    onSendMessage = { message -> conversationManager.processTextInput(message) },
                    languageManager = languageManager
                )

                // Current instruction display
                InstructionCard(
                    instruction = navigationState.currentInstruction,
                    errorMessage = navigationState.errorMessage,
                    isNavigating = navigationState.isNavigating
                )

                // QR detection status (when active)
                if (navigationState.qrDetectionActive || qrDetectionState.isScanning) {
                    QRDetectionCard(
                        qrDetectionState = qrDetectionState,
                        navigationState = navigationState
                    )
                }

                // Navigation controls
                SteppedNavigationControls(
                    navigationState = navigationState,
                    canStart = source.isNotBlank() && destination.isNotBlank(),
                    ttsReady = ttsState.isReady && ttsState.isEnabled,
                    lifecycleOwner = lifecycleOwner,
                    conversationActive = conversationState.isActive,
                    onInitializeServer = {
                        scope.launch {
                            val result = navigationManager.initializeWithServer(
                                source = source,
                                destination = destination,
                                useClockDirections = useClockDirections,
                                useLandmarks = useLandmarks,
                                conversationMode = conversationState.isActive
                            )

                            result.onFailure { error ->
                                android.widget.Toast.makeText(
                                    context,
                                    "Server initialization failed: ${error.message}",
                                    android.widget.Toast.LENGTH_LONG
                                ).show()
                            }
                        }
                    },
                    onStartNavigation = {
                        // Combined start navigation with automatic calibration
                        scope.launch {
                            val result = navigationManager.startNavigationWithCalibration(lifecycleOwner)

                            result.onFailure { error ->
                                android.widget.Toast.makeText(
                                    context,
                                    "Navigation start failed: ${error.message}",
                                    android.widget.Toast.LENGTH_LONG
                                ).show()
                            }
                        }
                    },
                    onStopNavigation = { navigationManager.stopNavigation() },
                    onResetPosition = {
                        sensorManager.resetPosition()
                        calibrationManager.resetCalibration()
                        qrDetector.resetDetection()
                    },
                    onResetInstruction = { ttsManager.resetInstruction() },
                    onRepeatInstruction = { ttsManager.repeatLastInstruction() },
                    onForceUpdate = {
                        scope.launch { navigationManager.forcePositionUpdate() }
                    },
                    onTestQR = { navigationManager.testQRDetection() },
                    onCompleteReset = {
                        scope.launch {
                            try {
                                navigationManager.stopNavigation()
                                conversationManager.stopConversationMode()
                                sensorManager.resetPosition()
                                calibrationManager.resetCalibration()
                                qrDetector.resetDetection()
                                ttsManager.resetInstruction()
                                source = ""
                                destination = ""
                                useClockDirections = false
                                useLandmarks = false
                                showAdvancedInfo = false

                                android.widget.Toast.makeText(
                                    context,
                                    "Complete reset successful",
                                    android.widget.Toast.LENGTH_SHORT
                                ).show()
                            } catch (e: Exception) {
                                android.widget.Toast.makeText(
                                    context,
                                    "Reset error: ${e.message}",
                                    android.widget.Toast.LENGTH_LONG
                                ).show()
                            }
                        }
                    }
                )

                // Advanced info toggle
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = showAdvancedInfo,
                        onCheckedChange = { showAdvancedInfo = it }
                    )
                    Text("Show Technical Details")
                }

                // Advanced information section
                if (showAdvancedInfo) {
                    AdvancedInfoSection(
                        imuState = imuState,
                        calibrationManager = calibrationManager,
                        ttsManager = ttsManager,
                        navigationManager = navigationManager,
                        sensorManager = sensorManager,
                        qrDetector = qrDetector,
                        conversationManager = conversationManager
                    )
                }
            } // End of Column

            // Double-tap visual feedback overlay
            if (showDoubleTapFeedback) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)),
                    contentAlignment = Alignment.Center
                ) {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.primaryContainer
                        ),
                        elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = Icons.Default.Mic,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = if (conversationState.isListening) "Voice input active" else "Voice input stopped",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onPrimaryContainer
                            )
                        }
                    }
                }
            }
        } // End of Box
    } // End of DoubleTapDetector
}


@Composable
private fun StatusIndicator(
    isNavigating: Boolean,
    isCalibrated: Boolean,
    ttsReady: Boolean,
    qrDetectionActive: Boolean,
    qrDetected: Boolean,
    conversationActive: Boolean
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = when {
                isNavigating && isCalibrated -> MaterialTheme.colorScheme.primaryContainer
                isNavigating -> warningContainer
                else -> MaterialTheme.colorScheme.surfaceVariant
            }
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            // Primary status row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                StatusBadge("Navigation", isNavigating, MaterialTheme.colorScheme.primary)
                StatusBadge("Calibrated", isCalibrated, MaterialTheme.colorScheme.primary)
                StatusBadge("Voice", ttsReady, MaterialTheme.colorScheme.primary)
                StatusBadge("Chat AI", conversationActive, MaterialTheme.colorScheme.tertiary)
            }

            // QR detection status (when active)
            if (qrDetectionActive) {
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    StatusBadge("QR Scanner", qrDetectionActive, MaterialTheme.colorScheme.secondary)
                    StatusBadge("Anchor Point", qrDetected, MaterialTheme.colorScheme.tertiary)
                    StatusBadge("Drift Correction", qrDetectionActive, MaterialTheme.colorScheme.secondary)
                }
            }
        }
    }
}

@Composable
private fun StatusBadge(label: String, isActive: Boolean, activeColor: androidx.compose.ui.graphics.Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(12.dp)
                .background(
                    color = if (isActive) activeColor else MaterialTheme.colorScheme.outline,
                    shape = CircleShape
                )
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = if (isActive) activeColor else MaterialTheme.colorScheme.outline,
            textAlign = TextAlign.Center
        )
    }
}
/**
 * NEW: Language toggle button
 */
@Composable
private fun LanguageToggleButton(
    currentLanguage: LanguageManager.Language,
    onLanguageChange: (LanguageManager.Language) -> Unit
) {
    IconButton(
        onClick = {
            val newLanguage = when (currentLanguage) {
                LanguageManager.Language.ENGLISH -> LanguageManager.Language.FRENCH
                LanguageManager.Language.FRENCH -> LanguageManager.Language.ENGLISH
            }
            onLanguageChange(newLanguage)
        },
        colors = IconButtonDefaults.iconButtonColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(horizontal = 8.dp)
        ) {
            Text(
                text = when (currentLanguage) {
                    LanguageManager.Language.ENGLISH -> "🇬🇧 EN"
                    LanguageManager.Language.FRENCH -> "🇫🇷 FR"
                },
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onPrimaryContainer
            )
        }
    }
}


@Composable
private fun NavigationInputSection(
    source: String,
    destination: String,
    useClockDirections: Boolean,
    useLandmarks: Boolean,
    ttsEnabled: Boolean,
    poiNames: List<String>,
    onSourceChange: (String) -> Unit,
    onDestinationChange: (String) -> Unit,
    onClockDirectionsChange: (Boolean) -> Unit,
    onLandmarksChange: (Boolean) -> Unit,
    onTtsEnabledChange: (Boolean) -> Unit,
    languageManager: LanguageManager
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = languageManager.getString("Navigation Setup"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )


            Autocomplete(
                value = source,
                onValueChange = onSourceChange,
                poiNames = poiNames,
                label = languageManager.getString("Source Location")
            )

            Autocomplete(
                value = destination,
                onValueChange = onDestinationChange,
                poiNames = poiNames,
                label = languageManager.getString("Destination Location")
            )



            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                OptionCheckbox(
                    checked = useClockDirections,
                    onCheckedChange = onClockDirectionsChange,
                    label = languageManager.getString("Clock Directions"),
                    modifier = Modifier.weight(1f)
                )

                OptionCheckbox(
                    checked = useLandmarks,
                    onCheckedChange = onLandmarksChange,
                    label = languageManager.getString("Use Landmarks"),
                    modifier = Modifier.weight(1f)
                )
            }

            OptionCheckbox(
                checked = ttsEnabled,
                onCheckedChange = onTtsEnabledChange,
                label = languageManager.getString("Voice Guidance")
            )
        }
    }

}

@Composable
private fun StepCalibrationCard(
    imuState: IMUSensorManager.IMUState,
    onStartCalibration: () -> Unit,
    onCompleteCalibration: () -> Unit,
    onStopCalibration: () -> Unit,
    onCancelCalibration: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = when {
                imuState.isStepCalibrating -> MaterialTheme.colorScheme.primaryContainer
                imuState.isStepCalibrationValid -> MaterialTheme.colorScheme.tertiaryContainer
                else -> MaterialTheme.colorScheme.surfaceVariant
            }
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "SLC", // Step length calibration
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            // Status text
            Text(
                text = when {
                    imuState.isStepCalibrating -> "W5M" // Walk 5 mins
                    imuState.isStepCalibrationValid -> "C-${String.format("%.3f", imuState.userBeta)})"
                    else -> "" // Calibrate for personalized step length
                },
                style = MaterialTheme.typography.bodyMedium
            )

            // Buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (imuState.isStepCalibrating) {
                    // Show two buttons when calibrating (Complete and Stop/Cancel)
                    Button(
                        onClick = onCompleteCalibration,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("Complete Calibration")
                    }

                    Button(
                        onClick = onStopCalibration,
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.secondary
                        )
                    ) {
                        Text("Stop Calibration")
                    }
                } else {
                    Button(
                        onClick = onStartCalibration,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(if (imuState.isStepCalibrationValid) "Recalibrate Steps" else "Start Calibration")
                    }
                }
            }
        }
    }
}

@Composable
private fun OptionCheckbox(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = checked, onCheckedChange = onCheckedChange)
        Text(text = label, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun InstructionCard(
    instruction: String,
    errorMessage: String?,
    isNavigating: Boolean
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
        colors = CardDefaults.cardColors(
            containerColor = when {
                errorMessage != null -> MaterialTheme.colorScheme.errorContainer
                isNavigating -> MaterialTheme.colorScheme.primaryContainer
                else -> MaterialTheme.colorScheme.surface
            }
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Current Instruction",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = when {
                    errorMessage != null -> MaterialTheme.colorScheme.onErrorContainer
                    isNavigating -> MaterialTheme.colorScheme.onPrimaryContainer
                    else -> MaterialTheme.colorScheme.onSurface
                }
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = errorMessage ?: instruction,
                style = MaterialTheme.typography.bodyLarge,
                color = when {
                    errorMessage != null -> MaterialTheme.colorScheme.onErrorContainer
                    isNavigating -> MaterialTheme.colorScheme.onPrimaryContainer
                    else -> MaterialTheme.colorScheme.onSurface
                }
            )
        }
    }
}

@androidx.annotation.OptIn(ExperimentalGetImage::class)
@Composable
private fun QRDetectionCard(
    qrDetectionState: QRCodeDetector.QRDetectionState,
    navigationState: NavigationManager.NavigationState
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = when {
                qrDetectionState.isDetected -> MaterialTheme.colorScheme.tertiaryContainer
                qrDetectionState.isScanning -> MaterialTheme.colorScheme.secondaryContainer
                else -> MaterialTheme.colorScheme.surfaceVariant
            }
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "QR Drift Correction",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = when {
                            qrDetectionState.isDetected -> "Anchor Point Detected!"
                            qrDetectionState.isScanning -> "Scanning for QR codes..."
                            else -> "QR Scanner Ready"
                        },
                        style = MaterialTheme.typography.bodyMedium
                    )

                    if (navigationState.qrDetectionCount > 0) {
                        Text(
                            text = "Detected: ${navigationState.qrDetectionCount} times",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .size(16.dp)
                        .background(
                            color = when {
                                qrDetectionState.isDetected -> MaterialTheme.colorScheme.tertiary
                                qrDetectionState.isScanning -> MaterialTheme.colorScheme.secondary
                                else -> MaterialTheme.colorScheme.outline
                            },
                            shape = CircleShape
                        )
                )
            }

            qrDetectionState.lastQRContent?.let { content ->
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Last QR: $content",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@androidx.annotation.OptIn(ExperimentalGetImage::class)
@Composable
private fun SteppedNavigationControls(
    navigationState: NavigationManager.NavigationState,
    canStart: Boolean,
    ttsReady: Boolean,
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    conversationActive: Boolean,
    onInitializeServer: () -> Unit,
    onStartNavigation: () -> Unit,
    onStopNavigation: () -> Unit,
    onResetPosition: () -> Unit,
    onResetInstruction: () -> Unit,
    onRepeatInstruction: () -> Unit,
    onForceUpdate: () -> Unit,
    onTestQR: () -> Unit,
    onCompleteReset: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Simplified step progress indicator
        StepProgressIndicator(
            currentStep = navigationState.initializationStep,
            modifier = Modifier.fillMaxWidth()
        )

        // Current step status message
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = when (navigationState.initializationStep) {
                    NavigationManager.InitStep.ERROR -> MaterialTheme.colorScheme.errorContainer
                    NavigationManager.InitStep.NAVIGATING -> MaterialTheme.colorScheme.primaryContainer
                    else -> MaterialTheme.colorScheme.surfaceVariant
                }
            )
        ) {
            Text(
                text = getStepStatusMessage(navigationState, conversationActive),
                modifier = Modifier.padding(16.dp),
                style = MaterialTheme.typography.bodyMedium
            )
        }

        // Server response display
        navigationState.serverResponse?.let { response ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Server Response:",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(text = response, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }


        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Step 1: Initialize Server
            Button(
                onClick = onInitializeServer,
                enabled = canStart && navigationState.initializationStep == NavigationManager.InitStep.NOT_STARTED,
                modifier = Modifier.weight(1f)
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "1. Initialize Server",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Connect & Setup Route",
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.8f)
                    )
                }
            }

            // Step 2: Start Navigation (Combined with calibration)
            Button(
                onClick = onStartNavigation,
                enabled = navigationState.initializationStep == NavigationManager.InitStep.INITIALIZED,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.tertiary
                )
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "2. Start Navigation",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Auto-Calibrate & Begin",
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onTertiary.copy(alpha = 0.8f)
                    )
                }
            }
        }

        // Stop button (when navigation is active)
        if (navigationState.isNavigating || navigationState.isInitialized) {
            Button(
                onClick = onStopNavigation,
                enabled = true,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(
                    imageVector = Icons.Default.Refresh,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Stop Navigation", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        // Secondary controls (smaller, less prominent)
        if (navigationState.isNavigating) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                )
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Navigation Controls",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        OutlinedButton(
                            onClick = {
                                onResetPosition()
                                onResetInstruction()
                            },
                            enabled = ttsReady,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Reset", fontSize = 11.sp)
                        }

                        Spacer(modifier = Modifier.width(4.dp))

                        OutlinedButton(
                            onClick = onRepeatInstruction,
                            enabled = ttsReady,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Repeat", fontSize = 11.sp)
                        }

                        Spacer(modifier = Modifier.width(4.dp))

                        OutlinedButton(
                            onClick = onForceUpdate,
                            enabled = navigationState.isNavigating,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Update", fontSize = 11.sp)
                        }

                        Spacer(modifier = Modifier.width(4.dp))

                        OutlinedButton(
                            onClick = onTestQR,
                            enabled = true,
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("Test QR", fontSize = 11.sp)
                        }
                    }
                }
            }
        }

        // Complete Reset Button (always available, less prominent)
        OutlinedButton(
            onClick = onCompleteReset,
            enabled = true,
            colors = ButtonDefaults.outlinedButtonColors(
                contentColor = MaterialTheme.colorScheme.error
            ),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(
                imageVector = Icons.Default.Refresh,
                contentDescription = null,
                modifier = Modifier.size(14.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Complete Reset - Clear All Data", fontSize = 12.sp)
        }
    }
}


@androidx.annotation.OptIn(ExperimentalGetImage::class)
private fun getStepStatusMessage(navigationState: NavigationManager.NavigationState, conversationActive: Boolean): String {
    return when (navigationState.initializationStep) {
        NavigationManager.InitStep.NOT_STARTED -> "Enter source and destination, then click 'Initialize Server'"
        NavigationManager.InitStep.INITIALIZED -> {
            val baseMessage = "Server connected! Click 'Start Navigation' to begin (includes automatic calibration)."
            if (conversationActive) "$baseMessage AI assistant is ready for questions." else baseMessage
        }
        NavigationManager.InitStep.NAVIGATING -> {
            val baseMessage = "Navigation active with automatic calibration - follow voice instructions"
            if (conversationActive) "$baseMessage Ask me questions anytime!" else baseMessage
        }
        NavigationManager.InitStep.ERROR -> navigationState.errorMessage ?: "An error occurred during setup"
    }
}

@androidx.annotation.OptIn(ExperimentalGetImage::class)
@Composable
private fun StepProgressIndicator(
    currentStep: NavigationManager.InitStep,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Step 1: Server Connection
        StepIndicatorItem(
            stepNumber = 1,
            label = "Server",
            isComplete = currentStep >= NavigationManager.InitStep.INITIALIZED,
            isActive = false // Never show as "in progress" since it's instant
        )

        StepConnector(currentStep >= NavigationManager.InitStep.INITIALIZED)

        // Step 2: Navigation (includes auto-calibration)
        StepIndicatorItem(
            stepNumber = 2,
            label = "Navigate",
            isComplete = currentStep == NavigationManager.InitStep.NAVIGATING,
            isActive = currentStep == NavigationManager.InitStep.NAVIGATING
        )
    }
}











@Composable
private fun StepIndicatorItem(
    stepNumber: Int,
    label: String,
    isComplete: Boolean,
    isActive: Boolean
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .background(
                    color = when {
                        isComplete -> MaterialTheme.colorScheme.primary
                        isActive -> MaterialTheme.colorScheme.primaryContainer
                        else -> MaterialTheme.colorScheme.outline
                    },
                    shape = CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = if (isComplete && !isActive) "✓" else stepNumber.toString(),
                color = if (isComplete || isActive) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = if (isActive || isComplete) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun StepConnector(isActive: Boolean) {
    Box(
        modifier = Modifier
            .height(2.dp)
            .width(32.dp)
            .background(
                color = if (isActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
            )
    )
}



@androidx.annotation.OptIn(ExperimentalGetImage::class)
@Composable
private fun AdvancedInfoSection(
    imuState: IMUSensorManager.IMUState,
    calibrationManager: IMUCalibrationManager,
    ttsManager: TTSManager,
    navigationManager: NavigationManager,
    sensorManager: IMUSensorManager,
    qrDetector: QRCodeDetector,
    conversationManager: ConversationManager
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = "Technical Information",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )

            // Conversation Status
            val conversationState = conversationManager.conversationState.collectAsState().value
            InfoSection(
                title = "AI Conversation",
                data = mapOf(
                    "Active" to if (conversationState.isActive) "✓" else "✗",
                    "Listening" to if (conversationState.isListening) "✓" else "✗",
                    "Processing" to if (conversationState.isProcessing) "Yes" else "No",
                    "Route Data" to if (conversationState.hasRouteData) "Loaded" else "Not loaded",
                    "Messages" to "${conversationState.conversationHistory.size}",
                    "Status" to if (conversationState.errorMessage != null) "Error" else "Ready"
                )
            )

            Divider()

            // IMU Information
            InfoSection(
                title = "IMU Data",
                data = mapOf(
                    "Position" to "(${String.format("%.2f", imuState.position.x)}, ${String.format("%.2f", imuState.position.y)})",
                    "Bearing" to "${String.format("%.1f", imuState.position.bearing)}°",
                    "Steps" to "${imuState.stepCount}",
                    "Moving" to if (imuState.isMoving) "Yes" else "No"
                )
            )

            Divider()

            // Navigation Summary
            val navSummary = navigationManager.getNavigationSummary()
            InfoSection(
                title = "Navigation Status",
                data = mapOf(
                    "Active" to if (navSummary["isNavigating"] as Boolean) "✓" else "✗",
                    "Route" to navSummary["route"].toString(),
                    "QR Detections" to navSummary["qrDetectionCount"].toString(),
                    "Last Update" to navSummary["lastUpdate"].toString()
                )
            )
        }
    }

    Divider()


// Export Controls
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var isExporting by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Button(
            onClick = {
                scope.launch {
                    isExporting = true
                    try {
                        withContext(Dispatchers.IO) {
                            val downloadsDir = android.os.Environment
                                .getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS)

                            if (!downloadsDir.exists()) {
                                downloadsDir.mkdirs()
                            }

                            val file = java.io.File(
                                downloadsDir,
                                "step_data_${System.currentTimeMillis()}.csv"
                            )

                            val samples = sensorManager.getAccelerationSamples()

                            // Use BufferedWriter for efficient writing
                            BufferedWriter(FileWriter(file)).use { writer ->
                                // Write header
                                writer.write("SampleIndex,Timestamp,RawMagnitude,FilteredMagnitude,IsPeak,IsValley,IsConfirmedStep,StepLength,StepNumber,PeakValleyDiff\n")

                                // Write all samples efficiently
                                samples.forEach { sample ->
                                    writer.write(
                                        "${sample.sampleIndex}," +
                                                "${sample.timestamp}," +
                                                "${sample.rawMagnitude}," +
                                                "${sample.filteredMagnitude}," +
                                                "${sample.isPeak}," +
                                                "${sample.isValley}," +
                                                "${sample.isConfirmedStep}," +
                                                "${sample.stepLength ?: ""}," +
                                                "${sample.stepNumber ?: ""}," +
                                                "${sample.peakValleyDiff ?: ""}\n"
                                    )
                                }
                            }

                            withContext(Dispatchers.Main) {
                                android.widget.Toast.makeText(
                                    context,
                                    "Exported ${samples.size} samples to Downloads/${file.name}",
                                    android.widget.Toast.LENGTH_LONG
                                ).show()
                            }
                        }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            android.widget.Toast.makeText(
                                context,
                                "Export failed: ${e.message}",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                    } finally {
                        isExporting = false
                    }
                }
            },
            modifier = Modifier.weight(1f),
            enabled = !isExporting
        ) {
            if (isExporting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(
                text = if (isExporting) "Exporting..." else "Export Step Data",
                fontSize = 12.sp
            )
        }
        Button(
            onClick = {
                val metrics = sensorManager.getStepDetectionMetrics()
                android.widget.Toast.makeText(
                    context,
                    "Steps: ${metrics["totalSteps"]}, Freq: ${metrics["walkingFrequency"]}",
                    android.widget.Toast.LENGTH_LONG
                ).show()
            },
            modifier = Modifier.weight(1f)
        ) {
            Text("Show Metrics", fontSize = 12.sp)
        }
    }
}

@Composable
private fun InfoSection(title: String, data: Map<String, String>) {
    Column {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.primary
        )

        Spacer(modifier = Modifier.height(8.dp))

        data.forEach { (key, value) ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = key,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = value,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.End,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

// Extension property for warning container color
private val warningContainer: androidx.compose.ui.graphics.Color
    @Composable
    get() = if (isSystemInDarkTheme()) {
        androidx.compose.ui.graphics.Color(0xFF5D4037)
    } else {
        androidx.compose.ui.graphics.Color(0xFFFFF3E0)
    }