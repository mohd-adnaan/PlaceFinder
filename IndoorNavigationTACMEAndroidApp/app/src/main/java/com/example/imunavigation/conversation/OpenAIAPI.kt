package com.example.imunavigation.conversation

import retrofit2.Response
import retrofit2.http.*
import com.google.gson.annotations.SerializedName

interface OpenAIAPI {
    @POST("v1/chat/completions")
    suspend fun chatCompletion(
        @Header("Authorization") authorization: String,
        @Body request: GPTRequest
    ): Response<GPTResponse>
}

// GPT-specific data classes
data class GPTRequest(
    val model: String,
    val messages: List<GPTMessage>,
    @SerializedName("max_tokens") val maxTokens: Int,
    val temperature: Double
)

data class GPTMessage(
    val role: String,
    val content: String
)

data class GPTResponse(
    val choices: List<GPTChoice>
)

data class GPTChoice(
    val message: GPTMessage
)