/* ConversationManager.kt - Ollama-Based Intelligent Version
package com.example.imunavigation.conversation

import android.content.Context
import android.speech.SpeechRecognizer
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.example.imunavigation.api.NavigationAPI
import com.example.imunavigation.navigation.InitializeRequest
import com.example.imunavigation.tts.TTSManager
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.google.gson.Gson
import org.json.JSONObject
import android.media.AudioManager
import android.media.ToneGenerator

val gson = Gson()

/**
 * Manages conversation-based navigation with Ollama integration
 * Uses intelligent location extraction for natural language understanding
 */
class ConversationManager(
    private val context: Context,
    private val navigationAPI: NavigationAPI,
    private val ollamaAPI: OllamaAPI,
    private val ttsManager: TTSManager,
    private val apiKey: String? = null
) {
    companion object {
        private const val TAG = "ConversationManager"
        private const val DEFAULT_MODEL = "Qwen/Qwen3-VL-4B-Instruct" //"Qwen/Qwen3-VL-4B-Instruct"//"llama2"  // You can change this to your preferred model
    }

    data class ConversationState(
        val isActive: Boolean = false,
        val isListening: Boolean = false,
        val currentMessage: String = "",
        val llmResponse: String = "",
        val hasRouteData: Boolean = false,
        val isProcessing: Boolean = false,
        val errorMessage: String? = null,
        val conversationHistory: List<ChatMessage> = emptyList()
    )

    data class ChatMessage(
        val message: String,
        val isUser: Boolean,
        val timestamp: Long = System.currentTimeMillis()
    )

    data class LocationIntent(
        val isNewRouteRequest: Boolean = false,
        val isQuestionAboutRoute: Boolean = false,
        val needsClarification: Boolean = false,
        val source: String? = null,
        val destination: String? = null,
        val clarificationMessage: String? = null
    )

    private val _conversationState = MutableStateFlow(ConversationState())
    val conversationState: StateFlow<ConversationState> = _conversationState.asStateFlow()

    private val conversationScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var speechRecognizer: SpeechRecognizer? = null
    private var routeData: String? = null
    private var sourceLocation: String? = null
    private var destinationLocation: String? = null

    // Track conversation context for better LLM understanding
    private val conversationContext = mutableListOf<String>()

    /**
     * Start conversation mode
     */
    fun startConversationMode() {
        Log.d(TAG, "Starting conversation mode")
        _conversationState.value = _conversationState.value.copy(
            isActive = true,
            currentMessage = "Conversation mode activated. How can I help you navigate?",
            errorMessage = null
        )

        ttsManager.speakPriority("Conversation mode activated. How can I help you navigate?")
        initializeSpeechRecognizer()
    }

    /**
     * Stop conversation mode
     */
    fun stopConversationMode() {
        Log.d(TAG, "Stopping conversation mode")
        speechRecognizer?.destroy()
        speechRecognizer = null
        routeData = null
        sourceLocation = null
        destinationLocation = null
        conversationContext.clear()

        _conversationState.value = ConversationState()
        ttsManager.speakPriority("Conversation mode deactivated")
    }

    /**
     * Start listening for voice input
     */
    fun startListening() {
        if (!_conversationState.value.isActive) {
            Log.w(TAG, "Cannot start listening - conversation mode not active")
            return
        }

        Log.d(TAG, "Starting voice recognition")
        _conversationState.value = _conversationState.value.copy(
            isListening = true,
            errorMessage = null
        )

        // Delay before starting speech recognizer to give user time
        conversationScope.launch {
            playFeedbackBeep(context, "start")

            ttsManager.speakPriority("Listening")
            delay(200) // 0.2 seconds for user to prepare

            withContext(Dispatchers.Main) {
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                    putExtra(RecognizerIntent.EXTRA_PROMPT, "Ask about navigation...")
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)

                    // Generous timeouts for natural speech patterns
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 7000L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 6000L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 5000L)
                }

                try {
                    speechRecognizer?.startListening(intent)
                } catch (e: Exception) {
                    Log.e(TAG, "Error starting speech recognition: ${e.message}")
                    ttsManager.speakPriority("Failed to start listening")
                    _conversationState.value = _conversationState.value.copy(
                        isListening = false,
                        errorMessage = "Voice recognition error: ${e.message}"
                    )
                }
            }
        }
    }

    /**
     * Stop listening
     */
    fun stopListening() {
        speechRecognizer?.stopListening()
        playFeedbackBeep(context, "end")
        _conversationState.value = _conversationState.value.copy(isListening = false)
    }

    /**
     * Process text input from user
     */
    fun processTextInput(userInput: String) {
        if (!_conversationState.value.isActive) return

        Log.d(TAG, "Processing text input: $userInput")

        // Add user message to history
        val updatedHistory = _conversationState.value.conversationHistory +
                ChatMessage(userInput, isUser = true)

        _conversationState.value = _conversationState.value.copy(
            currentMessage = userInput,
            isProcessing = true,
            conversationHistory = updatedHistory
        )

        conversationScope.launch {
            try {
                // Step 1: Use Ollama to understand the intent and extract locations
                val locationIntent = extractLocationsWithLLM(userInput)

                Log.d(TAG, "Location intent: isNewRoute=${locationIntent.isNewRouteRequest}, " +
                        "needsClarification=${locationIntent.needsClarification}, " +
                        "source=${locationIntent.source}, dest=${locationIntent.destination}")

                when {
                    // New route request detected with both locations
                    locationIntent.isNewRouteRequest &&
                            locationIntent.source != null &&
                            locationIntent.destination != null -> {
                        Log.d(TAG, "Processing new route request")
                        // Reset and fetch new route
                        routeData = null
                        sourceLocation = locationIntent.source
                        destinationLocation = locationIntent.destination
                        _conversationState.value = _conversationState.value.copy(hasRouteData = false)

                        fetchRouteDataAndRespond(
                            locationIntent.source!!,
                            locationIntent.destination!!,
                            userInput
                        )
                    }

                    // Clarification needed - missing information
                    locationIntent.needsClarification -> {
                        Log.d(TAG, "Needs clarification")
                        // Update what we know so far
                        if (locationIntent.source != null) sourceLocation = locationIntent.source
                        if (locationIntent.destination != null) destinationLocation = locationIntent.destination

                        // Provide specific clarification based on what's missing
                        val clarificationMsg = when {
                            sourceLocation == null && destinationLocation == null ->
                                "Please tell me both your starting point and destination."
                            sourceLocation == null ->
                                "Where are you starting from? I know you want to go to $destinationLocation."
                            destinationLocation == null ->
                                "Where would you like to go? I know you're starting from $sourceLocation."
                            else ->
                                "Could you please provide both your starting location and destination?"
                        }

                        handleLLMResponse(locationIntent.clarificationMessage ?: clarificationMsg)
                    }

                    // Question about existing route
                    _conversationState.value.hasRouteData && locationIntent.isQuestionAboutRoute -> {
                        Log.d(TAG, "Question about existing route")
                        processWithLLM(userInput)
                    }

                    // General conversation or unclear intent
                    else -> {
                        Log.d(TAG, "General conversation/unclear intent")
                        processWithLLM(userInput)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing input: ${e.message}", e)
                _conversationState.value = _conversationState.value.copy(
                    isProcessing = false,
                    errorMessage = "Processing error: ${e.message}"
                )
            }
        }
    }

    /**
     * Use Ollama to intelligently extract locations and understand intent
     */
    private suspend fun extractLocationsWithLLM(userInput: String): LocationIntent {
        val extractionPrompt = buildLocationExtractionPrompt(userInput)

        try {
            val response = sendToOllama(extractionPrompt)
            Log.d(TAG, "Ollama extraction response: $response")
            return parseLocationIntent(response)
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting locations with Ollama: ${e.message}")
            // Fallback to basic processing
            return LocationIntent(
                isNewRouteRequest = false,
                needsClarification = false,
                source = sourceLocation,
                destination = destinationLocation
            )
        }
    }

    /**
     * Build prompt for location extraction
     */
    private fun buildLocationExtractionPrompt(userInput: String): String {
        return """
You are a location extraction assistant for an indoor navigation system. 
Your job is to analyze user input and extract navigation-related information.

Current context:
- Known source: ${sourceLocation ?: "none"}
- Known destination: ${destinationLocation ?: "none"}
- Has route data: ${_conversationState.value.hasRouteData}

Recent conversation context:
${conversationContext.takeLast(3).joinToString("\n")}

CRITICAL: Location name normalization rules:
- Remove ALL spaces from location names
- Convert to lowercase
- Keep as a single word
- Examples:
  * "female restroom" → "femalerestroom"
  * "male restroom" → "malerestroom"  
  * "water fountain" → "waterfountain"
  * "room 435" → "room435"
  * "room 1" → "room1"
  * "room one" → "room1"
  * "roomone" → "room1"
  * "toilet" → "restroom"
  * "main entrance" → "mainentrance"
  * "Room 435" → "room435"
  * "UPRINT" → "uprint"
  
IMPORTANT - CONTEXT CONTINUATION:
- If source is ALREADY KNOWN, keep it unless user explicitly changes it
- If destination is ALREADY KNOWN, keep it unless user explicitly changes it
- If user provides ONLY source (e.g., "from room 424"), combine with known destination
- If user provides ONLY destination (e.g., "to room 435"), combine with known source
- Examples:
  * Known: destination="room435", source=none, User says: "from room 424" → Keep destination="room435", add source="room424", is_new_route_request=true
  * Known: source="entrance", destination=none, User says: "to the library" → Keep source="entrance", add destination="library", is_new_route_request=true

Analyze the user's message and respond with ONLY a JSON object in this exact format:
{
  "is_new_route_request": true/false,
  "is_question_about_route": true/false,
  "needs_clarification": true/false,
  "source": "normalized_source_location",
  "destination": "normalized_destination_location",
  "clarification_message": "message to ask user for missing info, or null"
}

Rules:
1. is_new_route_request = true if user wants directions to a NEW place OR is providing missing info to complete a route request
2. is_question_about_route = true if asking about an EXISTING route (keywords: "how far", "how long", "what floor", "describe", "explain", "tell me about")
3. needs_clarification = true ONLY if BOTH source AND destination are still missing after this message
4. Extract location names naturally - they can be ANYTHING (room numbers, building names, landmarks, places like "uprint", "entrance", "library", etc.)
5. For "from X to Y" patterns, X is source, Y is destination
6. For "to X from Y" patterns, Y is source, X is destination
7. For "go to X" or "navigate to X" without "from", X is destination
8. For "from X" alone, X is source (keep existing destination if known)
9. If user is correcting/changing a location, update the relevant field
10. Location names can be single words or multiple words
11. PRESERVE already known information unless user explicitly changes it

Examples:
- "how do I go to uprint from entrance" → source: "entrance", destination: "uprint"
- Known destination="room435", User: "from room 424" → source: "room424", destination: "room435", is_new_route_request: true
- Known source="entrance", User: "to the library" → source: "entrance", destination: "library", is_new_route_request: true
- "navigate to the library" → destination: "library", source: null, needs_clarification: true
- "how long will it take" (with existing route) → is_question_about_route: true

DO NOT include any text outside the JSON object. DO NOT use markdown code blocks. ONLY output valid JSON.

User message: "$userInput"
        """.trimIndent()
    }

    /**
     * Parse LLM response into LocationIntent
     */
    private fun parseLocationIntent(llmResponse: String): LocationIntent {
        return try {
            // Clean response - remove markdown code blocks if present
            val cleanResponse = llmResponse
                .replace("```json", "")
                .replace("```", "")
                .trim()

            Log.d(TAG, "Parsing JSON: $cleanResponse")

            val jsonObject = JSONObject(cleanResponse)

            LocationIntent(
                isNewRouteRequest = jsonObject.optBoolean("is_new_route_request", false),
                isQuestionAboutRoute = jsonObject.optBoolean("is_question_about_route", false),
                needsClarification = jsonObject.optBoolean("needs_clarification", false),
                source = jsonObject.optString("source").takeIf { it != "null" && it.isNotEmpty() },
                destination = jsonObject.optString("destination").takeIf { it != "null" && it.isNotEmpty() },
                clarificationMessage = jsonObject.optString("clarification_message").takeIf { it != "null" && it.isNotEmpty() }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing location intent: ${e.message}")
            Log.e(TAG, "Ollama Response was: $llmResponse")
            LocationIntent()
        }
    }

    /**
     * Fetch route data and respond to user
     */
    private suspend fun fetchRouteDataAndRespond(
        source: String,
        destination: String,
        userInput: String
    ) {
        try {
            Log.d(TAG, "Getting route data from '$source' to '$destination'")

            val sessionId = "conversation_session_${System.currentTimeMillis()}"
            val initResponse = navigationAPI.initialize(
                InitializeRequest(
                    source = source,
                    destination = destination,
                    conversationMode = true
                ),
                sessionId
            )

            if (initResponse.status == "success") {
                // Extract route data
                routeData = if (initResponse.conversation_mode == true) {
                    initResponse.conversation_data?.let { data ->
                        gson.toJson(data)
                    }
                } else {
                    initResponse.message ?: initResponse.instructions
                }

                sourceLocation = source
                destinationLocation = destination

                Log.d(TAG, "Route data received successfully: ${routeData?.take(200)}...")

                withContext(Dispatchers.Main) {
                    _conversationState.value = _conversationState.value.copy(
                        hasRouteData = true,
                        isProcessing = false
                    )
                }

                // Add to context
                conversationContext.add("User requested route from $source to $destination")

                // Now process with Ollama to generate natural response
                processWithLLM(userInput)

            } else {
                throw Exception("Navigation API error: ${initResponse.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting route data: ${e.message}", e)
            val errorMsg = "I couldn't find a route from $source to $destination. Please verify the location names are correct."
            handleLLMResponse(errorMsg)
        }
    }

    /**
     * Process user input with Ollama (for questions about existing routes or general conversation)
     */
    private suspend fun processWithLLM(userInput: String) {
        try {
            val ollamaPrompt = buildNavigationPrompt(userInput)
            val llmResponse = sendToOllama(ollamaPrompt)
            handleLLMResponse(llmResponse)

            // Update context
            conversationContext.add("User: $userInput")
            conversationContext.add("Assistant: $llmResponse")

            // Keep context size manageable
            if (conversationContext.size > 10) {
                conversationContext.removeAt(0)
                conversationContext.removeAt(0)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error processing with Ollama: ${e.message}", e)
            handleLLMResponse("I'm having trouble processing your request. Please try again.")
        }
    }

    /**
     * Build Ollama prompt for navigation conversation
     */
    private fun buildNavigationPrompt(userInput: String): String {
        val wantsDetails = isRequestingDetailedInstructions(userInput)

        val systemInstructions = """
You are a helpful indoor navigation assistant providing clear directions.

${if (!wantsDetails) {
            """
        INITIAL DIRECTION REQUEST:
        1. If the route data has a "summary" or "overview" field, USE THAT FIRST
        2. Otherwise, create a brief 2-3 sentence summary by:
        - Combining consecutive similar actions (add up steps: 2+5+3 = 10 steps)
        - Only mentioning major turns and landmarks
                - Keeping it conversational and easy to remember

        Example good summary: "Walk straight for 15 steps, turn right at the water fountain, continue for 8 steps, and the destination is on your left."
        Example bad summary: "Walk 2 steps. Continue 3 steps. Walk 5 steps. Continue 5 steps. Turn right. Walk 3 steps. Continue 5 steps..."
        """
        } else {
            """
        DETAILED INSTRUCTIONS REQUESTED:
        - Provide complete step-by-step directions with all details
        - Include every landmark mentioned in the route data
                - Be thorough and precise
        """
        }}

    IMPORTANT - POLITE ACKNOWLEDGMENTS:
    If the user says something like "ok", "thanks", "thank you", "got it", "okay", "alright", "cool", or any simple acknowledgment:
    - Respond briefly with: "You're welcome!" or "Happy to help!" or "No problem!"
    - DO NOT repeat navigation instructions
    - DO NOT provide directions again
    - Keep it short and friendly
    - Examples:
      * User: "Ok. Thank you." → Response: "You're welcome!"
      * User: "Thanks" → Response: "Happy to help!"
      * User: "Got it, thanks" → Response: "Great! Let me know if you need anything else."
      * User: "Okay" → Response: "You're welcome!"

    Always be friendly and natural. Don't use numbered lists unless asked.
            """.trimIndent()

        // Build conversation history
        val conversationHistory = buildString {
            _conversationState.value.conversationHistory.takeLast(4).forEach { msg ->
                if (msg.isUser) {
                    append("User: ${msg.message}\n")
                } else {
                    append("Assistant: ${msg.message}\n")
                }
            }
        }

        // Build the complete prompt
        return buildString {
            append(systemInstructions)
            append("\n\n")
            if (conversationHistory.isNotEmpty()) {
                append("Previous conversation:\n")
                append(conversationHistory)
                append("\n")
            }
            if (routeData != null) {
                append("Route data:\n")
                append(routeData)
                append("\n\n")
            }
            append("User: $userInput\n")
            append("Assistant:")
        }
    }

    /**
     * Handle LLM response and update UI
     */
    private suspend fun handleLLMResponse(response: String) {
        withContext(Dispatchers.Main) {
            val updatedHistory = _conversationState.value.conversationHistory +
                    ChatMessage(response, isUser = false)

            _conversationState.value = _conversationState.value.copy(
                llmResponse = response,
                isProcessing = false,
                conversationHistory = updatedHistory
            )

            ttsManager.speakPriority(response)
        }
    }

    /**
     * Initialize speech recognizer
     */
    private fun initializeSpeechRecognizer() {
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.d(TAG, "Ready for speech")
            }

            override fun onBeginningOfSpeech() {
                Log.d(TAG, "Beginning of speech")
            }

            override fun onRmsChanged(rmsdB: Float) {}

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {
                Log.d(TAG, "End of speech")
            }

            override fun onError(error: Int) {
                when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH,
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                        // Don't treat these as errors - just restart listening
                        Log.d(TAG, "No speech detected yet, restarting listener...")

                        conversationScope.launch {
                            // Play a subtle beep to remind user we're still listening
                            playFeedbackBeep(context, "start")
                            delay(200)

                            withContext(Dispatchers.Main) {
                                // Check if still in listening mode
                                if (_conversationState.value.isListening) {
                                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                                        putExtra(RecognizerIntent.EXTRA_PROMPT, "Ask about navigation...")
                                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 7000L)
                                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 6000L)
                                        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 5000L)
                                    }

                                    try {
                                        speechRecognizer?.startListening(intent)
                                        Log.d(TAG, "Successfully restarted listening")
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Failed to restart listening: ${e.message}")
                                        ttsManager.speakPriority("Voice input stopped")
                                        _conversationState.value = _conversationState.value.copy(
                                            isListening = false,
                                            errorMessage = "Failed to restart listening"
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Real errors that should stop listening
                    else -> {
                        val errorMessage = when (error) {
                            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                            SpeechRecognizer.ERROR_CLIENT -> "Client side error"
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
                            SpeechRecognizer.ERROR_NETWORK -> "Network error"
                            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognition service busy"
                            SpeechRecognizer.ERROR_SERVER -> "Server error"
                            else -> "Voice recognition failed"
                        }

                        Log.e(TAG, "Speech recognition error: $error - $errorMessage")
                        playFeedbackBeep(context, "error")
                        ttsManager.speakPriority(errorMessage)

                        _conversationState.value = _conversationState.value.copy(
                            isListening = false,
                            errorMessage = errorMessage
                        )
                    }
                }
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    val spokenText = matches[0]
                    Log.d(TAG, "Speech recognized: $spokenText")
                    playFeedbackBeep(context, "end")

                    // NOW stop listening since we got speech
                    _conversationState.value = _conversationState.value.copy(isListening = false)

                    ttsManager.speakPriority("processing")
                    processTextInput(spokenText)
                } else {
                    // Empty results - restart listening automatically
                    Log.w(TAG, "Empty results, restarting...")
                    conversationScope.launch {
                        delay(300)
                        playFeedbackBeep(context, "start")
                        delay(200)

                        withContext(Dispatchers.Main) {
                            if (_conversationState.value.isListening) {
                                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                                    putExtra(RecognizerIntent.EXTRA_PROMPT, "Ask about navigation...")
                                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 7000L)
                                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 6000L)
                                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 5000L)
                                }
                                try {
                                    speechRecognizer?.startListening(intent)
                                } catch (e: Exception) {
                                    Log.e(TAG, "Failed to restart: ${e.message}")
                                }
                            }
                        }
                    }
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {}

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
    }

    /**
     * Send request to Ollama API
     */
    /**
     * Send request to Ollama API (OpenAI-compatible format)
     */
    private suspend fun sendToOllama(prompt: String): String {
        val ollamaApiKey = apiKey ?: run {
            Log.e(TAG, "Ollama API key not provided")
            return "Sorry, AI conversation is not available. API key not configured."
        }

        if (ollamaApiKey.isBlank()) {
            Log.e(TAG, "Ollama API key is empty")
            return "Sorry, AI conversation is not available."
        }

        try {
            // OpenAI-compatible request format
            val request = OllamaRequest(
                model = DEFAULT_MODEL,
                messages = listOf(
                    Message(role = "user", content = prompt)
                ),
                temperature = 0.2,
                max_tokens = 512,
                stream = false
            )

            Log.d(TAG, "Sending request to Ollama: model=${DEFAULT_MODEL}, prompt length=${prompt.length}")

            val response = ollamaAPI.generate(
                authorization = "Bearer $ollamaApiKey",
                request = request
            )

            Log.d(TAG, "Response code: ${response.code()}")

            if (response.isSuccessful && response.body() != null) {
                val ollamaResponse = response.body()!!

                // Extract response from choices array
                if (ollamaResponse.choices.isNotEmpty()) {
                    val responseText = ollamaResponse.choices[0].message.content.trim()
                    Log.d(TAG, "Successfully received response: ${responseText.take(100)}...")
                    return responseText
                } else {
                    Log.e(TAG, "Response has no choices")
                    return "I received an empty response from the AI service."
                }
            } else {
                val errorBody = response.errorBody()?.string()
                Log.e(TAG, "Ollama API error: ${response.code()} - $errorBody")
                return "I'm having trouble connecting to the AI service. Please try again."
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error calling Ollama API: ${e.message}", e)
            e.printStackTrace()
            return "I'm having trouble processing your request. Please try again."
        }
    }
    /**
     * Check if user is asking for detailed/step-by-step instructions
     */
    private fun isRequestingDetailedInstructions(input: String): Boolean {
        val detailKeywords = listOf(
            "step by step",
            "more details",
            "detailed",
            "explain",
            "elaborate",
            "tell me more",
            "specifically",
            "exactly how"
        )
        val lowerInput = input.lowercase()
        return detailKeywords.any { lowerInput.contains(it) }
    }

    private fun playFeedbackBeep(context: Context, type: String) {
        conversationScope.launch(Dispatchers.Main) {
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

                // Check if volume is reasonable
                val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                if (currentVolume == 0) {
                    Log.w(TAG, "Volume is muted - beep won't be audible")
                }

                val toneGenerator = ToneGenerator(
                    AudioManager.STREAM_MUSIC,  // Changed to STREAM_MUSIC for better audibility
                    80  // Volume: 0-100, slightly reduced from 100
                )

                // Play the appropriate tone
                val success = when(type) {
                    "start" -> toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
                    "end" -> toneGenerator.startTone(ToneGenerator.TONE_PROP_ACK, 150)  // Different tone
                    "error" -> toneGenerator.startTone(ToneGenerator.TONE_PROP_NACK, 200)  // Error tone
                    else -> false
                }

                if (!success) {
                    Log.e(TAG, "Failed to play beep tone")
                }

                // Wait for tone to finish playing before releasing
                delay(300)  // Increased delay
                toneGenerator.release()

            } catch (e: Exception) {
                Log.e(TAG, "Error playing feedback beep: ${e.message}", e)
            }
        }
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        Log.d(TAG, "Cleaning up conversation manager")
        speechRecognizer?.destroy()
        conversationScope.cancel()
        conversationContext.clear()
    }
}*/