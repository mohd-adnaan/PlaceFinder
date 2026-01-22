// NavigationAPI.kt - Your existing API (no changes needed)
package com.example.imunavigation.api

import com.example.imunavigation.navigation.InitializeRequest
import com.example.imunavigation.navigation.NavigationResponse
import com.example.imunavigation.navigation.UpdateRequest
import retrofit2.http.*

/**
 * Retrofit interface for navigation API communication
 * Defines endpoints for initialization and position updates
 */
interface NavigationAPI {

    /**
     * Initialize navigation session with source and destination
     */
    @POST("wayfinder")
    suspend fun initialize(
        @Body request: InitializeRequest,
        @Header("Session-ID") sessionId: String
    ): NavigationResponse

    /**
     * Update current position and get navigation instructions
     */
    @POST("wayfinder")
    suspend fun updatePosition(
        @Body request: UpdateRequest,
        @Header("Session-ID") sessionId: String
    ): NavigationResponse
}