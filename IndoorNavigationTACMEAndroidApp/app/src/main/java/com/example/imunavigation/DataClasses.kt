// DataClasses.kt
package com.example.imunavigation

// Data classes for API communication
data class InitializeRequest(
    val action: String = "initialize",
    val source: String,
    val destination: String,
    val useClockDirections: Boolean = false,
    val useLandmarks: Boolean = false
)

data class UpdateRequest(
    val action: String = "update",
    val currentX: Double,
    val currentY: Double,
    val currentBearing: Double? = null
)

data class CalibrationData(
    val mapStartX: Double,
    val mapStartY: Double,
    val initialBearing: Double? = null
)

data class NavigationResponse(
    val status: String,
    val message: String? = null,
    val instructions: String? = null,
    val navigationStarted: Boolean? = null,
    val pathCoordinates: List<List<Double>>? = null,
    val calibration: CalibrationData? = null
)