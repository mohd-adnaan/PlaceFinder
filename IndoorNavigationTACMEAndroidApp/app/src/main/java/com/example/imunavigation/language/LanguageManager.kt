// LanguageManager.kt - OpenAI-Powered Translation
package com.example.imunavigation.language

import android.content.Context
import android.util.Log
import com.example.imunavigation.conversation.OpenAIAPI
import com.example.imunavigation.conversation.GPTRequest
import com.example.imunavigation.conversation.GPTMessage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/**
 * Manages bilingual support (English/French) using OpenAI for translations
 */
class LanguageManager(
    private val context: Context,
    private val openAIAPI: OpenAIAPI,
    private val apiKey: String
) {
    companion object {
        private const val TAG = "LanguageManager"
    }

    enum class Language(val code: String, val displayName: String, val locale: Locale) {
        ENGLISH("en", "English", Locale.US),
        FRENCH("fr", "Français", Locale.CANADA_FRENCH)
    }

    private var currentLanguage = Language.ENGLISH

    // Translation cache to reduce API calls
    private val translationCache = mutableMapOf<String, String>()

    // Critical phrases for instant offline fallback
    private val criticalPhrases = mapOf(
        // Navigation - Core
        "turn left" to "tournez à gauche",
        "turn right" to "tournez à droite",
        "go straight" to "allez tout droit",
        "continue straight" to "continuez tout droit",

        // Navigation - Actions
        "arrived" to "arrivé",
        "destination" to "destination",
        "wrong direction" to "mauvaise direction",
        "backtrack" to "revenez en arrière",
        "keep moving" to "continuez à avancer",
        "prepare to turn" to "préparez-vous à tourner",
        "make a turn" to "tournez",

        // System - Status
        "navigation started" to "navigation démarrée",
        "navigation stopped" to "navigation arrêtée",
        "listening" to "en écoute",
        "processing" to "traitement en cours",
        "error" to "erreur",
        "ready" to "prêt",
        "server connected" to "serveur connecté",

        // System - UI
        "navigation setup" to "configuration de navigation",
        "source location" to "lieu de départ",
        "destination location" to "lieu de destination",
        "start navigation" to "démarrer navigation",
        "stop navigation" to "arrêter navigation",
        "current instruction" to "instruction actuelle",
        "voice guidance" to "guidage vocal",

        // Common POIs
        "entrance" to "entrée",
        "exit" to "sortie",
        "restroom" to "toilettes",
        "elevator" to "ascenseur",
        "stairs" to "escaliers",
        "water fountain" to "fontaine d'eau",
        "library" to "bibliothèque",
        "office" to "bureau"
    )

    /**
     * Set current language
     */
    fun setLanguage(language: Language) {
        currentLanguage = language
        Log.d(TAG, "Language changed to: ${language.displayName}")
    }

    /**
     * Get current language
     */
    fun getCurrentLanguage(): Language = currentLanguage

    /**
     * Check if current language is French
     */
    fun isFrench(): Boolean = currentLanguage == Language.FRENCH

    /**
     * Get locale for TTS
     */
    fun getCurrentLocale(): Locale = currentLanguage.locale

    /**
     * Translate text from current language to English (for backend)
     */
    suspend fun translateToEnglish(text: String): String {
        if (currentLanguage == Language.ENGLISH) {
            return text
        }

        return translateText(text, Language.FRENCH, Language.ENGLISH)
    }

    /**
     * Translate text from English to current language (for user)
     */
    suspend fun translateFromEnglish(text: String): String {
        if (currentLanguage == Language.ENGLISH) {
            return text
        }

        return translateText(text, Language.ENGLISH, Language.FRENCH)
    }

    /**
     * Batch translate multiple texts efficiently
     */
    suspend fun batchTranslateFromEnglish(texts: List<String>): List<String> {
        if (currentLanguage == Language.ENGLISH) {
            return texts
        }

        return texts.map { translateFromEnglish(it) }
    }

    /**
     * Core translation using OpenAI with caching and fallback
     */
    private suspend fun translateText(
        text: String,
        fromLanguage: Language,
        toLanguage: Language
    ): String = withContext(Dispatchers.IO) {
        try {
            // Check cache first
            val cacheKey = "${fromLanguage.code}:${toLanguage.code}:${text.lowercase()}"
            translationCache[cacheKey]?.let {
                Log.d(TAG, "Cache hit: $text → $it")
                return@withContext it
            }

            // Use OpenAI for ALL translations (primary method)
            val translated = translateWithOpenAI(text, fromLanguage, toLanguage)
            translationCache[cacheKey] = translated
            Log.d(TAG, "OpenAI translation: $text → $translated")
            return@withContext translated

        } catch (e: Exception) {
            Log.e(TAG, "Translation error: ${e.message}", e)

            // Critical phrases (ONLY if OpenAI fails)
            if (fromLanguage == Language.ENGLISH && toLanguage == Language.FRENCH) {
                val lowerText = text.lowercase()


                var translatedText = text
                for (entry in criticalPhrases.entries.sortedByDescending { it.key.length }) {
                    if (translatedText.lowercase().contains(entry.key)) {
                        translatedText = translatedText.replace(entry.key, entry.value, ignoreCase = true)
                    }
                }

                if (translatedText != text) {
                    Log.w(TAG, "Used fallback phrases: $text → $translatedText")
                    return@withContext translatedText
                }
            }

            // 4. Last resort: return original
            Log.w(TAG, "Translation failed, returning original: $text")
            return@withContext text
        }
    }

    /**
     * Translate using OpenAI
     */
    private suspend fun translateWithOpenAI(
        text: String,
        fromLanguage: Language,
        toLanguage: Language
    ): String = withContext(Dispatchers.IO) {
        try {
            val systemPrompt = """
You are a professional translator specializing in indoor navigation systems.
Translate the following text from ${fromLanguage.displayName} to ${toLanguage.displayName}.

CRITICAL RULES:
1. Maintain navigation terminology accuracy
2. Keep location names unchanged (e.g., "room435" stays "room435")
3. Preserve urgency and clarity of instructions
4. Use natural, spoken language
5. For direction instructions, be precise
6. Return ONLY the translation, no explanations

Examples:
- "turn left at the water fountain" → "tournez à gauche à la fontaine d'eau"
- "continue straight for 10 steps" → "continuez tout droit pendant 10 pas"
- "wrong direction, backtrack" → "mauvaise direction, revenez en arrière"
            """.trimIndent()

            val request = GPTRequest(
                model = "gpt-4o-mini",
                messages = listOf(
                    GPTMessage("system", systemPrompt),
                    GPTMessage("user", text)
                ),
                maxTokens = 150,
                temperature = 0.1 // Low temperature for consistent translations
            )

            val response = openAIAPI.chatCompletion(
                authorization = "Bearer $apiKey",
                request = request
            )

            if (response.isSuccessful && response.body() != null) {
                val translatedText = response.body()!!
                    .choices.firstOrNull()?.message?.content
                    ?: throw Exception("Empty response from OpenAI")

                return@withContext translatedText.trim()
            } else {
                val errorBody = response.errorBody()?.string()
                throw Exception("OpenAI API error: ${response.code()} - $errorBody")
            }

        } catch (e: Exception) {
            Log.e(TAG, "OpenAI translation failed: ${e.message}")
            throw e
        }
    }

    /**
     * Translate location name for backend (preserves format)
     */
    suspend fun translateLocationName(location: String): String {
        try {
            // First normalize the location
            val normalized = location.replace(" ", "").lowercase()

            // If it's already in English format (e.g., "room435"), return as-is
            if (normalized.matches(Regex("^[a-z]+\\d+$"))) {
                return normalized
            }

            // Translate and then normalize
            val translated = translateToEnglish(location)
            return translated.replace(" ", "").lowercase()

        } catch (e: Exception) {
            Log.e(TAG, "Location translation failed: ${e.message}")
            return location.replace(" ", "").lowercase()
        }
    }

    /**
     * Get localized UI strings (instant, no API call)
     */
    fun getString(key: String): String {
        return when (currentLanguage) {
            Language.FRENCH -> getLocalizedString(key)
            Language.ENGLISH -> key
        }
    }

    /**
     * Pre-defined UI strings for French (instant access)
     */
    private fun getLocalizedString(key: String): String {
        return when (key) {
            // Navigation Screen
            "Navigation Setup" -> "Configuration de navigation"
            "Source Location" -> "Lieu de départ"
            "Destination Location" -> "Lieu de destination"
            "Clock Directions" -> "Directions horaires"
            "Use Landmarks" -> "Utiliser repères"
            "Voice Guidance" -> "Guidage vocal"
            "Start Navigation" -> "Démarrer navigation"
            "Stop Navigation" -> "Arrêter navigation"
            "Current Instruction" -> "Instruction actuelle"
            "Ready to navigate" -> "Prêt à naviguer"
            "Initialize Server" -> "Initialiser serveur"
            "Server connected! Ready to start navigation." -> "Serveur connecté! Prêt à démarrer."
            "Reset Interface" -> "Réinitialiser interface"

            // AI Conversation
            "AI Chat" -> "Chat IA"
            "Start AI Chat" -> "Démarrer chat IA"
            "Stop AI Chat" -> "Arrêter chat IA"
            "Listening" -> "En écoute"
            "Processing" -> "Traitement"
            "Send" -> "Envoyer"
            "Type a message" -> "Tapez un message"
            "Ask about navigation..." -> "Posez une question..."

            // Status
            "Navigation" -> "Navigation"
            "Calibrated" -> "Calibré"
            "Voice" -> "Voix"
            "Active" -> "Actif"
            "Inactive" -> "Inactif"
            "Chat AI" -> "IA Chat"

            // Errors & Messages
            "Network error" -> "Erreur réseau"
            "Connection lost" -> "Connexion perdue"
            "Failed to start" -> "Échec du démarrage"
            "Server connection failed" -> "Échec connexion serveur"
            "Network connection error" -> "Erreur connexion réseau"
            "Failed to start listening" -> "Échec démarrage écoute"
            "Server connected" -> "Serveur connecté"
            "Navigation system ready" -> "Système de navigation prêt"
            "Server initialization failed" -> "Échec initialisation serveur"

            // Step Calibration
            "SLC" -> "EDP" // Étalonnage de pas
            "W5M" -> "M5M" // Marchez 5 minutes
            "Calibrate for personalized step length" -> "Calibrer longueur de pas"
            "Start Calibration" -> "Démarrer calibration"
            "Complete Calibration" -> "Terminer calibration"
            "Stop Calibration" -> "Arrêter calibration"

            else -> key // Return key if no translation
        }
    }

    /**
     * Pre-warm cache with common phrases (call on app start)
     */
    suspend fun preloadCommonPhrases() {
        val commonPhrases = listOf(
            "turn left", "turn right", "go straight", "arrived",
            "wrong direction", "backtrack", "keep moving"
        )

        withContext(Dispatchers.IO) {
            commonPhrases.forEach { phrase ->
                try {
                    translateFromEnglish(phrase)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to preload: $phrase")
                }
            }
        }

        Log.d(TAG, "Preloaded ${commonPhrases.size} common phrases")
    }

    /**
     * Clear translation cache
     */
    fun clearCache() {
        translationCache.clear()
        Log.d(TAG, "Translation cache cleared")
    }

    /**
     * Get cache statistics
     */
    fun getCacheStats(): Map<String, Any> {
        return mapOf(
            "cacheSize" to translationCache.size,
            "criticalPhrasesCount" to criticalPhrases.size,
            "currentLanguage" to currentLanguage.displayName,
            "locale" to currentLanguage.locale.toString()
        )
    }
}