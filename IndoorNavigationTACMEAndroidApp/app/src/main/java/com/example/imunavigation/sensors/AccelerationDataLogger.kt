package com.example.imunavigation.sensors


/**
 * Data class representing a single acceleration sample with detection metadata
 */
data class AccelerationSample(
    val sampleIndex: Int,
    val timestamp: Long,
    val rawMagnitude: Float,
    val filteredMagnitude: Double,
    var isPeak: Boolean = false,
    var isValley: Boolean = false,
    var isConfirmedStep: Boolean = false,
    var stepLength: Double? = null,
    var stepNumber: Int? = null,
    var peakValleyDiff: Double? = null
)

/**
 * Logger for tracking acceleration data and step detection events
 * Used for debugging and analysis of the step detection algorithm
 */
class AccelerationDataLogger(
    private val maxSamples: Int = Int.MAX_VALUE
    //private val maxSamples: Int = 10000
) {
    private val samples = mutableListOf<AccelerationSample>()
    private var sampleCounter = 0

    /**
     * Add acceleration sample to the log
     */
    fun addSample(
        timestamp: Long,
        rawMagnitude: Float,
        filteredMagnitude: Double,
        isPeak: Boolean = false,
        isValley: Boolean = false,
        isConfirmedStep: Boolean = false,
        stepLength: Double? = null,
        stepNumber: Int? = null,
        peakValleyDiff: Double? = null
    ) {
        samples.add(
            AccelerationSample(
                sampleIndex = sampleCounter++,
                timestamp = timestamp,
                rawMagnitude = rawMagnitude,
                filteredMagnitude = filteredMagnitude,
                isPeak = isPeak,
                isValley = isValley,
                isConfirmedStep = isConfirmedStep,
                stepLength = stepLength,
                stepNumber = stepNumber,
                peakValleyDiff = peakValleyDiff
            )
        )

        // Keep only recent samples to prevent memory issues
        if (samples.size > maxSamples) {
            samples.removeFirst()
            // Adjust sample indices after removal
            samples.forEachIndexed { index, sample ->
                samples[index] = sample.copy(sampleIndex = index)
            }
            sampleCounter = samples.size
        }
    }

    /**
     * Mark the most recent sample as a detected peak
     */
    fun markLastSampleAsPeak() {
        if (samples.isNotEmpty()) {
            val previousIndex = samples.size - 2
            samples[previousIndex] = samples[previousIndex].copy(isPeak = true)
        }
    }

    /**
     * Mark the most recent sample as a detected valley
     */
    fun markLastSampleAsValley() {
        if (samples.isNotEmpty()) {
            val previousIndex = samples.size - 2
            samples[previousIndex] = samples[previousIndex].copy(isValley = true)
        }
    }

    /**
     * Mark a specific sample (by timestamp) as a confirmed step
     */
    fun markSampleAsConfirmedStep(
        timestamp: Long,
        stepLength: Double,
        stepNumber: Int,
        peakValleyDiff: Double
    ) {
        val sampleIndex = samples.indexOfFirst { it.timestamp == timestamp }
        if (sampleIndex >= 0) {
            samples[sampleIndex] = samples[sampleIndex].copy(
                isConfirmedStep = true,
                stepLength = stepLength,
                stepNumber = stepNumber,
                peakValleyDiff = peakValleyDiff
            )
        }
    }

    /**
     * Get all logged samples (returns a copy to prevent external modification)
     */
    fun getSamples(): List<AccelerationSample> = samples.toList()

    /**
     * Get samples within a specific time range
     */
    fun getSamplesInRange(startTime: Long, endTime: Long): List<AccelerationSample> {
        return samples.filter { it.timestamp in startTime..endTime }
    }

    /**
     * Get only samples marked as peaks
     */
    fun getPeaks(): List<AccelerationSample> {
        return samples.filter { it.isPeak }
    }

    /**
     * Get only samples marked as valleys
     */
    fun getValleys(): List<AccelerationSample> {
        return samples.filter { it.isValley }
    }

    /**
     * Get only samples marked as confirmed steps
     */
    fun getConfirmedSteps(): List<AccelerationSample> {
        return samples.filter { it.isConfirmedStep }
    }

    /**
     * Get the total number of logged samples
     */
    fun getSampleCount(): Int = samples.size

    /**
     * Get statistics about the logged data
     */
    fun getStatistics(): LoggerStatistics {
        return LoggerStatistics(
            totalSamples = samples.size,
            peakCount = samples.count { it.isPeak },
            valleyCount = samples.count { it.isValley },
            confirmedStepCount = samples.count { it.isConfirmedStep },
            timeSpanMs = if (samples.isNotEmpty()) {
                samples.last().timestamp - samples.first().timestamp
            } else 0L
        )
    }

    /**
     * Clear all logged samples
     */
    fun clear() {
        samples.clear()
        sampleCounter = 0
    }

    /**
     * Statistics data class for logger metrics
     */
    data class LoggerStatistics(
        val totalSamples: Int,
        val peakCount: Int,
        val valleyCount: Int,
        val confirmedStepCount: Int,
        val timeSpanMs: Long
    )
}