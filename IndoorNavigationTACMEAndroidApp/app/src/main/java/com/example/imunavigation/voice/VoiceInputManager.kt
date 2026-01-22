// VoiceInputManager.kt
package com.example.imunavigation.voice

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.*

/**
 * Enhanced voice input manager
 */
open class VoiceInputManager(private val context: Context) {

    data class VoiceInputState(
        val isListening: Boolean = false,
        val isReady: Boolean = false,
        val lastResult: String = "",
        val source: String = "",
        val destination: String = "",
        val isComplete: Boolean = false,
        val currentMode: InputMode = InputMode.NONE,
        val errorMessage: String = "",
        val debugInfo: String = "",
        val waitingForConfirmation: Boolean = false,
        val confirmationPrompt: String = "",
        val retryCount: Int = 0,
        val maxRetries: Int = 5,
        val isInstructing: Boolean = false
    )

    enum class InputMode {
        NONE,
        LISTENING_SOURCE,
        LISTENING_DESTINATION,
        CONFIRMING_SOURCE,
        CONFIRMING_DESTINATION,
        CONFIRMING_BOTH
    }

    private val _voiceInputState = MutableStateFlow(VoiceInputState())
    val voiceInputState: StateFlow<VoiceInputState> = _voiceInputState.asStateFlow()

    private var speechRecognizer: SpeechRecognizer? = null
    private var onResultCallback: ((source: String, destination: String) -> Unit)? = null
    private var onStatusCallback: ((status: String, prompt: String) -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Temporary storage for confirmation flow
    private var tempSource: String = ""
    private var tempDestination: String = ""

    companion object {
        private const val TAG = "VoiceInputManager"


        private const val INSTRUCTION_DELAY_MS = 4000L        // 4 seconds to process instruction
        private const val CONFIRMATION_DELAY_MS = 3000L       // 3 seconds for confirmation prompts
        private const val RETRY_DELAY_MS = 3000L             // 3 seconds before retry
        private const val ERROR_RECOVERY_DELAY_MS = 2500L    // 2.5 seconds after errors

        // Speech recognition timeouts
        private const val SPEECH_COMPLETE_SILENCE_MS = 4000L   // 4 seconds of silence to complete
        private const val SPEECH_PARTIAL_SILENCE_MS = 3000L    // 3 seconds for partial completion
        private const val SPEECH_MINIMUM_LENGTH_MS = 800L      // Minimum 0.8 seconds of speech
    }

    init {
        mainHandler.post {
            initializeSpeechRecognizer()
        }
    }

    private fun initializeSpeechRecognizer() {
        try {
            Log.d(TAG, "Initializing speech recognizer...")

            speechRecognizer?.destroy()

            if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                Log.e(TAG, "Speech recognition NOT available")
                updateState { it.copy(
                    isReady = false,
                    errorMessage = "Speech recognition not available",
                    debugInfo = "Device does not support speech recognition"
                )}
                return
            }

            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)

            if (speechRecognizer == null) {
                Log.e(TAG, "Failed to create SpeechRecognizer")
                updateState { it.copy(
                    isReady = false,
                    errorMessage = "Failed to create speech recognizer"
                )}
                return
            }

            speechRecognizer?.setRecognitionListener(recognitionListener)

            updateState { it.copy(
                isReady = true,
                errorMessage = "",
                debugInfo = "Speech recognizer ready"
            )}

            Log.d(TAG, "Speech recognizer initialized successfully")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize speech recognizer: ${e.message}", e)
            updateState { it.copy(
                isReady = false,
                errorMessage = "Initialization failed: ${e.message}"
            )}
        }
    }

    private fun updateState(update: (VoiceInputState) -> VoiceInputState) {
        _voiceInputState.value = update(_voiceInputState.value)
    }

    /**
     * Schedule listening with appropriate delays
     */
    private fun scheduleListening(prompt: String, delayMs: Long) {
        Log.d(TAG, "Scheduling listening in ${delayMs}ms with prompt: $prompt")

        updateState { it.copy(
            isInstructing = true,
            debugInfo = "Processing instruction... will listen in ${delayMs/1000} seconds"
        )}

        mainHandler.postDelayed({
            updateState { it.copy(isInstructing = false) }
            startListening(prompt)
        }, delayMs)
    }

    private fun startListening(prompt: String) {
        try {
            Log.d(TAG, "Starting to listen: $prompt")

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
                putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)


                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, SPEECH_COMPLETE_SILENCE_MS)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, SPEECH_PARTIAL_SILENCE_MS)
                putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, SPEECH_MINIMUM_LENGTH_MS)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            }

            updateState { it.copy(
                isListening = true,
                isInstructing = false,
                errorMessage = "",
                debugInfo = "Listening for input - take your time"
            )}

            speechRecognizer?.startListening(intent)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start listening: ${e.message}", e)
            updateState { it.copy(
                isListening = false,
                isInstructing = false,
                errorMessage = "Failed to start listening: ${e.message}"
            )}
        }
    }

    private val recognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "Ready for speech")
            updateState { it.copy(debugInfo = "Microphone ready - you can speak now") }
        }

        override fun onBeginningOfSpeech() {
            Log.d(TAG, "Speech detected")
            updateState { it.copy(debugInfo = "Listening to you...") }
        }

        override fun onRmsChanged(rmsdB: Float) {
            // Visual feedback for voice level
            if (rmsdB > -25) {
                updateState { it.copy(debugInfo = "Voice detected: ${String.format("%.0f", rmsdB + 40)}%") }
            }
        }

        override fun onBufferReceived(buffer: ByteArray?) { /* Not used */ }

        override fun onEndOfSpeech() {
            Log.d(TAG, "End of speech detected")
            updateState { it.copy(
                isListening = false,
                debugInfo = "Processing what you said..."
            )}
        }

        override fun onError(error: Int) {
            val errorMessage = getErrorMessage(error)
            Log.e(TAG, "Speech recognition error ($error): $errorMessage")

            updateState { it.copy(
                isListening = false,
                isInstructing = false,
                errorMessage = errorMessage,
                debugInfo = "Error: $errorMessage"
            )}

            handleSpeechError(error, errorMessage)
        }

        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val confidences = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)

            if (matches != null && matches.isNotEmpty()) {
                val recognizedText = matches[0]
                val confidence = confidences?.getOrNull(0) ?: 0f

                Log.d(TAG, "Recognition result: '$recognizedText' (confidence: ${(confidence * 100).toInt()}%)")

                updateState { it.copy(
                    lastResult = recognizedText,
                    isListening = false,
                    debugInfo = "Heard: '$recognizedText'"
                )}

                processRecognitionResult(recognizedText, confidence)
            } else {
                Log.w(TAG, "No recognition results")
                handleNoResults()
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val partialMatches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (partialMatches != null && partialMatches.isNotEmpty()) {
                updateState { it.copy(
                    debugInfo = "Hearing: '${partialMatches[0]}...'"
                )}
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) { /* Not used */ }
    }

    private fun processRecognitionResult(recognizedText: String, confidence: Float) {
        val currentState = _voiceInputState.value

        when (currentState.currentMode) {
            InputMode.LISTENING_SOURCE -> {
                val extractedSource = extractLocation(recognizedText, "source")
                if (extractedSource.isNotEmpty()) {
                    tempSource = extractedSource

                    val confirmMessage = "Is your starting location $extractedSource?"

                    updateState { it.copy(
                        currentMode = InputMode.CONFIRMING_SOURCE,
                        waitingForConfirmation = true,
                        confirmationPrompt = confirmMessage,
                        isInstructing = true,
                        debugInfo = "Confirming source: $extractedSource"
                    )}

                    onStatusCallback?.invoke("confirming", confirmMessage)


                    scheduleListening("Say 'yes' if $extractedSource is correct, or 'no' to try again", CONFIRMATION_DELAY_MS)

                } else {
                    handleExtractionFailure("source", recognizedText, InputMode.LISTENING_SOURCE)
                }
            }

            InputMode.LISTENING_DESTINATION -> {
                val extractedDestination = extractLocation(recognizedText, "destination")
                if (extractedDestination.isNotEmpty()) {
                    tempDestination = extractedDestination

                    val confirmMessage = "Is your destination $extractedDestination?"

                    updateState { it.copy(
                        currentMode = InputMode.CONFIRMING_DESTINATION,
                        waitingForConfirmation = true,
                        confirmationPrompt = confirmMessage,
                        isInstructing = true,
                        debugInfo = "Confirming destination: $extractedDestination"
                    )}

                    onStatusCallback?.invoke("confirming", confirmMessage)
                    scheduleListening("Say 'yes' if $extractedDestination is correct, or 'no' to try again", CONFIRMATION_DELAY_MS)

                } else {
                    handleExtractionFailure("destination", recognizedText, InputMode.LISTENING_DESTINATION)
                }
            }

            InputMode.CONFIRMING_SOURCE -> {
                if (isPositiveResponse(recognizedText)) {
                    val destinationPrompt = "Now tell me your destination."

                    updateState { it.copy(
                        source = tempSource,
                        currentMode = InputMode.LISTENING_DESTINATION,
                        waitingForConfirmation = false,
                        isInstructing = true,
                        debugInfo = "Source confirmed, listening for destination"
                    )}

                    onStatusCallback?.invoke("instructing", destinationPrompt)
                    scheduleListening(destinationPrompt, INSTRUCTION_DELAY_MS)

                } else if (isNegativeResponse(recognizedText)) {
                    retryInput("source", InputMode.LISTENING_SOURCE, "Again. What's your starting location?")
                } else {
                    val clarifyMessage = "I didn't catch that. Please say 'yes' if $tempSource is correct, or 'no' to try again."

                    updateState { it.copy(isInstructing = true) }
                    onStatusCallback?.invoke("clarifying", clarifyMessage)
                    scheduleListening(clarifyMessage, CONFIRMATION_DELAY_MS)
                }
            }

            InputMode.CONFIRMING_DESTINATION -> {
                if (isPositiveResponse(recognizedText)) {
                    showFinalConfirmation()
                } else if (isNegativeResponse(recognizedText)) {
                    retryInput("destination", InputMode.LISTENING_DESTINATION, "Again. Where do you want to go?")
                } else {
                    val clarifyMessage = "Please say 'yes' if $tempDestination is correct, or 'no' to try again."

                    updateState { it.copy(isInstructing = true) }
                    onStatusCallback?.invoke("clarifying", clarifyMessage)
                    scheduleListening(clarifyMessage, CONFIRMATION_DELAY_MS)
                }
            }

            InputMode.CONFIRMING_BOTH -> {
                if (isPositiveResponse(recognizedText)) {
                    completeVoiceInput()
                } else if (isNegativeResponse(recognizedText)) {
                    restartVoiceInput()
                } else {
                    val clarifyMessage = "Please say 'yes' to confirm both locations, or 'no' to start over."

                    updateState { it.copy(isInstructing = true) }
                    onStatusCallback?.invoke("clarifying", clarifyMessage)
                    scheduleListening(clarifyMessage, CONFIRMATION_DELAY_MS)
                }
            }

            else -> {
                Log.w(TAG, "Unexpected recognition in mode: ${currentState.currentMode}")
            }
        }
    }

    private fun showFinalConfirmation() {
        val finalMessage = "Perfect! I have your route from $tempSource to $tempDestination."

        updateState { it.copy(
            currentMode = InputMode.CONFIRMING_BOTH,
            confirmationPrompt = finalMessage,
            destination = tempDestination,
            isInstructing = true,
            debugInfo = "Final confirmation needed"
        )}

        onStatusCallback?.invoke("final_confirm", finalMessage)


        scheduleListening(finalMessage, INSTRUCTION_DELAY_MS)
    }

    private fun completeVoiceInput() {
        Log.d(TAG, "Voice input completed successfully: $tempSource -> $tempDestination")

        updateState { it.copy(
            source = tempSource,
            destination = tempDestination,
            isComplete = true,
            currentMode = InputMode.NONE,
            waitingForConfirmation = false,
            isInstructing = false,
            debugInfo = "Voice input complete!"
        )}

        val successMessage = "Excellent! Navigation is set up from $tempSource to $tempDestination. Now point your camera at any QR code near the door."
        onStatusCallback?.invoke("complete", successMessage)

        onResultCallback?.invoke(tempSource, tempDestination)
    }

    private fun retryInput(type: String, mode: InputMode, prompt: String) {
        val currentRetries = _voiceInputState.value.retryCount + 1

        if (currentRetries >= _voiceInputState.value.maxRetries) {
            handleMaxRetriesReached(type)
            return
        }

        updateState { it.copy(
            currentMode = mode,
            waitingForConfirmation = false,
            retryCount = currentRetries,
            isInstructing = true,
            debugInfo = "Retry $currentRetries for $type"
        )}

        onStatusCallback?.invoke("retrying", "$prompt (Attempt ${currentRetries + 1})")


        scheduleListening(prompt, RETRY_DELAY_MS)
    }

    private fun restartVoiceInput() {
        tempSource = ""
        tempDestination = ""

        updateState { it.copy(
            currentMode = InputMode.LISTENING_SOURCE,
            waitingForConfirmation = false,
            retryCount = 0,
            isInstructing = true,
            debugInfo = "Restarting voice input"
        )}

        val restartMessage = "Let's start over. What's your starting location?"
        onStatusCallback?.invoke("restarting", restartMessage)

        scheduleListening(restartMessage, INSTRUCTION_DELAY_MS)
    }

    private fun handleExtractionFailure(type: String, recognizedText: String, retryMode: InputMode) {
        val currentRetries = _voiceInputState.value.retryCount + 1

        if (currentRetries >= _voiceInputState.value.maxRetries) {
            handleMaxRetriesReached(type)
            return
        }

        Log.w(TAG, "Could not extract $type from: '$recognizedText' (attempt $currentRetries)")

        val retryMessage = when (type) {
            "source" -> "I couldn't understand your starting location. Please try again with something like 'source room 435'"
            "destination" -> "I couldn't understand your destination. Please try again with something like 'destination room 424'"
            else -> "I couldn't understand. Please try again."
        }

        updateState { it.copy(
            retryCount = currentRetries,
            isInstructing = true,
            debugInfo = "Extraction failed for $type, retrying"
        )}

        onStatusCallback?.invoke("error", retryMessage)


        scheduleListening(retryMessage, ERROR_RECOVERY_DELAY_MS)
    }

    private fun handleMaxRetriesReached(type: String) {
        val errorMessage = "I'm having trouble understanding the $type after several attempts. Please use manual input instead."

        updateState { it.copy(
            currentMode = InputMode.NONE,
            errorMessage = errorMessage,
            isInstructing = false,
            debugInfo = "Max retries reached for $type"
        )}

        onStatusCallback?.invoke("max_retries", errorMessage)
    }

    private fun handleSpeechError(error: Int, errorMessage: String) {
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH,
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                val currentState = _voiceInputState.value
                if (currentState.retryCount < currentState.maxRetries) {
                    // Generate appropriate retry message based on current mode
                    val retryMessage = when (currentState.currentMode) {
                        InputMode.LISTENING_SOURCE -> "I didn't catch that. Please tell me your starting location."
                        InputMode.LISTENING_DESTINATION -> "Please tell me your destination."
                        InputMode.CONFIRMING_SOURCE -> "Say 'yes' if $tempSource is correct, or 'no' to try again."
                        InputMode.CONFIRMING_DESTINATION -> "Say 'yes' if $tempDestination is correct, or 'no' to try again."
                        InputMode.CONFIRMING_BOTH -> "Say 'yes' to confirm your route from $tempSource to $tempDestination, or 'no' to start over."
                        else -> "I didn't catch that. Can you repeat your response?"
                    }

                    updateState { it.copy(
                        isInstructing = true,
                        retryCount = currentState.retryCount + 1
                    )}
                    onStatusCallback?.invoke("retry_silence", retryMessage)

                    // Use the same retry message for listening
                    mainHandler.postDelayed({
                        updateState { it.copy(isInstructing = false) }
                        startListening(retryMessage)
                    }, ERROR_RECOVERY_DELAY_MS)
                } else {
                    handleMaxRetriesReached("input")
                }
            }

            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> {
                updateState { it.copy(
                    currentMode = InputMode.NONE,
                    isReady = false,
                    isInstructing = false,
                    errorMessage = "Microphone permission required"
                )}
                onStatusCallback?.invoke("permission_error", "Microphone permission is required for voice input")
            }

            else -> {
                onStatusCallback?.invoke("error", "Voice recognition error: $errorMessage")
                updateState { it.copy(
                    currentMode = InputMode.NONE,
                    isInstructing = false
                ) }
            }
        }
    }

    private fun handleNoResults() {
        val retryMessage = "I didn't catch that. Could you please try again?"

        updateState { it.copy(isInstructing = true) }
        onStatusCallback?.invoke("no_results", retryMessage)


        mainHandler.postDelayed({
            retryCurrentInput()
        }, ERROR_RECOVERY_DELAY_MS)
    }

    private fun retryCurrentInput() {
        val currentState = _voiceInputState.value
        if (!currentState.isReady) return

        when (currentState.currentMode) {
            InputMode.LISTENING_SOURCE -> {
                scheduleListening("Please tell me your starting location, like 'source room 435'", INSTRUCTION_DELAY_MS)
            }
            InputMode.LISTENING_DESTINATION -> {
                scheduleListening("Please tell me your destination, like 'destination room 424'", INSTRUCTION_DELAY_MS)
            }
            InputMode.CONFIRMING_SOURCE -> {
                scheduleListening("Say 'yes' if $tempSource is correct, or 'no' to try again", CONFIRMATION_DELAY_MS)
            }
            InputMode.CONFIRMING_DESTINATION -> {
                scheduleListening("Say 'yes' if $tempDestination is correct, or 'no' to try again", CONFIRMATION_DELAY_MS)
            }
            InputMode.CONFIRMING_BOTH -> {
                scheduleListening("Say 'yes' to confirm your route, or 'no' to start over", CONFIRMATION_DELAY_MS)
            }
            else -> {}
        }
    }

    private fun getErrorMessage(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Microphone error"
            SpeechRecognizer.ERROR_CLIENT -> "Client error"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission required"
            SpeechRecognizer.ERROR_NETWORK -> "Network connection needed"
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
            SpeechRecognizer.ERROR_NO_MATCH -> "Couldn't understand - please try again"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Voice recognizer busy"
            SpeechRecognizer.ERROR_SERVER -> "Speech server error"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected - please try again"
            else -> "Speech recognition error"
        }
    }

    private fun isPositiveResponse(text: String): Boolean {
        val cleaned = text.lowercase().trim()
        return cleaned in listOf("yes", "yeah", "yep", "correct", "right", "ok", "okay", "true", "confirm")
    }

    private fun isNegativeResponse(text: String): Boolean {
        val cleaned = text.lowercase().trim()
        return cleaned in listOf("no", "nope", "wrong", "incorrect", "false", "try again", "retry")
    }

    protected fun extractLocation(text: String, expectedType: String): String {
        val cleanText = text.lowercase().trim()
        Log.d(TAG, "Extracting $expectedType from: '$cleanText'")

        // Pattern 1: "source room 435" or "destination room 424"
        val pattern1 = Regex("$expectedType\\s+(room\\s*\\d+)")
        val match1 = pattern1.find(cleanText)
        if (match1 != null) {
            val location = match1.groupValues[1].replace("\\s+".toRegex(), "")
            Log.d(TAG, "Pattern 1 match: '$location'")
            return location
        }

        // Pattern 2: "source 435" or "destination 424"
        val pattern2 = Regex("$expectedType\\s+(\\d+)")
        val match2 = pattern2.find(cleanText)
        if (match2 != null) {
            val roomNumber = match2.groupValues[1]
            val location = "room$roomNumber"
            Log.d(TAG, "Pattern 2 match: '$location'")
            return location
        }

        // Pattern 3: Just "room 435" or "435"
        val pattern3 = Regex("(?:room\\s*)?(\\d{3,4})")
        val match3 = pattern3.find(cleanText)
        if (match3 != null) {
            val roomNumber = match3.groupValues[1]
            val location = "room$roomNumber"
            Log.d(TAG, "Pattern 3 match: '$location'")
            return location
        }

        Log.w(TAG, "No location pattern matched in: '$cleanText'")
        return ""
    }


}