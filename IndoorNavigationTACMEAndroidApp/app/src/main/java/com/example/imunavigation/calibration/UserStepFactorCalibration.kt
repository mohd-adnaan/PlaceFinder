package com.example.imunavigation.calibration

import android.util.Log
import kotlin.math.pow

/**
 * Calibration for user step factor (beta)
 */
class UserStepFactorCalibration {

    var isCalibrating = false
        private set

    private var userStepCount = 0
    private var accumulatedAccelerationDiff = 0.0

    // Last computed beta (even if invalid)
    private var userBeta = DEFAULT_BETA

    // Stored only when calibration is valid
    private var calibratedBeta: Double = DEFAULT_BETA
    private var isValid = false

    companion object {
        private const val TAG = "StepCalibration"
        private const val CALIBRATION_DISTANCE = 20 //5.0 // meters
        private const val DEFAULT_BETA = 0.6
    }

    /**
     * Start calibration - user should walk exactly 20 meters
     */
    fun startCalibration() {
        isCalibrating = true
        userStepCount = 0
        accumulatedAccelerationDiff = 0.0
        Log.d(TAG, "Calibration started - walk exactly 20 meters")
    }

    /**
     * Add step data during calibration
     */
    fun addStepData(peakValleyDifference: Double) {
        if (!isCalibrating || peakValleyDifference <= 0) return

        val accDiff = peakValleyDifference.pow(0.25)
        accumulatedAccelerationDiff += accDiff
        userStepCount++

        Log.d(
            TAG,
            "Step $userStepCount: accDiff = ${"%.3f".format(accDiff)}, " +
                    "accumulatedAccDiff = ${"%.3f".format(accumulatedAccelerationDiff)}"
        )
    }

    /**
     * Complete calibration and calculate beta
     */
    fun completeCalibration() {
        if (!isCalibrating) return

        if (accumulatedAccelerationDiff > 0) {
            userBeta = CALIBRATION_DISTANCE / accumulatedAccelerationDiff
            isValid = userBeta in 0.1..2.0

            if (isValid) {
                calibratedBeta = userBeta
                Log.i(
                    TAG,
                    "Calibration complete: steps=$userStepCount, beta=${"%.4f".format(userBeta)}"
                )
            } else {
                Log.w(TAG, "Calibration result out of range: beta=${"%.4f".format(userBeta)}")
            }
        } else {
            Log.w(TAG, "Calibration failed: insufficient data")
        }

        isCalibrating = false
    }

    /**
     * Stop calibration early and calculate beta with estimated distance
     */
    fun stopCalibration(): Boolean {
        if (!isCalibrating) return false

        if (accumulatedAccelerationDiff > 0 && userStepCount > 0) {
            val estimatedDistance = CALIBRATION_DISTANCE
            userBeta = estimatedDistance / accumulatedAccelerationDiff
            isValid = userBeta in 0.1..2.0

            if (isValid) {
                calibratedBeta = userBeta
                Log.i(
                    TAG,
                    "Calibration stopped early: steps=$userStepCount, " +
                            "estimatedDistance=${estimatedDistance}m, userStepFactor=${"%.4f".format(userBeta)}"
                )
                isCalibrating = false
                return true
            } else {
                Log.w(TAG, "Early calibration result out of range: beta=${"%.4f".format(userBeta)}")
            }
        } else {
            Log.w(TAG, "Calibration stopped: insufficient data")
        }

        isCalibrating = false
        return false
    }

    /**
     * Get the calibrated beta factor (falls back to DEFAULT_BETA if never calibrated)
     */
    fun getUserBeta(): Double = calibratedBeta

    /**
     * Check if calibration is valid
     */
    fun isCalibrationValid(): Boolean = isValid

    /**
     * Cancel calibration (does not erase previous valid calibration)
     */
    fun cancel() {
        isCalibrating = false
        Log.d(TAG, "Calibration cancelled - previous calibration preserved")
    }
}
