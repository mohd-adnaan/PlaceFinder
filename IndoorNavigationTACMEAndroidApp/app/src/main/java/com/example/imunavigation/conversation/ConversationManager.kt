// ConversationManager.kt - GPT-Based Intelligent Version
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
import com.example.imunavigation.language.LanguageManager

val gson = Gson()

/**
 * Manages conversation-based navigation with GPT integration
 * Uses intelligent location extraction for natural language understanding
 */
class ConversationManager(
    private val context: Context,
    private val navigationAPI: NavigationAPI,
    private val openAIAPI: OpenAIAPI,
    private val ttsManager: TTSManager,
    private val languageManager: LanguageManager,
    private val apiKey: String? = null
) {
    companion object {
        private const val TAG = "ConversationManager"
    }

    data class ConversationState(
        val isActive: Boolean = false,
        val isListening: Boolean = false,
        val currentMessage: String = "",
        val gptResponse: String = "",
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

    // Track conversation context for better GPT understanding
    private val conversationContext = mutableListOf<String>()

    /**
     * Start conversation mode
     */
    fun startConversationMode() {
        Log.d(TAG, "Starting conversation mode")
        val message = languageManager.getString("Conversation mode activated. How can I help you navigate?")
        _conversationState.value = _conversationState.value.copy(
            isActive = true,
            currentMessage = message,
            errorMessage = null
        )

        ttsManager.speakPriority(message)
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
        val message = languageManager.getString("Conversation mode deactivated")
        ttsManager.speakPriority(message)

    }

    /**
     * Start listening for voice input
     */
    fun startListening() {
        if (!_conversationState.value.isActive) {
            Log.w(TAG, "Cannot start listening - conversation mode not active")
            return
        }
        // NEW: Get current language for speech recognition
        val currentLang = languageManager.getCurrentLanguage()
        Log.d(TAG, "Starting voice recognition in ${currentLang.displayName}")

        Log.d(TAG, "Starting voice recognition")
        _conversationState.value = _conversationState.value.copy(
            isListening = true,
            errorMessage = null
        )

        // Delay before starting speech recognizer to give user time
        conversationScope.launch {
            playFeedbackBeep(context, "start")



            val listeningMsg = languageManager.getString("Listening")
            ttsManager.speakPriority(listeningMsg)
            delay(200) // 0.2 seconds for user to prepare

            withContext(Dispatchers.Main) {
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    val languageCode = when (currentLang) {
                        LanguageManager.Language.ENGLISH -> "en-US"
                        LanguageManager.Language.FRENCH -> "fr-CA"
                    }
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode)
                    val promptMsg = languageManager.getString("Ask about navigation...")
                    putExtra(RecognizerIntent.EXTRA_PROMPT, promptMsg)
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
                    val errorMsg = languageManager.getString("Failed to start listening")
                    ttsManager.speakPriority(errorMsg)
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

                val englishInput = if (languageManager.isFrench()) {
                    Log.d(TAG, "Translating French to English...")
                    languageManager.translateToEnglish(userInput)
                } else {
                    userInput
                }

                Log.d(TAG, "English input for processing: $englishInput")
                // Use GPT to understand the intent and extract locations
                val locationIntent = extractLocationsWithGPT(englishInput)

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
                            englishInput
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


                        handleGPTResponse(locationIntent.clarificationMessage ?: clarificationMsg)
                    }

                    // Question about existing route
                    _conversationState.value.hasRouteData && locationIntent.isQuestionAboutRoute -> {
                        Log.d(TAG, "Question about existing route")
                        processWithGPT(englishInput)
                    }

                    // General conversation or unclear intent
                    else -> {
                        Log.d(TAG, "General conversation/unclear intent")
                        processWithGPT(englishInput)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing input: ${e.message}", e)
                val errorMsg = languageManager.getString("Processing error: ${e.message}")
                _conversationState.value = _conversationState.value.copy(
                    isProcessing = false,
                    errorMessage = errorMsg
                )
            }
        }
    }

    /**
     * Use GPT to intelligently extract locations and understand intent
     */
    private suspend fun extractLocationsWithGPT(userInput: String): LocationIntent {
        val extractionPrompt = buildLocationExtractionPrompt(userInput)

        try {
            val response = sendToGPT(extractionPrompt)
            Log.d(TAG, "GPT extraction response: $response")
            return parseLocationIntent(response)
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting locations with GPT: ${e.message}")
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
    private fun buildLocationExtractionPrompt(userInput: String): GPTRequest {
        val systemPrompt = """
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
  * "roomone" → "room1
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
        """.trimIndent()

        return GPTRequest(
            model = "gpt-4o-mini",
            messages = listOf(
                GPTMessage("system", systemPrompt),
                GPTMessage("user", userInput)
            ),
            maxTokens = 300,
            temperature = 0.1  // Low temperature for consistent structured output
        )
    }

    /**
     * Parse GPT response into LocationIntent
     */
    private fun parseLocationIntent(gptResponse: String): LocationIntent {
        return try {
            // Clean response - remove markdown code blocks if present
            val cleanResponse = gptResponse
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
            Log.e(TAG, "GPT Response was: $gptResponse")
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

                // Now process with GPT to generate natural response
                processWithGPT(userInput)

            } else {
                throw Exception("Navigation API error: ${initResponse.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting route data: ${e.message}", e)
            val errorMsg = "I couldn't find a route from $source to $destination. Please verify the location names are correct."
            handleGPTResponse(errorMsg)
        }
    }

    /**
     * Process user input with GPT (for questions about existing routes or general conversation)
     */
    private suspend fun processWithGPT(userInput: String) {
        try {
            val gptRequest = buildNavigationGPTRequest(userInput)
            val gptResponse = sendToGPT(gptRequest)
            handleGPTResponse(gptResponse)

            // Update context
            conversationContext.add("User: $userInput")
            conversationContext.add("Assistant: $gptResponse")

            // Keep context size manageable
            if (conversationContext.size > 10) {
                conversationContext.removeAt(0)
                conversationContext.removeAt(0)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error processing with GPT: ${e.message}", e)
            handleGPTResponse("I'm having trouble processing your request. Please try again.")
        }
    }

    /**
     * Build GPT request for navigation conversation
     */
    private fun buildNavigationGPTRequest(userInput: String): GPTRequest {
        val wantsDetails = isRequestingDetailedInstructions(userInput)

        val systemPrompt = """
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

        val messages = mutableListOf<GPTMessage>().apply {
            add(GPTMessage("system", systemPrompt))

            _conversationState.value.conversationHistory.takeLast(4).forEach { msg ->
                add(GPTMessage(
                    if (msg.isUser) "user" else "assistant",
                    msg.message
                ))
            }

            add(GPTMessage("user", buildString {
                if (routeData != null) {
                    append("Route data:\n")
                    append(routeData)
                    append("\n\n")
                }
                append(userInput)
            }))
        }

        return GPTRequest(
            model = "gpt-4o-mini",
            messages = messages,
            maxTokens = if (wantsDetails) 700 else 350,
            temperature = 0.2  // Lower for more consistent summarization
        )
    }

    /**
     * Handle GPT response and update UI
     */
    private suspend fun handleGPTResponse(response: String) {
        withContext(Dispatchers.Main) {

            val localizedResponse = if (languageManager.isFrench()) {
                Log.d(TAG, "Translating response to French...")
                languageManager.translateFromEnglish(response)
            } else {
                response
            }

            Log.d(TAG, "Localized response: $localizedResponse")

            val updatedHistory = _conversationState.value.conversationHistory +
                    ChatMessage(localizedResponse, isUser = false)

            _conversationState.value = _conversationState.value.copy(
                gptResponse = localizedResponse,
                isProcessing = false,
                conversationHistory = updatedHistory
            )

            ttsManager.speakPriority(localizedResponse)
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
                                        val languageCode = if (languageManager.isFrench()) "fr-CA" else "en-US"
                                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode)

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
                                        val errorMsg = languageManager.getString("Voice input stopped")
                                        ttsManager.speakPriority(errorMsg)

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


                    val processingMsg = languageManager.getString("processing")
                    ttsManager.speakPriority(processingMsg)
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
                                    val languageCode = if (languageManager.isFrench()) "fr-CA" else "en-US"
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode)
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
     * Send request to GPT API
     */
    private suspend fun sendToGPT(request: GPTRequest): String {
        val openAIApiKey = apiKey ?: run {
            Log.e(TAG, "OpenAI API key not provided")
            return "Sorry, AI conversation is not available. API key not configured."
        }

        if (openAIApiKey.isBlank()) {
            Log.e(TAG, "OpenAI API key is empty")
            return "Sorry, AI conversation is not available."
        }

        try {
            val response = openAIAPI.chatCompletion(
                authorization = "Bearer $openAIApiKey",
                request = request
            )

            if (response.isSuccessful && response.body() != null) {
                val gptResponse = response.body()!!
                return gptResponse.choices.firstOrNull()?.message?.content
                    ?: "I'm not sure how to help with that."
            } else {
                val errorBody = response.errorBody()?.string()
                Log.e(TAG, "GPT API error: ${response.code()} - $errorBody")
                return "I'm having trouble connecting to the AI service. Please try again."
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error calling GPT API: ${e.message}", e)
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
}