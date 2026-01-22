// OllamaAPI.kt - OpenAI-compatible API format
package com.example.imunavigation.conversation

import retrofit2.Response
import retrofit2.http.*
import com.google.gson.annotations.SerializedName

interface OllamaAPI {
    @POST("api/v1/chat/completions")
    suspend fun generate(
        @Header("Authorization") authorization: String,
        @Body request: OllamaRequest
    ): Response<OllamaResponse>
}

// OpenAI-compatible request format
data class OllamaRequest(
    val model: String,
    val messages: List<Message>,  // Changed from prompt
    val temperature: Double? = null,
    val max_tokens: Int? = null,
    val stream: Boolean = false
)

data class Message(
    val role: String,  // "system", "user", or "assistant"
    val content: String
)

// OpenAI-compatible response format
data class OllamaResponse(
    val id: String,
    @SerializedName("object") val objectType: String,
    val created: Long,
    val model: String,
    val choices: List<Choice>,
    val usage: Usage? = null
)

data class Choice(
    val index: Int,
    val message: Message,
    val finish_reason: String?  // "stop", "length", etc.
)

data class Usage(
    val prompt_tokens: Int,
    val completion_tokens: Int,
    val total_tokens: Int
)