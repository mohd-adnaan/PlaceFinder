// TTSManager.kt
package com.example.imunavigation.tts

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.*
import com.example.imunavigation.language.LanguageManager

/**
 * Manages Text-to-Speech functionality for navigation instructions
  */
class TTSManager(private val context: Context, private var languageManager: LanguageManager? = null) : TextToSpeech.OnInitListener {

    /**
     * TTS state information
     */
    data class TTSState(
        val isReady: Boolean = false,
        val isEnabled: Boolean = true,
        val isSpeaking: Boolean = false,
        val lastSpokenText: String = "",
        val lastSpeechTime: Long = 0L
    )

    private var textToSpeech: TextToSpeech? = null
    private val _ttsState = MutableStateFlow(TTSState())
    val ttsState: StateFlow<TTSState> = _ttsState.asStateFlow()

    // Speech management with different priorities
    private val minTimeBetweenSameInstructions = 10000L // 10 seconds for regular instructions
    private val minTimeBetweenAnyInstructions = 1500L //3000L // 3 seconds between different instructions
    private val minTimeBetweenPriorityInstructions = 5000L // 5 seconds for priority instructions (shorter)
    private val minTimeBetweenNeverMissInstructions = 2000L // 3 seconds for never-miss instructions

    // Track the last instruction to prevent consecutive identical utterances
    private var lastNormalizedInstruction: String = ""

    // Track when the last timed never-miss instruction was spoken
    private val lastTimedNeverMissInstructionTimes = mutableMapOf<String, Long>()

    // Never-miss keywords that should always be spoken but never consecutively (same instruction)
    private val neverMissNoConsecutiveKeywords = setOf(
        "prepare"
    )

    // Never-miss keywords that should always be spoken but never within 3 seconds of each other
    private val neverMissTimedKeywords = setOf(
        "turn left", "turn right", "press"
    )

    // Priority instruction keywords that should always be spoken more frequently
    private val priorityKeywords = setOf(
        "straight", "reversed",
        "recalibrate", "error", "keep moving", "turn completed", "press"
    )

    // Critical instruction keywords that should ALWAYS be spoken (even if repeated quickly)
    private val criticalKeywords = setOf(
        "backtrack", "wrong direction", "danger", "keep moving", "stop", "error","turn completed", "make", "turn left", "turn right", "turn completed", "backtrack", "press"
    )

    // One-time only instruction keywords that should only be spoken once per session
    private val oneTimeKeywords = setOf(
        "reached", "finished", "approaching","arrived","destination"
    )

    // Track one-time instructions that have been spoken
    private val spokenOneTimeInstructions = mutableSetOf<String>()

    companion object {
        private const val TAG = "TTSManager"
        private const val SPEECH_RATE = 1.1f //0.9
        private const val SPEECH_PITCH = 1.0f
    }

    init {
        initializeTTS()
    }

    /**
     * Initialize Text-to-Speech engine
     */
    private fun initializeTTS() {
        try {
            textToSpeech = TextToSpeech(context, this)
            Log.d(TAG, "TTS initialization started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize TTS: ${e.message}")
            _ttsState.value = _ttsState.value.copy(isReady = false)
        }
    }
    fun setLanguageManager(manager: LanguageManager) {
        languageManager = manager
        updateTTSLanguage()
    }


    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            textToSpeech?.let { tts ->
                // Set language
                updateTTSLanguage()

                // Configure TTS settings
                tts.setSpeechRate(SPEECH_RATE)
                tts.setPitch(SPEECH_PITCH)

                // Set up progress listener
                tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        Log.d(TAG, "Started speaking: $utteranceId")
                        _ttsState.value = _ttsState.value.copy(isSpeaking = true)
                    }

                    override fun onDone(utteranceId: String?) {
                        Log.d(TAG, "Finished speaking: $utteranceId")
                        _ttsState.value = _ttsState.value.copy(isSpeaking = false)
                    }

                    override fun onError(utteranceId: String?) {
                        Log.e(TAG, "TTS error for utterance: $utteranceId")
                        _ttsState.value = _ttsState.value.copy(isSpeaking = false)
                    }
                })

                _ttsState.value = _ttsState.value.copy(isReady = true)
                Log.d(TAG, "TTS initialized successfully")

                // Welcome message
                val readyMsg = languageManager?.getString("Navigation system ready")
                    ?: "Navigation system ready"
                speak(readyMsg, force = true)

            }
        } else {
            Log.e(TAG, "TTS initialization failed with status: $status")
            _ttsState.value = _ttsState.value.copy(isReady = false)
        }
    }
    /**
     * TTS language
     */
    private fun updateTTSLanguage() {
        textToSpeech?.let { tts ->
            val locale = languageManager?.getCurrentLocale() ?: Locale.US
            val langResult = tts.setLanguage(locale)

            if (langResult == TextToSpeech.LANG_MISSING_DATA ||
                langResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.e(TAG, "Language ${locale.language} not supported, using English")
                tts.setLanguage(Locale.US)
            } else {
                Log.d(TAG, "TTS language set to: ${locale.displayLanguage}")
            }
        }
    }

    /**
     * Change language dynamically
     */
    fun changeLanguage(language: LanguageManager.Language) {
        languageManager?.setLanguage(language)
        updateTTSLanguage()

        val message = when (language) {
            LanguageManager.Language.ENGLISH -> "Language changed to English"
            LanguageManager.Language.FRENCH -> "Langue changée en français"
        }
        speak(message, force = true)
    }

    /**
     * Normalize instructions for consecutive checking
     */
    private fun normalizeInstruction(text: String): String {
        val normalized = text.lowercase()

        return when {
            // --- Navigation turns ---
            normalized.contains("turn left") -> "turn_left"
            normalized.contains("turn right") -> "turn_right"
            normalized.contains("turn") -> "turn"

            // --- Location references (rooms, exits, etc.) ---
            normalized.contains("your left") || normalized.contains("on your left") -> "location_left"
            normalized.contains("your right") || normalized.contains("on your right") -> "location_right"

            // --- General instructions ---
            normalized.contains("prepare") -> "prepare"
            normalized.contains("stop") -> "stop"
            normalized.contains("danger") -> "danger"
            normalized.contains("error") -> "error"
            normalized.contains("keep moving") -> "keep_moving"
            normalized.contains("wrong direction") -> "wrong_direction"
            normalized.contains("make") -> "make"

            normalized.contains("go straight") || normalized.contains("continue straight") -> "go_straight"
            normalized.contains("u-turn") -> "u_turn"

            // --- Fallback ---
            else -> normalized
        }
    }




    /**
     * Speak the given text with intelligent filtering and priority handling
     */
    fun speak(text: String, force: Boolean = false) {
        val currentState = _ttsState.value

        if (!currentState.isReady || !currentState.isEnabled || text.isBlank()) {
            Log.d(TAG, "TTS not ready or disabled, skipping: $text")
            return
        }

        val currentTime = System.currentTimeMillis()

        // Check if we should speak this instruction based on priority
        if (!force && !shouldSpeakWithPriority(text, currentTime, currentState)) {
            Log.d(TAG, "Skipping instruction: $text")
            return
        }

        // Stop current speech if speaking something else
        if (currentState.isSpeaking) {
            textToSpeech?.stop()
        }

        // Speak the instruction
        val utteranceId = "nav_instruction_$currentTime"
        val result = textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)

        if (result == TextToSpeech.SUCCESS) {
            _ttsState.value = _ttsState.value.copy(
                lastSpokenText = text,
                lastSpeechTime = currentTime
            )
            Log.d(TAG, "Speaking: $text")
        } else {
            Log.e(TAG, "Failed to speak: $text")
        }
    }

    /**
     * Determine if we should speak this text based on timing, content, and priority
     */
    private fun shouldSpeakWithPriority(text: String, currentTime: Long, state: TTSState): Boolean {
        // Always speak if nothing has been spoken yet
        if (state.lastSpeechTime == 0L) {
            lastNormalizedInstruction = normalizeInstruction(text)
            // Update timed never-miss time if applicable
            if (isNeverMissTimedInstruction(text)) {
                lastTimedNeverMissInstructionTimes[lastNormalizedInstruction] = currentTime
            }
            return true
        }

        val textLower = text.lowercase()
        val normalizedCurrentInstruction = normalizeInstruction(text)

        // Check if this is a never-miss no-consecutive instruction
        val isNeverMissNoConsecutive = isNeverMissNoConsecutiveInstruction(text)

        // Check if this is a never-miss timed instruction
        val isNeverMissTimed = isNeverMissTimedInstruction(text)

        // Handle never-miss no-consecutive instructions
        if (isNeverMissNoConsecutive) {
            // Don't speak if it's the same as the last instruction (prevent consecutive identical)
            if (normalizedCurrentInstruction == lastNormalizedInstruction) {
                Log.d(TAG, "Skipping consecutive identical never-miss no-consecutive instruction: $text")
                return false
            }

            // Always speak if it's different from last instruction
            Log.d(TAG, "Speaking never-miss no-consecutive instruction: $text")
            lastNormalizedInstruction = normalizedCurrentInstruction
            return true
        }

        // Handle never-miss timed instructions
        if (isNeverMissTimed) {
            val key = normalizedCurrentInstruction
            val lastTimeForKey = lastTimedNeverMissInstructionTimes[key] ?: 0L
            val timeSinceLastForKey = currentTime - lastTimeForKey

            if (timeSinceLastForKey < minTimeBetweenNeverMissInstructions) {
                Log.d(TAG, "Skipping never-miss timed instruction for key='$key' within window: $text (${timeSinceLastForKey}ms since last timed never-miss for this key)")
                return false
            }

            // Speak and update only this specific key's timestamp
            Log.d(TAG, "Speaking never-miss timed instruction for key='$key': $text")
            lastNormalizedInstruction = key
            lastTimedNeverMissInstructionTimes[key] = currentTime
            return true
        }

        // Check if this is a one-time instruction
        val isOneTime = oneTimeKeywords.any { keyword ->
            textLower.contains(keyword.lowercase())
        }

        // Handle one-time instructions
        if (isOneTime) {
            val normalizedText = normalizeOneTimeInstruction(text)
            if (spokenOneTimeInstructions.contains(normalizedText)) {
                Log.d(TAG, "One-time instruction already spoken: $text")
                return false
            }
            spokenOneTimeInstructions.add(normalizedText)
            lastNormalizedInstruction = normalizedCurrentInstruction
            return true
        }

        val timeSinceLastSpeech = currentTime - state.lastSpeechTime

        // Check if this is a critical instruction that should always be spoken
        val isCritical = criticalKeywords.any { keyword ->
            textLower.contains(keyword.lowercase())
        }

        // Check if this is a priority instruction
        val isPriority = priorityKeywords.any { keyword ->
            textLower.contains(keyword.lowercase())
        }

        // If it's the same instruction as last time
        if (text.equals(state.lastSpokenText, ignoreCase = true)) {
            val shouldSpeak = when {
                isCritical -> {
                    // Critical instructions can be repeated more frequently
                    Log.d(TAG, "Critical instruction detected: $text")
                    timeSinceLastSpeech >= minTimeBetweenPriorityInstructions
                }
                isPriority -> {
                    // Priority instructions use shorter interval
                    Log.d(TAG, "Priority instruction detected: $text")
                    timeSinceLastSpeech >= minTimeBetweenPriorityInstructions
                }
                else -> {
                    // Regular instructions use standard interval
                    timeSinceLastSpeech >= minTimeBetweenSameInstructions
                }
            }

            if (shouldSpeak) {
                lastNormalizedInstruction = normalizedCurrentInstruction
            }
            return shouldSpeak
        }

        // For different instructions, use appropriate interval based on priority
        val shouldSpeak = when {
            isCritical -> {
                // Critical instructions can interrupt more quickly
                timeSinceLastSpeech >= (minTimeBetweenAnyInstructions / 2)
            }
            isPriority -> {
                // Priority instructions use standard different-instruction interval
                timeSinceLastSpeech >= minTimeBetweenAnyInstructions
            }
            else -> {
                // Regular different instructions
                timeSinceLastSpeech >= minTimeBetweenAnyInstructions
            }
        }

        if (shouldSpeak) {
            lastNormalizedInstruction = normalizedCurrentInstruction
        }
        return shouldSpeak
    }

    /**
     * Normalize one-time instructions for comparison
     */
    private fun normalizeOneTimeInstruction(text: String): String {
        var normalized = text.lowercase()

        // Remove common direction words to create a base instruction
        val directionsToRemove = listOf("left", "right", "front", "behind", "ahead", "back")
        directionsToRemove.forEach { direction ->
            normalized = normalized.replace(direction, "").trim()
        }

        // Remove extra spaces and standardize
        normalized = normalized.replace(Regex("\\s+"), " ").trim()

        // Extract the core message
        return when {
            normalized.contains("reached") -> "reached_target"
            normalized.contains("completed") -> "completed_navigation"
            normalized.contains("finished") -> "finished_navigation"
            else -> normalized
        }
    }

    /**
     * Check if instruction contains one-time keywords
     */
    fun isOneTimeInstruction(text: String): Boolean {
        val textLower = text.lowercase()
        return oneTimeKeywords.any { keyword -> textLower.contains(keyword.lowercase()) }
    }

    /**
     * Check if instruction contains priority keywords
     */
    fun isPriorityInstruction(text: String): Boolean {
        val textLower = text.lowercase()
        return priorityKeywords.any { keyword -> textLower.contains(keyword.lowercase()) }
    }

    /**
     * Check if instruction contains critical keywords
     */
    fun isCriticalInstruction(text: String): Boolean {
        val textLower = text.lowercase()
        return criticalKeywords.any { keyword -> textLower.contains(keyword.lowercase()) }
    }

    /**
     * Check if instruction is never-miss no-consecutive type
     */
    fun isNeverMissNoConsecutiveInstruction(text: String): Boolean {
        val textLower = text.lowercase()
        return neverMissNoConsecutiveKeywords.any { keyword -> textLower.contains(keyword.lowercase()) }
    }

    /**
     * Check if instruction is never-miss timed type
     *
    fun isNeverMissTimedInstruction(text: String): Boolean {
    val textLower = text.lowercase()
    return neverMissTimedKeywords.any { keyword -> textLower.contains(keyword.lowercase()) }
    }
     */

    private fun isNeverMissTimedInstruction(text: String): Boolean {
        val textLower = text.lowercase().trim()
        return neverMissTimedKeywords.any { keyword ->
            // More specific matching - look for instruction phrases, not just keywords
            when (keyword) {
                "turn left" -> textLower.matches(Regex(".*\\bturn\\s+left\\b.*")) ||
                        textLower.matches(Regex(".*\\bmake.*left.*turn\\b.*"))
                "turn right" -> textLower.matches(Regex(".*\\bturn\\s+right\\b.*")) ||
                        textLower.matches(Regex(".*\\bmake.*right.*turn\\b.*"))
                else -> textLower.contains(keyword.lowercase())
            }
        }
    }

    /**
     * Check if instruction is any type of never-miss
     */
    fun isNeverMissInstruction(text: String): Boolean {
        return isNeverMissNoConsecutiveInstruction(text) || isNeverMissTimedInstruction(text)
    }

    /**
     * Speak with explicit priority override
     */
    fun speakPriority(text: String) {
        Log.d(TAG, "Speaking priority instruction: $text")

        val currentState = _ttsState.value
        if (!currentState.isReady || !currentState.isEnabled) {
            Log.d(TAG, "TTS not ready for priority instruction: $text")
            return
        }

        val normalizedCurrentInstruction = normalizeInstruction(text)
        val currentTime = System.currentTimeMillis()

        // Check for never-miss keywords
        val isNeverMissNoConsecutive = isNeverMissNoConsecutiveInstruction(text)
        val isNeverMissTimed = isNeverMissTimedInstruction(text)

        // Handle never-miss no-consecutive instructions
        if (isNeverMissNoConsecutive) {
            // Don't speak if it's the same as the last instruction
            if (normalizedCurrentInstruction == lastNormalizedInstruction) {
                Log.d(TAG, "Skipping consecutive identical never-miss no-consecutive priority instruction: $text")
                return
            }
        }

        // Handle never-miss timed instructions
        if (isNeverMissTimed) {
            val key = normalizedCurrentInstruction
            val lastTimeForKey = lastTimedNeverMissInstructionTimes[key] ?: 0L
            val timeSinceLastForKey = currentTime - lastTimeForKey

            if (timeSinceLastForKey < minTimeBetweenNeverMissInstructions) {
                Log.d(TAG, "Skipping never-miss timed priority instruction for key='$key' within window: $text (${timeSinceLastForKey}ms since last timed never-miss for this key)")
                return
            }

            // Update timed never-miss tracking for this key
            lastTimedNeverMissInstructionTimes[key] = currentTime
        }

        // Check if this is a one-time instruction that's already been spoken
        if (isOneTimeInstruction(text)) {
            val normalizedText = normalizeOneTimeInstruction(text)
            if (spokenOneTimeInstructions.contains(normalizedText)) {
                Log.d(TAG, "One-time priority instruction already spoken: $text")
                return
            }
            spokenOneTimeInstructions.add(normalizedText)
        }

        // Stop current speech immediately for priority instructions
        if (currentState.isSpeaking) {
            textToSpeech?.stop()
        }

        val utteranceId = "nav_priority_$currentTime"
        val result = textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)

        if (result == TextToSpeech.SUCCESS) {
            lastNormalizedInstruction = normalizedCurrentInstruction
            _ttsState.value = _ttsState.value.copy(
                lastSpokenText = text,
                lastSpeechTime = currentTime
            )
            Log.d(TAG, "Priority instruction spoken: $text")
        }
    }

    /**
     * Speak critical instruction
     */
    fun speakCritical(text: String) {
        Log.d(TAG, "Speaking critical instruction: $text")

        val currentState = _ttsState.value
        if (!currentState.isReady) {
            Log.e(TAG, "TTS not ready for critical instruction: $text")
            return
        }

        val normalizedCurrentInstruction = normalizeInstruction(text)
        val currentTime = System.currentTimeMillis()

        // Check for never-miss keywords
        val isNeverMissNoConsecutive = isNeverMissNoConsecutiveInstruction(text)
        val isNeverMissTimed = isNeverMissTimedInstruction(text)

        // Handle never-miss no-consecutive instructions
        if (isNeverMissNoConsecutive) {
            // Don't speak if it's the same as the last instruction
            if (normalizedCurrentInstruction == lastNormalizedInstruction) {
                Log.d(TAG, "Skipping consecutive identical never-miss no-consecutive critical instruction: $text")
                return
            }
        }

        // Handle never-miss timed instructions
        if (isNeverMissTimed) {
            val key = normalizedCurrentInstruction
            val lastTimeForKey = lastTimedNeverMissInstructionTimes[key] ?: 0L
            val timeSinceLastForKey = currentTime - lastTimeForKey

            if (timeSinceLastForKey < minTimeBetweenNeverMissInstructions) {
                Log.d(TAG, "Skipping never-miss timed priority instruction for key='$key' within window: $text (${timeSinceLastForKey}ms since last timed never-miss for this key)")
                return
            }

            // Update timed never-miss tracking for this key
            lastTimedNeverMissInstructionTimes[key] = currentTime
        }

        // Check if this is a one-time instruction that's already been spoken
        if (isOneTimeInstruction(text)) {
            val normalizedText = normalizeOneTimeInstruction(text)
            if (spokenOneTimeInstructions.contains(normalizedText)) {
                Log.d(TAG, "One-time critical instruction already spoken: $text")
                return
            }
            spokenOneTimeInstructions.add(normalizedText)
        }

        // Critical instructions work even if TTS is "disabled"
        if (currentState.isSpeaking) {
            textToSpeech?.stop()
        }

        val utteranceId = "nav_critical_$currentTime"
        val result = textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)

        if (result == TextToSpeech.SUCCESS) {
            lastNormalizedInstruction = normalizedCurrentInstruction
            _ttsState.value = _ttsState.value.copy(
                lastSpokenText = text,
                lastSpeechTime = currentTime
            )
            Log.d(TAG, "Critical instruction spoken: $text")
        }
    }

    /**
     * Enable or disable TTS
     */
    fun setEnabled(enabled: Boolean) {
        _ttsState.value = _ttsState.value.copy(isEnabled = enabled)

        if (!enabled) {
            // Stop current speech when disabling
            textToSpeech?.stop()
        } else {
            speak("Voice guidance enabled", force = true)
        }

        Log.d(TAG, "TTS ${if (enabled) "enabled" else "disabled"}")
    }


    /**
     * Emergency correction instructions that bypass ALL filtering
     */
    fun speakEmergencyCorrection(text: String) {
        Log.d(TAG, "EMERGENCY CORRECTION: $text")

        val currentState = _ttsState.value
        if (!currentState.isReady) {
            Log.e(TAG, "TTS not ready for emergency correction: $text")
            return
        }

        val currentTime = System.currentTimeMillis()
        val textLower = text.lowercase()

        // Define emergency correction keywords that trigger this method
        val emergencyCorrectionKeywords = listOf(
            "wrong direction", "backtrack"
        )

        // Verify this is actually an emergency correction
        val isEmergencyCorrection = emergencyCorrectionKeywords.any { keyword ->
            textLower.contains(keyword.lowercase())
        }

        if (!isEmergencyCorrection) {
            Log.w(TAG, "Not an emergency correction keyword, falling back to regular speakCritical: $text")
            speakCritical(text)
            return
        }

        Log.d(TAG, "Confirmed emergency correction - bypassing ALL filtering")

        // Stop any current speech immediately
        if (currentState.isSpeaking) {
            Log.d(TAG, "Stopping current speech for emergency correction")
            textToSpeech?.stop()
        }

        // Speak immediately with highest priority
        val utteranceId = "nav_emergency_$currentTime"
        val result = textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)

        if (result == TextToSpeech.SUCCESS) {

            _ttsState.value = _ttsState.value.copy(
                lastSpokenText = text,
                lastSpeechTime = currentTime
            )


            // Only update if the instruction contains never-miss timed keywords
            if (isNeverMissTimedInstruction(text)) {
                lastTimedNeverMissInstructionTimes[lastNormalizedInstruction] = currentTime
                Log.d(TAG, "Updated never-miss timing for emergency correction")
            }

            Log.d(TAG, "Emergency correction spoken successfully: $text")
        } else {
            Log.e(TAG, "Failed to speak emergency correction: $result")
        }
    }

    /**
     * Check if an instruction qualifies as an emergency correction
     */
    fun isEmergencyCorrection(text: String): Boolean {
        val textLower = text.lowercase()
        val emergencyKeywords = listOf(
            "wrong direction", "backtrack", "danger", "stop immediately",
            "emergency", "overshoot", "reversed", "error recovery"
        )

        return emergencyKeywords.any { keyword ->
            textLower.contains(keyword.lowercase())
        }
    }

    /**
     * Stop current speech
     */
    fun stop() {
        textToSpeech?.stop()
        _ttsState.value = _ttsState.value.copy(isSpeaking = false)
        Log.d(TAG, "TTS stopped")
    }

    /**
     * Repeat the last spoken instruction
     */
    fun repeatLastInstruction() {
        val lastText = _ttsState.value.lastSpokenText
        if (lastText.isNotBlank()) {
            speak(lastText, force = true)
        } else {
            speak("No previous instruction to repeat", force = true)
        }
    }

    /**
     * Reset message
     */
    fun resetInstruction() {
        val resetMessage = "System reset." // "Press Calibration button!"
        speak(resetMessage, force = true)
    }

    /**
     * Check if TTS is currently speaking
     */
    fun isSpeaking(): Boolean {
        return textToSpeech?.isSpeaking == true
    }

    /**
     * Reset one-time instruction tracking (call when starting new navigation)
     */
    fun resetOneTimeInstructions() {
        spokenOneTimeInstructions.clear()
        lastNormalizedInstruction = ""
        lastTimedNeverMissInstructionTimes.clear() // Also reset timed never-miss timing
        Log.d(TAG, "One-time instruction and timed never-miss timing reset")
    }

    /**
     * Check if a one-time instruction has been spoken
     */
    fun hasSpokenOneTimeInstruction(text: String): Boolean {
        val normalizedText = normalizeOneTimeInstruction(text)
        return spokenOneTimeInstructions.contains(normalizedText)
    }

    /**
     * Get TTS status information
     */
    fun getStatus(): Map<String, Any> {
        val state = _ttsState.value
        return mapOf(
            "isReady" to state.isReady,
            "isEnabled" to state.isEnabled,
            "isSpeaking" to state.isSpeaking,
            "hasSpoken" to (state.lastSpeechTime > 0),
            "lastInstruction" to state.lastSpokenText.take(50), // Truncated for display
            "lastNormalizedInstruction" to lastNormalizedInstruction,
            "lastInstructionPriority" to when {
                isOneTimeInstruction(state.lastSpokenText) -> "One-Time"
                isNeverMissNoConsecutiveInstruction(state.lastSpokenText) -> "Never-Miss No-Consecutive"
                isNeverMissTimedInstruction(state.lastSpokenText) -> "Never-Miss Timed"
                isCriticalInstruction(state.lastSpokenText) -> "Critical"
                isPriorityInstruction(state.lastSpokenText) -> "Priority"
                else -> "Regular"
            },
            "timeSinceLastSpeech" to if (state.lastSpeechTime > 0) {
                "${(System.currentTimeMillis() - state.lastSpeechTime) / 1000}s"
            } else "Never",
            "timeSinceLastTimedNeverMiss" to if (lastTimedNeverMissInstructionTimes.isNotEmpty()) {
                val lastTime = lastTimedNeverMissInstructionTimes.values.maxOrNull() ?: 0L
                "${(System.currentTimeMillis() - lastTime) / 1000}s"
            } else "Never",
            "neverMissNoConsecutiveKeywords" to neverMissNoConsecutiveKeywords.size,
            "neverMissTimedKeywords" to neverMissTimedKeywords.size,
            "priorityKeywords" to priorityKeywords.size,
            "criticalKeywords" to criticalKeywords.size,
            "oneTimeKeywords" to oneTimeKeywords.size,
            "spokenOneTimeInstructions" to spokenOneTimeInstructions.size,
            "minTimeBetweenNeverMiss" to "${minTimeBetweenNeverMissInstructions}ms"
        )
    }

    /**
     * Configure timing intervals (for testing/tuning)
     */
    fun configureTiming(
        regularInterval: Long? = null,
        priorityInterval: Long? = null,
        differentInstructionInterval: Long? = null
    ) {
        // Note: These are val properties, so you'd need to make them var if you want runtime configuration
        Log.d(TAG, "Timing configuration requested but properties are immutable")
        Log.d(TAG, "Current intervals - Regular: ${minTimeBetweenSameInstructions}ms, Priority: ${minTimeBetweenPriorityInstructions}ms, Different: ${minTimeBetweenAnyInstructions}ms, Timed Never-Miss: ${minTimeBetweenNeverMissInstructions}ms")
    }

    /**
     * Force speak an instruction (bypasses all filtering except never-miss 3-second rule)
     */
    fun forceSpeak(text: String) {
        val normalizedCurrentInstruction = normalizeInstruction(text)
        val currentTime = System.currentTimeMillis()
        val isNeverMissNoConsecutive = isNeverMissNoConsecutiveInstruction(text)
        val isNeverMissTimed = isNeverMissTimedInstruction(text)

        // Handle never-miss no-consecutive instructions
        if (isNeverMissNoConsecutive) {
            // Don't speak if it's the same as the last instruction
            if (normalizedCurrentInstruction == lastNormalizedInstruction) {
                Log.d(TAG, "Skipping consecutive identical never-miss no-consecutive forced instruction: $text")
                return
            }
        }

        // Handle never-miss timed instructions
        if (isNeverMissTimed) {
            val key = normalizedCurrentInstruction
            val lastTimeForKey = lastTimedNeverMissInstructionTimes[key] ?: 0L
            val timeSinceLastForKey = currentTime - lastTimeForKey

            if (timeSinceLastForKey < minTimeBetweenNeverMissInstructions) {
                Log.d(TAG, "Skipping never-miss timed priority instruction for key='$key' within window: $text (${timeSinceLastForKey}ms since last timed never-miss for this key)")
                return
            }

            // Update timed never-miss tracking for this key
            lastTimedNeverMissInstructionTimes[key] = currentTime
        }

        val currentState = _ttsState.value
        if (!currentState.isReady) {
            Log.e(TAG, "TTS not ready for forced instruction: $text")
            return
        }

        // Stop current speech
        if (currentState.isSpeaking) {
            textToSpeech?.stop()
        }

        val utteranceId = "nav_forced_$currentTime"
        val result = textToSpeech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)

        if (result == TextToSpeech.SUCCESS) {
            lastNormalizedInstruction = normalizedCurrentInstruction
            _ttsState.value = _ttsState.value.copy(
                lastSpokenText = text,
                lastSpeechTime = currentTime
            )
            Log.d(TAG, "Forced instruction spoken: $text")
        }
    }

    /**
     * Cleanup TTS resources
     */
    fun cleanup() {
        Log.d(TAG, "Cleaning up TTS resources")
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        lastNormalizedInstruction = ""
        lastTimedNeverMissInstructionTimes.clear() // Reset timed never-miss timing
        spokenOneTimeInstructions.clear()
        _ttsState.value = TTSState() // Reset to default state
    }
}