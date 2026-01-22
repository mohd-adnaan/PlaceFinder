package com.example.imunavigation.utils

import android.content.Context
import android.util.Log
import org.json.JSONObject

object POIExtractor {

    /**
     * Extract POI names from any GeoJSON file - completely generic
     * @param context Android context
     * @param fileName Name of the GeoJSON file in assets folder
     * @return List of POI names found, empty if none found or file missing
     */
    fun extractPOINames(context: Context, fileName: String = "map_data.json"): List<String> {
        return try {
            Log.d("POIExtractor", "Attempting to load POIs from: $fileName")

            // Read the JSON file from assets
            val inputStream = context.assets.open(fileName)
            val jsonString = inputStream.bufferedReader().use { it.readText() }

            // Parse JSON
            val jsonObject = JSONObject(jsonString)
            val features = jsonObject.getJSONArray("features")
            val poiNames = mutableListOf<String>()

            Log.d("POIExtractor", "Found ${features.length()} features in GeoJSON")

            // Extract POI names
            for (i in 0 until features.length()) {
                val feature = features.getJSONObject(i)
                val properties = feature.getJSONObject("properties")

                // Check if it's a POI type with a valid name
                val type = properties.optString("type", "")
                val name = properties.optString("name", "")


                if (type == "poi" && name.isNotBlank() && name != "null" && !name.equals("null", ignoreCase = true)) {
                    poiNames.add(name)
                    Log.v("POIExtractor", "Found POI: $name")
                }
            }

            val sortedNames = poiNames.sorted()
            Log.d("POIExtractor", "Successfully extracted ${sortedNames.size} POI names")

            sortedNames

        } catch (e: java.io.FileNotFoundException) {
            Log.w("POIExtractor", "GeoJSON file '$fileName' not found in assets folder")
            emptyList()
        } catch (e: Exception) {
            Log.e("POIExtractor", "Error extracting POI names from '$fileName': ${e.message}")
            emptyList()
        }
    }

    /**
     * Try multiple possible file names/locations
     */
    fun extractPOINamesWithFallback(context: Context, vararg fileNames: String): List<String> {
        for (fileName in fileNames) {
            val names = extractPOINames(context, fileName)
            if (names.isNotEmpty()) {
                Log.d("POIExtractor", "Successfully loaded POIs from: $fileName")
                return names
            }
        }
        Log.w("POIExtractor", "No POI names found in any of the provided files: ${fileNames.joinToString()}")
        return emptyList()
    }

    /**
     * Get diagnostic info about the GeoJSON file
     */
    fun getDiagnosticInfo(context: Context, fileName: String = "map_data.json"): String {
        return try {
            val inputStream = context.assets.open(fileName)
            val jsonString = inputStream.bufferedReader().use { it.readText() }
            val jsonObject = JSONObject(jsonString)
            val features = jsonObject.getJSONArray("features")

            var poiCount = 0
            var namedPOICount = 0
            var nullNameCount = 0
            val types = mutableSetOf<String>()

            for (i in 0 until features.length()) {
                val feature = features.getJSONObject(i)
                val properties = feature.getJSONObject("properties")
                val type = properties.optString("type", "unknown")
                val name = properties.optString("name", "")
                types.add(type)

                if (type == "poi") {
                    poiCount++
                    if (name.isNotBlank() && name != "null" && !name.equals("null", ignoreCase = true)) {
                        namedPOICount++
                    } else {
                        nullNameCount++
                    }
                }
            }

            "File: $fileName\n" +
                    "Total features: ${features.length()}\n" +
                    "POI features: $poiCount\n" +
                    "Named POIs: $namedPOICount\n" +
                    "Null/Empty POIs: $nullNameCount\n" +
                    "Feature types: ${types.joinToString()}"

        } catch (e: Exception) {
            "Error reading $fileName: ${e.message}"
        }
    }
}