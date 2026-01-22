// IMUCalibrationManager.kt
package com.example.imunavigation.calibration

import android.util.Log
import kotlin.math.*

/**
 * Manages IMU calibration and coordinate system transformations
 */


class IMUCalibrationManager {

    /**
     * Represents the calibration state and confidence
     */
    data class CalibrationState(
        val isPositionCalibrated: Boolean = false,
        val isBearingCalibrated: Boolean = false,
        val positionOffsetX: Double = 0.0,
        val positionOffsetY: Double = 0.0,
        val bearingOffset: Double = 0.0,
        val calibrationConfidence: Double = 0.0,
        val calibrationTimestamp: Long = 0L,
        var permanentBearingOffset: Double? = null,
        val initialBearing: Double? = null
    )

    /**
     * Represents a position in either coordinate system
     */
    data class Position(
        val x: Double,
        val y: Double,
        val bearing: Double = 0.0,
        val timestamp: Long = System.currentTimeMillis()
    )

    private var calibrationState = CalibrationState()
    private var lastKnownImuPosition = Position(0.0, 0.0)

    // Reference to sensor manager for setting initial bearing
    private var sensorManagerRef: Any? = null // Will be set via setSensorManager




    companion object {
        private const val TAG = "IMUCalibration"
        private const val MIN_CONFIDENCE_THRESHOLD = 0.5
        private const val BEARING_WRAP_THRESHOLD = 180.0
        private const val MAX_CALIBRATION_AGE_MS = 300_000L // 5 minutes


    }

    /**
     * Set reference to sensor manager for initial bearing setup
     */
    fun setSensorManager(sensorManager: Any) {
        this.sensorManagerRef = sensorManager
        Log.d(TAG, "Sensor manager reference set for bearing calibration")
    }

    /**
     * Validate bearing reference system and detect potential mismatches
     */
    private fun validateBearingReference(mapBearing: Double, imuBearing: Double): String {
        val diff = abs(mapBearing - imuBearing)
        val normalizedDiff = minOf(diff, 360.0 - diff)

        return when {
            normalizedDiff < 15.0 -> "ALIGNED - Bearings are well aligned"
            normalizedDiff < 45.0 -> "MINOR_OFFSET - Small bearing difference"
            normalizedDiff < 90.0 -> "MODERATE_OFFSET - Moderate bearing difference"
            normalizedDiff < 135.0 -> "MAJOR_OFFSET - Large bearing difference"
            else -> "REFERENCE_MISMATCH - Possible coordinate system difference"
        }
    }

    /**
     * Calculate bearing offset handling angle wrap-around and reference system differences
     */
    private fun calculateBearingOffset(mapBearing: Double, imuBearing: Double): Double {
        // Log the raw values for debugging
        Log.d(TAG, "Bearing calibration: Map=$mapBearing°, IMU=$imuBearing°")

        // Check if we need to account for different reference systems
        // Android: 0°=North, 90°=East (standard compass)
        // Server: Should be same after conversion, but let's validate

        var adjustedMapBearing = mapBearing
        var adjustedImuBearing = imuBearing

        // Normalize both bearings to [0, 360) first
        adjustedMapBearing = normalizeBearing(adjustedMapBearing)
        adjustedImuBearing = normalizeBearing(adjustedImuBearing)

        // Calculate basic offset
        var offset = adjustedMapBearing - adjustedImuBearing

        // Normalize to [-180, 180] range for shortest rotation
        while (offset > BEARING_WRAP_THRESHOLD) offset -= 360.0
        while (offset < -BEARING_WRAP_THRESHOLD) offset += 360.0

        // Log the calculated offset for debugging
        Log.d(TAG, "Calculated bearing offset: $offset°")

        // If the offset is very large (>90°), there might be a reference system mismatch
        if (abs(offset) > 90.0) {
            Log.w(TAG, "Large bearing offset detected ($offset°) - possible reference system mismatch")

            // Try alternative reference conversions and pick the smallest offset
            val alternativeOffsets = listOf(
                offset,
                offset + 90.0,   // 90° rotation
                offset - 90.0,   // -90° rotation
                offset + 180.0,  // 180° rotation
                offset - 180.0   // -180° rotation
            ).map {
                var normalized = it
                while (normalized > 180.0) normalized -= 360.0
                while (normalized < -180.0) normalized += 360.0
                normalized
            }

            // Pick the smallest absolute offset
            val bestOffset = alternativeOffsets.minByOrNull { abs(it) } ?: offset
            Log.d(TAG, "Adjusted bearing offset: $bestOffset° (was $offset°)")


            fixedBearingOffset(bestOffset)

            return bestOffset
        }

        fixedBearingOffset(offset)
        return offset
    }

    /**
     * Normalize bearing to [0, 360) range
     */
    private fun normalizeBearing(bearing: Double): Double {
        var normalized = bearing % 360.0
        if (normalized < 0) normalized += 360.0
        return normalized
    }

    /**
     * Calculate calibration confidence based on various factors
     */
    private fun calculateConfidence(stepCount: Int, timeElapsed: Long): Double {
        val stepConfidence = when {
            stepCount < 5 -> 0.7 //0.3
            stepCount < 15 -> 0.8
            stepCount < 30 -> 0.85
            else -> 0.9
        }

        val timeConfidence = when {
            timeElapsed < 10_000 -> 0.7  //0.4 Less than 10 seconds
            timeElapsed < 30_000 -> 0.8  // 0.8Less than 30 seconds
            timeElapsed < 60_000 -> 0.9  // Less than 1 minute
            else -> 0.6  // Longer time may indicate drift
        }

        return (stepConfidence + timeConfidence) / 2.0
    }

    /**
     * Perform initial calibration with map coordinates
     */
    fun calibrateWithMapPosition(
        currentImuPosition: Position,
        mapX: Double,
        mapY: Double,
        mapBearing: Double? = null,
        stepCount: Int = 0,

        ): Boolean {
        try {
            val currentTime = System.currentTimeMillis()

            // Calculate position offset (transformation from IMU to map coordinates)
            val offsetX = mapX - currentImuPosition.x
            val offsetY = mapY - currentImuPosition.y

            // Calculate bearing offset if map bearing is provided
            var bearingOffset = 0.0
            var isBearingCalibrated = false

            mapBearing?.let { bearing ->
                if (!calibrationState.isBearingCalibrated) {
                    setInitialBearingInSensorManager(bearing)
                    calibrationState = calibrationState.copy(initialBearing = bearing)
                    bearingOffset = 0.0
                    isBearingCalibrated = true
                    Log.d(TAG, "Initial bearing set (FIRST TIME): ${bearing}° (gyroscope integration mode)")
                } else {
                    Log.d(TAG, "Recalibration: preserving existing bearing, only updating position")
                }
            }

            // Calculate confidence based on available data
            val confidence = calculateConfidence(stepCount, 0L)

            calibrationState = CalibrationState(
                isPositionCalibrated = true,
                isBearingCalibrated = isBearingCalibrated,
                positionOffsetX = offsetX,
                positionOffsetY = offsetY,
                bearingOffset = bearingOffset,
                calibrationConfidence = confidence,
                calibrationTimestamp = currentTime,
                permanentBearingOffset = calibrationState.permanentBearingOffset,
                initialBearing = calibrationState.initialBearing
            )

            lastKnownImuPosition = currentImuPosition

            Log.d(TAG, "Calibration complete:")
            Log.d(TAG, "  Position offset: (${offsetX}, ${offsetY})")
            Log.d(TAG, "  Bearing offset: ${bearingOffset}°")
            Log.d(TAG, "  Confidence: ${confidence}")

            return true

        } catch (e: Exception) {
            Log.e(TAG, "Calibration failed: ${e.message}")
            return false
        }
    }

    /**
     * Transform IMU position to map coordinates
     */
    fun transformToMapPosition(imuPosition: Position): Position? {
        if (!calibrationState.isPositionCalibrated) {
            Log.w(TAG, "Position not calibrated - cannot transform to map coordinates")
            return null
        }

        val mapX = imuPosition.x + calibrationState.positionOffsetX
        val mapY = imuPosition.y + calibrationState.positionOffsetY

        val mapBearing = if (calibrationState.isBearingCalibrated) {
            //normalizeBearing(imuPosition.bearing + calibrationState.bearingOffset) // This is for dynamic bearing calibration
            normalizeBearing(imuPosition.bearing + (calibrationState.permanentBearingOffset?:calibrationState.bearingOffset))
        } else {
            imuPosition.bearing
        }

        return Position(mapX, mapY, mapBearing, imuPosition.timestamp)
    }

    // THIS IS NOT RELEVANT FOR NOW. I AM CURRENTLY USING DYNAMIC BEARING CALIB AT EVERY SEGMENT CHANGE
    private fun fixedBearingOffset(fixedBearingOffset: Double){

        if (calibrationState.permanentBearingOffset == null) {

            calibrationState.permanentBearingOffset = fixedBearingOffset
        }
    }

    /**
     * Update calibration confidence based on movement and time
     */
    fun updateCalibration(currentImuPosition: Position, stepCount: Int) {
        if (!calibrationState.isPositionCalibrated) return

        val timeElapsed = System.currentTimeMillis() - calibrationState.calibrationTimestamp
        val newConfidence = calculateConfidence(stepCount, timeElapsed)

        // Gradually decrease confidence over time to account for drift
        val timeDecayFactor = when {
            timeElapsed > MAX_CALIBRATION_AGE_MS -> 0.3
            timeElapsed > MAX_CALIBRATION_AGE_MS / 2 -> 0.7
            else -> 1.0
        }

        val adjustedConfidence = newConfidence * timeDecayFactor

        calibrationState = calibrationState.copy(
            calibrationConfidence = adjustedConfidence
        )

        lastKnownImuPosition = currentImuPosition

        Log.d(TAG, "Calibration updated: confidence=${adjustedConfidence}, steps=$stepCount")
    }

    // NEW method:
    private fun setInitialBearingInSensorManager(bearing: Double) {
        try {
            sensorManagerRef?.let { sensorManager ->
                val method = sensorManager::class.java.getMethod("setInitialBearing", Double::class.javaPrimitiveType)
                method.invoke(sensorManager, bearing)
                Log.d(TAG, "Initial bearing $bearing° set in sensor manager")
            } ?: run {
                Log.w(TAG, "Sensor manager reference not set - cannot set initial bearing")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set initial bearing in sensor manager: ${e.message}")
        }
    }

    /**
     * Check if calibration is valid and reliable
     */
    fun isCalibrationValid(): Boolean {
        return calibrationState.isPositionCalibrated &&
                calibrationState.calibrationConfidence >= MIN_CONFIDENCE_THRESHOLD
    }

    /**
     * Check if bearing calibration is available
     */
    fun isBearingCalibrated(): Boolean {
        return calibrationState.isBearingCalibrated && isCalibrationValid()
    }

    /**
     * Get current calibration status as human-readable string
     */
    fun getCalibrationStatus(): String {
        return when {
            !calibrationState.isPositionCalibrated -> "Position not calibrated"
            !calibrationState.isBearingCalibrated -> "Bearing not calibrated"
            calibrationState.calibrationConfidence < MIN_CONFIDENCE_THRESHOLD ->
                "Low calibration confidence (${(calibrationState.calibrationConfidence * 100).toInt()}%)"
            else -> "Fully calibrated (${(calibrationState.calibrationConfidence * 100).toInt()}%)"
        }
    }

    /**
     * Get calibration confidence as percentage
     */
    fun getCalibrationConfidence(): Double {
        return calibrationState.calibrationConfidence
    }

    /**
     * Check if recalibration is recommended
     */
    fun isRecalibrationRecommended(): Boolean {
        val timeElapsed = System.currentTimeMillis() - calibrationState.calibrationTimestamp
        return calibrationState.calibrationConfidence < 0.3 ||
                timeElapsed > MAX_CALIBRATION_AGE_MS
    }

    /**
     * Reset calibration state
     */
    fun resetCalibration() {
        calibrationState = CalibrationState()
        lastKnownImuPosition = Position(0.0, 0.0)
        Log.d(TAG, "Calibration reset")
    }

    /**
     * Get detailed calibration information for debugging
     */
    fun getCalibrationDetails(): Map<String, Any> {
        return mapOf(
            "isPositionCalibrated" to calibrationState.isPositionCalibrated,
            "isBearingCalibrated" to calibrationState.isBearingCalibrated,
            "positionOffset" to "(${calibrationState.positionOffsetX}, ${calibrationState.positionOffsetY})",
            "bearingOffset" to "${calibrationState.bearingOffset}°",
            "confidence" to "${(calibrationState.calibrationConfidence * 100).toInt()}%",
            "ageMs" to (System.currentTimeMillis() - calibrationState.calibrationTimestamp),
            "isValid" to isCalibrationValid()
        )
    }
}