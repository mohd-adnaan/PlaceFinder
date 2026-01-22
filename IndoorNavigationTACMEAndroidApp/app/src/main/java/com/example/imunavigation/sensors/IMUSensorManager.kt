// Enhanced IMUSensorManager.kt with advanced step detection
package com.example.imunavigation.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log
import com.example.imunavigation.calibration.IMUCalibrationManager
import com.example.imunavigation.calibration.UserStepFactorCalibration
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.*

/**
 * Enhanced IMU sensor manager with advanced step detection using:
 */
class IMUSensorManager(
    private val context: Context,
    private val calibrationManager: IMUCalibrationManager
) : SensorEventListener {

    private val stepFactorCalibration = UserStepFactorCalibration()
    private var currentStepLength = 0.0  // Current calculated step length
    //private var walkingFrequency = 0.0    // Current walking frequency



    /**
     * Second-order Butterworth bandpass filter for acceleration data
     * Frequency range: 0.8Hz - 4Hz (typical walking frequency range)
     */
    inner class ButterworthFilter(
        private val lowCut: Double = 0.8,  // Hz
        private val highCut: Double = 4.0, // Hz
        private val sampleRate: Double = 50.0 // Hz
    ) {
        private val order = 2
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        // Butterworth coefficients for 0.8-4Hz bandpass filter (fs=50Hz, order=2)
        private val a0 = 1.0
        private val a1 = -1.6255829582907484
        private val a2 = 0.6675381679326730
        private val b0 = 0.16623091603366352
        private val b1 = 0.0
        private val b2 = -0.16623091603366352

        fun filter(input: Double): Double {
            val output = (b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0

            // Shift delay line
            x2 = x1; x1 = input
            y2 = y1; y1 = output

            return output
        }

        fun reset() {
            x1 = 0.0; x2 = 0.0
            y1 = 0.0; y2 = 0.0
        }
    }

    fun startStepCalibration() = stepFactorCalibration.startCalibration()
    fun completeStepCalibration() = stepFactorCalibration.completeCalibration()
    fun cancelStepCalibration() = stepFactorCalibration.cancel()




    data class IMUState(
        val position: IMUCalibrationManager.Position = IMUCalibrationManager.Position(0.0, 0.0),
        val stepCount: Int = 0,
        val isCalibrated: Boolean = false,
        val accelerationMagnitude: Float = 0f,
        val isMoving: Boolean = false,
        val currentStepLength: Double = 0.75,
        val filterQuality: String = "Good",
        val userBeta: Double = 0.6,
        val isStepCalibrationValid: Boolean = false,
        val isStepCalibrating: Boolean = false
    )

    data class BearingResult(
        val bearing: Double,
        val wasCorrected: Boolean,
        val wasSnappedToCardinal: Boolean = false
    )

    // Step detection data structures
    data class PeakInfo(
        val magnitude: Double,
        val timestamp: Long,
        val index: Int
    )



    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var accelerometer: Sensor? = null
    private var gyroscope: Sensor? = null

    // sensor data processing
    private val accelerometerReading = FloatArray(3)
    private val gyroscopeReading = FloatArray(3)
    private val butterworthFilter = ButterworthFilter()


    // Position tracking variables
    private var imuX = 0.0
    private var imuY = 0.0
    private var currentBearing = 0.0
    private var stepCount = 0
    private var lastTimestamp = 0L
    private var isInitialized = false

    // step detection variables
    private val filteredAcceleration = mutableListOf<Double>()
    private val accelerationTimestamps = mutableListOf<Long>()
    private val detectedPeaks = mutableListOf<PeakInfo>()
    private val recentStepPeriods = mutableListOf<Long>()
    private val confirmedStepPeaks = mutableListOf<PeakInfo>()
    private val accelerationLogger = AccelerationDataLogger()
    private var pendingPeak: PeakInfo? = null


    // Peak-valley detection variables
    private var lastFilteredMagnitude = 0.0
    private var lastPeak = 0.0
    private var lastValley = 0.0
    private var lastPeakTime = 0L
    private var lastStepTime = 0L
    private var stepPeriod = 600L
    private val stepPeakThreshold = 1.10 // Threshold for peak-valley difference

    // Dynamic parameters
    private var dynamicWindowSize = 50 // Initial window size
    private var averageStepPeriod = 600L // milliseconds (initial estimate)

    // Constraints thresholds
    private val minStepPeriod = 300L // milliseconds
    private val maxStepPeriod = 1200L // milliseconds
    private val continuityWindowSize = 7 // N+1 windows for continuity check
    private val continuityThreshold = 4 // M threshold
    private val varianceThreshold = 0.20 // 0.3 0.5var for motion detection
    private val inactivityThreshold = 3000L // 3 seconds of no peaks

    // Movement detection and continuity
    private val accelerationVariances = mutableListOf<Double>()


    // Direction and bearing (existing code)
    private var directionX = 0.0
    private var directionY = 1.0
    private val directionSmoothing = 0.0 //0.7 since we are now using map bearing bearings (true bearings), we dont need smoothing again
    private var pathBearings: List<Double> = emptyList()
    private var currentSegmentId: Int = -1
    private val BEARING_CORRECTION_THRESHOLD = 45.0
    private var bearingCorrectionCount = 0
    private var lastCorrectedBearing: Double = 0.0
    private var initialBearingSet = false
    private var gyroIntegrationBearing = 0.0
    private val gyroAlpha = 0.98f

    private val _imuState = MutableStateFlow(IMUState())
    val imuState: StateFlow<IMUState> = _imuState.asStateFlow()

    companion object {
        private const val TAG = "IMUSensorManager"
        private const val SENSOR_DELAY = SensorManager.SENSOR_DELAY_GAME
        private const val GYRO_NOISE_THRESHOLD = 0.1
        private const val MAX_GYRO_RATE = 5.0
    }

    fun initialize(): Boolean {
        try {
            accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            gyroscope = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

            if (accelerometer == null) {
                //Log.e(TAG, "Accelerometer not available")
                return false
            }

            accelerometer?.let {
                sensorManager.registerListener(this, it, SENSOR_DELAY)
                //Log.d(TAG, "Accelerometer registered")
            }

            gyroscope?.let {
                sensorManager.registerListener(this, it, SENSOR_DELAY)
                //Log.d(TAG, "Gyroscope registered")
            }

            isInitialized = true
            //Log.d(TAG, "IMU sensors initialized successfully")
            return true

        } catch (e: Exception) {
            //Log.e(TAG, "Failed to initialize sensors: ${e.message}")
            return false
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (!isInitialized) return

        event?.let { sensorEvent ->
            when (sensorEvent.sensor.type) {
                Sensor.TYPE_ACCELEROMETER -> {
                    System.arraycopy(sensorEvent.values, 0, accelerometerReading, 0, 3)
                    detectStep(sensorEvent.values, sensorEvent.timestamp)
                }

                Sensor.TYPE_GYROSCOPE -> {
                    System.arraycopy(sensorEvent.values, 0, gyroscopeReading, 0, 3)
                    updateBearingFromGyroscope(sensorEvent.timestamp)
                }
            }
        }
    }

    /**
     * step detection with Butterworth filtering and multiple constraints
     */
    private fun detectStep(accelerometerValues: FloatArray, timestamp: Long) {
        // 1. Calculate acceleration magnitude and remove gravity
        val rawMagnitude = sqrt(
            accelerometerValues[0].pow(2) +
                    accelerometerValues[1].pow(2) +
                    accelerometerValues[2].pow(2)
        )
        val magnitude = rawMagnitude - SensorManager.GRAVITY_EARTH
        //val magnitude = rawMagnitude

        // 2. Apply Butterworth bandpass filter (0.8-4Hz)
        val filteredMagnitude = butterworthFilter.filter(magnitude.toDouble())


        val currentTime = System.currentTimeMillis()  // Wall clock time

        // LOG THE SAMPLE HERE - ADD THIS LINE
        accelerationLogger.addSample(
            timestamp = currentTime,
            rawMagnitude = rawMagnitude,
            filteredMagnitude = filteredMagnitude
        )

        // Check for inactivity period and reset if needed
        checkAndResetAfterInactivity(currentTime)

        accelerationTimestamps.add(currentTime)

        //Store filtered data with timestamps
        filteredAcceleration.add(filteredMagnitude)


        //Update dynamic window size based on recent step periods
        //updateDynamicWindowSize() // we dont need this anymore since we are now doing local peak comparison

        //Maintain data within dynamic window
        if (filteredAcceleration.size > dynamicWindowSize) {
            filteredAcceleration.removeFirst()
            accelerationTimestamps.removeFirst()
        }

        //Calculate acceleration variance for continuity check
        if (filteredAcceleration.size >= dynamicWindowSize) { //3
            val recentData = filteredAcceleration //.takeLast(dynamicWindowSize)
            val variance = calculateVariance(recentData)
            //Log.d(TAG, "accelerationVariancePerWindow: $variance")
            accelerationVariances.add(variance)

            if (accelerationVariances.size > continuityWindowSize) {
                accelerationVariances.removeFirst()
            }
        }

        //Perform peak detection if we have enough data
        if (filteredAcceleration.size >= 3) {
            detectPeaksAndValidateSteps()
        }

        updateIMUState()
    }

    /**
     * Update dynamic window size based on walking pattern
     */
    private fun updateDynamicWindowSize() {
        if (recentStepPeriods.isNotEmpty()) {
            averageStepPeriod = recentStepPeriods.takeLast(3).average().toLong()

            if (averageStepPeriod > 1000) {
            averageStepPeriod = 1000L             }

            // Search window for peak
            val estimatedSamplesPerCycle = (averageStepPeriod * 50 ) / 1000 // 50Hz sampling rate
            dynamicWindowSize = (estimatedSamplesPerCycle).toInt()
            //.coerceIn(minWindowSize, maxWindowSize)
            //Log.d(TAG, "avgStepPeriod:$averageStepPeriod, dynamicWindowSize:$dynamicWindowSize, estimatedSamplesPerCycle:$estimatedSamplesPerCycle")
        }
    }

    /**
     * Enhanced peak-valley detection using dynamic thresholds (like original code)
     */

    private fun detectPeaksAndValidateSteps() {
        if (filteredAcceleration.size <= 3) return

        // Calculate dynamic thresholds using mean and standard deviation
        val recentData = filteredAcceleration //.takeLast(dynamicWindowSize)
        val mean = recentData.average()
        val std = calculateStandardDeviation(recentData, mean)

        val upperThreshold = mean + std * 1.0  // Peak threshold
        val lowerThreshold = mean - std * 0.5  // Valley threshold

        val currentMagnitude = filteredAcceleration.last()
        val currentTime = accelerationTimestamps.last()
        val previousTime = accelerationTimestamps[accelerationTimestamps.size - 2]
        val previousMagnitude = filteredAcceleration[filteredAcceleration.size - 2]
        val beforePreviousMagnitude = filteredAcceleration[filteredAcceleration.size - 3]

        if (previousMagnitude > beforePreviousMagnitude &&
            previousMagnitude > currentMagnitude && previousMagnitude > upperThreshold && previousMagnitude >= lastFilteredMagnitude) {

        // Peak detection with immediate periodicity check
        //if (currentMagnitude > upperThreshold && lastFilteredMagnitude <= upperThreshold) {
            // Create candidate peak
            val candidatePeak = PeakInfo(
                magnitude = previousMagnitude,
                timestamp = previousTime,
                index = filteredAcceleration.size - 2
            )
            //Log.d(TAG, "Send peak: $previousMagnitude for periodicity check, timestamp: $currentTime.")

            // FIRST: Check periodicity constraint on this peak
            if (checkPeakPeriodicityConstraint(candidatePeak)) {
                // Peak passes periodicity - proceed with step detection logic
                //Log.d(TAG, "peak: $previousMagnitude passed periodicity check, timestamp: $currentTime.")

                if (stepPeriod <= 0 )  {
                    stepPeriod = 600L

                    recentStepPeriods.add(stepPeriod)

                }
                pendingPeak = candidatePeak

                //detectedPeaks.add(candidatePeak)

                // Mark this sample as a peak
                accelerationLogger.markLastSampleAsPeak()

                if (detectedPeaks.size > 5) {
                    detectedPeaks.removeFirst()
                }
                lastPeak = previousMagnitude
                lastPeakTime = currentTime

                //Log.d(TAG, "Peak accepted (periodicity passed): magnitude=${String.format("%.3f", lastPeak)} at time=$lastPeakTime")
            } else {
                //Log.v(TAG, "Peak rejected: periodicity constraint failed for magnitude=${String.format("%.3f", previousMagnitude)}")
                return // Don't proceed with this peak
            }
        }

        // Valley detection logic (only runs if peak was accepted)
        if (previousMagnitude < lowerThreshold && previousMagnitude < beforePreviousMagnitude &&
            previousMagnitude < currentMagnitude && previousMagnitude < lastFilteredMagnitude && lastPeakTime > 0) {
            // Valley detected after an accepted peak
            lastValley = previousMagnitude

            // Mark this sample as a valley
            accelerationLogger.markLastSampleAsValley()

            // Validate step if valley follows peak with sufficient difference
            val peakValleyDiff = lastPeak - lastValley

            //Log.d(TAG, "Valley detected: magnitude=${String.format("%.3f", lastValley)}")
            //Log.d(TAG, "PeakValleyDiff: ${String.format("%.3f", peakValleyDiff)}, threshold: $stepPeakThreshold")

            // Check basic peak-valley difference
            if (peakValleyDiff > stepPeakThreshold) {
                // Create peak info for the accepted peak
                pendingPeak?.let { peak ->

                    // Additional constraint validation (similarity and continuity)
                    if (validateAdditionalStepConstraints(peak)) {
                        // Step confirmed! Use peak-to-peak period for step length calculation

                        if (confirmedStepPeaks.isNotEmpty()) {
                            stepPeriod = peak.timestamp - confirmedStepPeaks.last().timestamp
                        }




                        recentStepPeriods.add(stepPeriod)

                        currentStepLength = calculateStepLengthWithCalibration(peakValleyDiff)

                        // Mark confirmed step
                        accelerationLogger.markSampleAsConfirmedStep(
                            timestamp = peak.timestamp,
                            stepLength = currentStepLength,
                            stepNumber = stepCount,
                            peakValleyDiff = peakValleyDiff
                        )




                        if (stepFactorCalibration.isCalibrating) {
                            stepFactorCalibration.addStepData(peakValleyDiff)
                        }

                        // Update step count and position
                        stepCount++
                        lastStepTime = currentTime

                        confirmedStepPeaks.add(peak)
                        pendingPeak = null

                        if (confirmedStepPeaks.size > 20) {
                            confirmedStepPeaks.removeFirst()
                        }

                        updatePositionFromStep()





                        calibrationManager.updateCalibration(getCurrentPosition(), stepCount)

                        Log.d(
                            TAG, "Enhanced step #$stepCount confirmed: " +
                                    "peak=${String.format("%.2f", lastPeak)}, " +
                                    "valley=${String.format("%.2f", lastValley)}, " +
                                    "diff=${String.format("%.2f", peakValleyDiff)}, " +
                                    "stepLength=${String.format("%.2f", currentStepLength)}m, " +
                                    "stepPeriod=${String.format("%d", stepPeriod)}ms" +
                                    "userStepFactor=${String.format("%.3f", stepFactorCalibration.getUserBeta())}"

                        )

                        } else {
                        //Log.v(TAG, "Step validation failed for additional constraints")
                    }

                }
            }else {
                //Log.v(TAG, "Peak-valley difference too small: ${String.format("%.3f", peakValleyDiff)} < $stepPeakThreshold")
            }
        }

        lastFilteredMagnitude = previousMagnitude
    }


    /**
     * Calculate standard deviation for dynamic threshold calculation
     */
    private fun calculateStandardDeviation(data: List<Double>, mean: Double): Double {
        if (data.isEmpty()) return 0.0
        val variance = data.map { (it - mean).pow(2) }.average()
        return sqrt(variance)
    }

    /**
     * Check periodicity constraint based on peak-to-peak timing (Ti = tpeaki+1 − tpeaki)
     */
    private fun checkPeakPeriodicityConstraint(candidatePeak: PeakInfo): Boolean {
        // Cold start: Allow first few peaks to establish pattern
        if (detectedPeaks.size < 2) {
            //Log.d(TAG, "Peak periodicity: Cold start - allowing peak #${detectedPeaks.size + 1}")
            return true
        }

        // Find the most recent peak for periodicity calculation
        val lastPeak = detectedPeaks.last()
        val peakToPeakPeriod = candidatePeak.timestamp - lastPeak.timestamp

        detectedPeaks.add(candidatePeak)

        // Check if this peak-to-peak period is within acceptable range (fixed range)
        val isValid = peakToPeakPeriod in minStepPeriod..maxStepPeriod

        //Log.d(TAG, "Peak periodicity check: ${peakToPeakPeriod}ms in range [${minStepPeriod}, ${maxStepPeriod}]ms = $isValid")

        if (!isValid) {
            Log.v(TAG, "Peak rejected - period ${peakToPeakPeriod}ms outside fixed range")
        }

        return isValid
    }

    private fun checkAndResetAfterInactivity(currentTime: Long) {


        if (detectedPeaks.isNotEmpty()) {
            val timeSinceLastPeak = currentTime - detectedPeaks.last().timestamp

            if (timeSinceLastPeak > inactivityThreshold) {
                //Log.d(TAG, "Inactivity detected (${timeSinceLastPeak}ms) - clearing peak history")
                detectedPeaks.clear()
                // Optionally clear other related data
                accelerationVariances.clear()
                recentStepPeriods.clear()
                confirmedStepPeaks.clear()
            }
        }
    }


    /**
     * Validate additional step constraints (similarity and continuity)
     */
    private fun validateAdditionalStepConstraints(peak: PeakInfo): Boolean {
        // Similarity constraint
        if (!checkSimilarityConstraint(peak)) {
            //Log.v(TAG, "Step rejected: similarity constraint failed")
            //Log.d(TAG, "Step rejected")
            return false
        }

        // Continuity constraint
        if (!checkContinuityConstraint()) {
            //Log.v(TAG, "Step rejected: continuity constraint failed")
            return false
        }

        //Log.d(TAG, "Additional step constraints passed for peak: $peak")
        return true
    }

    /**
     * Check peak similarity with previous peaks (unchanged from original)
     */

  /*
    private fun checkSimilarityConstraint(peak: PeakInfo): Boolean {
        if (confirmedStepPeaks.size < 2) {
            return true
        }

        // Only look at last 5-10 steps (rolling window)
        val recentSteps = confirmedStepPeaks.takeLast(10)
        val recentMagnitudes = recentSteps.map { it.magnitude }

        val avgMagnitude = recentMagnitudes.average()
        val stdDeviation = calculateStandardDeviation(recentMagnitudes, avgMagnitude)

        val deviationFromMean = abs(peak.magnitude - avgMagnitude)
        val normalizedDeviation = if (stdDeviation > 0) deviationFromMean / stdDeviation else 0.0

        // More lenient threshold
        val maxAllowedDeviations = 3.0 // 99.7% confidence interval
        return normalizedDeviation <= maxAllowedDeviations
    }*/





    private fun checkSimilarityConstraint(peak: PeakInfo): Boolean {
        // Need at least 3 previous peaks for meaningful comparison
        if (confirmedStepPeaks.size < 6) {//2
            //Log.d(TAG, "Insufficient step history (${confirmedStepPeaks.size} steps) for similarity check, allowing step")
            return true
        }


        // Create temporary list combining confirmed steps + current peak for analysis
        val allPeakMagnitudes = confirmedStepPeaks.map { it.magnitude }.toMutableList()
        //allPeakMagnitudes.add(peak.magnitude)
        val recentPeakMagnitudes = allPeakMagnitudes //.takeLast(15)

        // Calculate statistics from the combined dataset
        //val avgMagnitude = allPeakMagnitudes.average()
        val avgMagnitude = recentPeakMagnitudes.average()
        val stdDeviation = calculateStandardDeviation(recentPeakMagnitudes, avgMagnitude)
        //val minStdDev = avgMagnitude * 0.15  // Tune this value
        val effectiveStdDev = stdDeviation //maxOf(stdDeviation , minStdDev)
        // Check if current peak deviates too much from the group
        val deviationFromMean = abs(peak.magnitude - avgMagnitude)
        val normalizedDeviation = if (effectiveStdDev > 0) deviationFromMean / effectiveStdDev else 0.0

        val maxAllowedDeviations = 3
        val isValid = normalizedDeviation <= maxAllowedDeviations
        val variationPercent = (stdDeviation / avgMagnitude) * 100



        Log.d(TAG, "Similarity check: comparing current peak (potential step) ${String.format("%.3f", peak.magnitude)} " + "with average steps ${String.format("%.3f", avgMagnitude)}, similarityValue: $isValid, standarddeviation: $stdDeviation, deviationFromMean: $deviationFromMean, normalizeddeviation: $normalizedDeviation, detectedSteps: $recentPeakMagnitudes, variationPercent: $variationPercent")


        return isValid
    }



    /**
     * Check motion continuity using variance of acceleration (unchanged from original)
     */
    private fun checkContinuityConstraint(): Boolean {
        // Need sufficient data for meaningful continuity check
        if (accelerationVariances.size < continuityWindowSize) {
            //Log.d(TAG, "Insufficient variance history (${accelerationVariances.size}/${continuityWindowSize}) " + "for continuity check, allowing step")
            return true
        }

        val activeWindows = accelerationVariances.count { it > varianceThreshold }
        val isValid = activeWindows >= continuityThreshold

        Log.d(TAG, "Continuity check: ${activeWindows} active windows >= ${continuityThreshold} = $isValid")
        Log.d(TAG, "Variance threshold: ${varianceThreshold}, recent variances: " + "${accelerationVariances.takeLast(5).map { String.format("%.2f", it) }}")

        return isValid
    }


    /**
     * Calculate variance of a data series
     */
    private fun calculateVariance(data: List<Double>): Double {
        if (data.isEmpty()) return 0.0
        val mean = data.average()
        return data.map { (it - mean).pow(2) }.average()
    }

    /**
     * Calculate dynamic step length for users
     */
    private fun calculateStepLengthWithCalibration(peakValleyDiff: Double): Double {
        val userBeta = stepFactorCalibration.getUserBeta()
        val stepLength = userBeta * peakValleyDiff.pow(0.25)

        //Log.d(TAG, "dynamicStepLength: $stepLength, userStepFactor: $userBeta, peakValleyDiff: $peakValleyDiff")
        return stepLength //.coerceIn(0.3, 1.2) // Keep within reasonable bounds
    }





    /**
     * Update position using dynamic step length
     */
    private fun updatePositionFromStep() {
        val rawBearing = if (calibrationManager.isBearingCalibrated()) {
            calibrationManager.transformToMapPosition(getCurrentPosition())?.bearing
                ?: currentBearing
        } else {
            currentBearing
        }

        val bearingResult = applyBearingCorrection(rawBearing)
        val correctedBearing = bearingResult.bearing
        val wasCorrected = bearingResult.wasCorrected
        lastCorrectedBearing = correctedBearing

        // Convert bearing to direction vector
        val bearingRad = Math.toRadians(correctedBearing)
        val newDirX = sin(bearingRad)
        val newDirY = cos(bearingRad)

        // Smooth direction vector
        directionX = directionSmoothing * directionX + (1 - directionSmoothing) * newDirX
        directionY = directionSmoothing * directionY + (1 - directionSmoothing) * newDirY

        // Normalize
        val magnitude = sqrt(directionX * directionX + directionY * directionY)
        if (magnitude > 0) {
            directionX /= magnitude
            directionY /= magnitude
        }

        // Calculate position delta using DYNAMIC step length
        val deltaX = currentStepLength * directionX
        val deltaY = currentStepLength * directionY

        // Update position
        imuX += deltaX
        imuY += deltaY

        currentBearing = correctedBearing

        /*
        if (wasCorrected) {
            currentBearing = correctedBearing
        } else {
            currentBearing = Math.toDegrees(atan2(directionX, directionY))
            if (currentBearing < 0) currentBearing += 360
        }

         */

        //Log.d(TAG, "Position updated: (${String.format("%.2f", imuX)}, ${String.format("%.2f", imuY)}) " + "stepLength=${String.format("%.2f", currentStepLength)}m" )

        updateIMUState()
    }

    // ... (keep all existing methods like setInitialBearing, stop, resetPosition, etc.)

    fun setInitialBearing(bearing: Double) {
        currentBearing = bearing
        gyroIntegrationBearing = bearing
        initialBearingSet = true
        val bearingRad = Math.toRadians(bearing)
        directionX = sin(bearingRad)
        directionY = cos(bearingRad)
        //Log.d(TAG, "Initial bearing set to $bearing°")
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        isInitialized = false
        butterworthFilter.reset()
        //Log.d(TAG, "IMU sensors stopped")
    }

    fun resetPosition() {
        imuX = 0.0
        imuY = 0.0
        stepCount = 0
        lastTimestamp = 0L
        filteredAcceleration.clear()
        accelerationTimestamps.clear()
        detectedPeaks.clear()
        accelerationVariances.clear()
        recentStepPeriods.clear()
        butterworthFilter.reset()
        accelerationLogger.clear()

        // Reset peak-valley detection variables
        lastFilteredMagnitude = 0.0
        lastPeak = 0.0
        lastValley = 0.0
        lastPeakTime = 0L
        lastStepTime = 0L

        directionX = 0.0
        directionY = 1.0

        updateIMUState()
        //Log.d(TAG, "Position reset")
    }

    /**
     * Clear accumulated sensor data to prevent memory buildup
     */
    fun clearAccumulatedData() {
        try {

            val sampleCount = accelerationLogger.getSamples().size


            accelerationLogger.clear()

            filteredAcceleration.clear()
            accelerationTimestamps.clear()
            detectedPeaks.clear()
            recentStepPeriods.clear()
            confirmedStepPeaks.clear()
            accelerationVariances.clear()

            lastFilteredMagnitude = 0.0
            lastPeak = 0.0
            lastValley = 0.0
            lastPeakTime = 0L
            lastStepTime = 0L
            pendingPeak = null


            butterworthFilter.reset()

            Log.d(TAG, "Cleared accumulated sensor data: $sampleCount samples + detection state")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing sensor data: ${e.message}", e)
        }
    }

    fun getCurrentPosition(): IMUCalibrationManager.Position {
        return IMUCalibrationManager.Position(imuX, imuY, currentBearing)
    }

    fun getCurrentMapPosition(): IMUCalibrationManager.Position? {
        return calibrationManager.transformToMapPosition(getCurrentPosition())
    }



    private fun updateBearingFromGyroscope(timestamp: Long) {
        if (!initialBearingSet || gyroscope == null) return

        if (lastTimestamp != 0L) {
            val dt = (timestamp - lastTimestamp) / 1e9
            val gyroZ = gyroscopeReading[2]

            if (abs(gyroZ) >= GYRO_NOISE_THRESHOLD && abs(gyroZ) <= MAX_GYRO_RATE) {
                val deltaBearing = Math.toDegrees(gyroZ * dt * (-1))
                gyroIntegrationBearing = (gyroIntegrationBearing + deltaBearing + 360) % 360
                currentBearing = gyroIntegrationBearing
            }
        }
        lastTimestamp = timestamp
        updateIMUState()
    }

    private fun updateIMUState() {
        val isMoving = accelerationVariances.isNotEmpty() &&
                accelerationVariances.takeLast(3).any { it > varianceThreshold }

        val filterQuality = when {
            detectedPeaks.size >= 3 && recentStepPeriods.isNotEmpty() -> "Excellent"
            filteredAcceleration.size >= dynamicWindowSize -> "Good"
            else -> "Initializing"
        }

        _imuState.value = IMUState(
            position = getCurrentPosition(),
            stepCount = stepCount,
            isCalibrated = calibrationManager.isCalibrationValid(),
            accelerationMagnitude = if (filteredAcceleration.isNotEmpty()) filteredAcceleration.last()
                .toFloat() else 0f,
            isMoving = isMoving,
            currentStepLength = currentStepLength,
            filterQuality = filterQuality,
            userBeta = stepFactorCalibration.getUserBeta(),
            isStepCalibrationValid = stepFactorCalibration.isCalibrationValid(),
            isStepCalibrating = stepFactorCalibration.isCalibrating
        )
    }

    // Keep existing bearing correction and utility methods...
    fun setBearingCorrectionData(bearings: List<Double>, segmentId: Int) {
        pathBearings = bearings
        currentSegmentId = segmentId
    }

    private fun applyBearingCorrection(rawBearing: Double): BearingResult {
        if (currentSegmentId < 0 || currentSegmentId >= pathBearings.size) {
            return BearingResult(rawBearing, false)
        }

        val trueBearing = pathBearings[currentSegmentId]
        val diff = calculateBearingDifference(rawBearing, trueBearing)

        return if (abs(diff) <= BEARING_CORRECTION_THRESHOLD) {
            bearingCorrectionCount++
            val cardinalBearing= findNearestCardinalBearing(trueBearing)
            BearingResult(cardinalBearing, true, false)
        } else {
            //BearingResult(rawBearing, false)
            // Raw bearing differs too much from path - snap to nearest cardinal direction
            val cardinalBearing = findNearestCardinalBearing(rawBearing)
            //Log.d(TAG, "Path diff too large (${String.format("%.1f", diff)}°) - snapping bearing ${String.format("%.1f", rawBearing)}° to cardinal ${String.format("%.1f", cardinalBearing)}°")
            BearingResult(cardinalBearing, false, true)
        }
    }

    /**
     * Find the nearest cardinal direction (0, 90, 180, 270) to the given bearing
     */
    private fun findNearestCardinalBearing(bearing: Double): Double {
        val normalizedBearing = ((bearing % 360) + 360) % 360 // Ensure 0-360 range

        val cardinalBearings = listOf(0.0, 90.0, 180.0, 270.0)

        return cardinalBearings.minByOrNull { direction ->
            val diff1 = abs(normalizedBearing - direction)
            val diff2 = abs(normalizedBearing - (direction + 360)) // Handle wrap-around
            val diff3 = abs((normalizedBearing + 360) - direction) // Handle wrap-around
            minOf(diff1, diff2, diff3)
        } ?: 0.0
    }

    fun getLastCorrectedBearing(): Double = lastCorrectedBearing

    private fun calculateBearingDifference(bearing1: Double, bearing2: Double): Double {
        var diff = bearing1 - bearing2
        while (diff > 180) diff -= 360
        while (diff < -180) diff += 360
        return diff
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        //Log.d(TAG, "Sensor accuracy changed: ${sensor?.name}, accuracy: $accuracy")
    }

    /**
     * Get sensor status with new metrics
     */
    fun getSensorStatus(): Map<String, Any> {
        return mapOf(
            "accelerometer" to (accelerometer != null),
            "gyroscope" to (gyroscope != null),
            "isInitialized" to isInitialized,
            "stepCount" to stepCount,
            "position" to "(${"%.2f".format(imuX)}, ${"%.2f".format(imuY)})",
            "bearing" to "${"%.1f".format(currentBearing)}°",
            "currentStepLength" to "${"%.2f".format(currentStepLength)}m",
            //"walkingFrequency" to "${"%.2f".format(walkingFrequency)}Hz",
            "dynamicWindowSize" to dynamicWindowSize,
            "filterQuality" to _imuState.value.filterQuality,
            "detectedPeaks" to detectedPeaks.size,
            "averageStepPeriod" to "${averageStepPeriod}ms"
        )
    }

    /**
     * Get bearing correction stats for debugging
     */
    fun getBearingCorrectionStats(): Map<String, Any> {
        return mapOf(
            "pathBearingsCount" to pathBearings.size,
            "currentSegmentId" to currentSegmentId,
            "bearingCorrectionCount" to bearingCorrectionCount,
            "bearingThreshold" to BEARING_CORRECTION_THRESHOLD,
            "currentBearing" to String.format("%.1f°", currentBearing)
        )
    }


    /**
     * Get step detection quality metrics
     */
    fun getStepDetectionMetrics(): Map<String, Any> {
        return mapOf(
            "totalSteps" to stepCount,
            "averageStepLength" to if (stepCount > 0) String.format(
                "%.2f",
                currentStepLength
            ) else "0.00",
            //"walkingFrequency" to String.format("%.2f", walkingFrequency),
            "recentStepPeriods" to recentStepPeriods.takeLast(5),
            "dynamicWindowSize" to dynamicWindowSize,
            "continuityScore" to if (accelerationVariances.isNotEmpty()) {
                accelerationVariances.count { it > varianceThreshold }
            } else 0,
            "peakSimilarityPassed" to (detectedPeaks.size >= 2),
            "filterStatus" to "Butterworth 0.8-4Hz"
        )
        
        
    }




    /**
     * Stop step calibration and save partial data
     */
    fun stopStepCalibration() {
        val success = stepFactorCalibration.stopCalibration()

        // Update the state to reflect the new calibration status
        _imuState.value = _imuState.value.copy(
            isStepCalibrating = false,
            userBeta = stepFactorCalibration.getUserBeta(),
            isStepCalibrationValid = stepFactorCalibration.isCalibrationValid()
        )

        //Log.d(TAG, "Step calibration stopped. Success: $success, userStepFactor: ${stepFactorCalibration.getUserBeta()}")
    }

    /**
     * Get all logged acceleration samples for debugging and analysis
     */
    fun getAccelerationSamples(): List<AccelerationSample> {
        return accelerationLogger.getSamples()
    }

}