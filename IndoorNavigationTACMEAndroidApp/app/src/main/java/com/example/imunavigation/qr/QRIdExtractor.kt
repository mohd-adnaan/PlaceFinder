package com.example.imunavigation.qr

import android.util.Log

object QRIdExtractor {

    private const val TAG = "QRIdExtractor"

    /**
     * Extract numeric ID from QR content like "QR_Id:https://qrco.de/bgErvr"
     */
    fun extractQRCodeId(qrContent: String?): String? {
        if (qrContent.isNullOrBlank()) return null

        Log.d(TAG, "Extracting numeric ID from: $qrContent")

        return when {
            // specific format: "QR_Id:https://qrco.de/bgErvr"
            qrContent.startsWith("QR_Id:") && qrContent.contains("qrco.de/") -> {
                val urlCode = qrContent.substringAfter("qrco.de/")
                convertUrlCodeToNumber(urlCode)
            }

            // Look for existing numbers in QR content
            qrContent.contains(Regex("\\d+")) -> {
                val numbers = Regex("\\d+").findAll(qrContent).map { it.value }.toList()
                if (numbers.isNotEmpty()) numbers.first() else hashToNumber(qrContent)
            }

            // Hash any other content to a consistent number
            else -> {
                hashToNumber(qrContent)
            }
        }
    }

    /**
     * Convert URL code like "bgErvr" to a numeric ID
     */
    private fun convertUrlCodeToNumber(urlCode: String): String {
        if (urlCode.isBlank()) return "0"

        try {
            // Simple conversion: sum of character codes with position weighting
            var numericValue = 0L

            for (i in urlCode.indices) {
                val char = urlCode[i]
                val charValue = when {
                    char.isDigit() -> char.digitToInt()
                    char.isLetter() -> char.lowercaseChar().code - 'a'.code + 10
                    else -> char.code % 36
                }
                numericValue += charValue * (36L * i + 1)
            }

            // Keep it within reasonable range
            val result = (numericValue % 999999).toString()
            Log.d(TAG, "URL code '$urlCode' -> numeric ID: $result")
            return result

        } catch (e: Exception) {
            Log.w(TAG, "Error converting URL code: ${e.message}")
            return urlCode.hashCode().toString().replace("-", "")
        }
    }

    /**
     * Simple hash to number conversion
     */
    private fun hashToNumber(content: String): String {
        return try {
            val hash = content.hashCode()
            (kotlin.math.abs(hash) % 999999).toString()
        } catch (e: Exception) {
            "12345" // Fallback
        }
    }
}