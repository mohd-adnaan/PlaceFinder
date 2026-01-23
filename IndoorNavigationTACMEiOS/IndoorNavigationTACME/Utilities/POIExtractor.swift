//
//  POIExtractor.swift
//  IndoorNavigationTACME
//
//  Utility for extracting POI names from GeoJSON files
//

import Foundation

/// Utility for extracting Points of Interest from GeoJSON map data
enum POIExtractor {
    
    /// Extract POI names from a GeoJSON file in the bundle
    /// - Parameter fileName: Name of the JSON file (without extension)
    /// - Returns: Array of POI names, or nil if extraction fails
    static func extractPOINames(fileName: String = "map_data") -> [String]? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("POIExtractor: File '\(fileName).json' not found in bundle")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return extractPOINames(from: data)
        } catch {
            print("POIExtractor: Failed to read file: \(error)")
            return nil
        }
    }
    
    /// Extract POI names from GeoJSON data
    /// - Parameter data: Raw JSON data
    /// - Returns: Array of POI names
    static func extractPOINames(from data: Data) -> [String]? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = json["features"] as? [[String: Any]] else {
                print("POIExtractor: Invalid GeoJSON structure")
                return nil
            }
            
            var poiNames: [String] = []
            
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let type = properties["type"] as? String,
                      type == "poi",
                      let name = properties["name"] as? String,
                      !name.isEmpty,
                      name.lowercased() != "null" else {
                    continue
                }
                
                poiNames.append(name)
            }
            
            let sortedNames = poiNames.sorted()
            print("POIExtractor: Successfully extracted \(sortedNames.count) POI names")
            return sortedNames
            
        } catch {
            print("POIExtractor: JSON parsing error: \(error)")
            return nil
        }
    }
    
    /// Try multiple possible file names
    /// - Parameter fileNames: Array of file names to try
    /// - Returns: First successful extraction result
    static func extractPOINamesWithFallback(fileNames: [String]) -> [String]? {
        for fileName in fileNames {
            if let names = extractPOINames(fileName: fileName), !names.isEmpty {
                print("POIExtractor: Successfully loaded POIs from: \(fileName)")
                return names
            }
        }
        print("POIExtractor: No POI names found in any provided files")
        return nil
    }
    
    /// Get diagnostic info about a GeoJSON file
    /// - Parameter fileName: Name of the JSON file
    /// - Returns: Diagnostic string
    static func getDiagnosticInfo(fileName: String = "map_data") -> String {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            return "File '\(fileName).json' not found"
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = json["features"] as? [[String: Any]] else {
                return "Invalid GeoJSON structure"
            }
            
            var typeCount: [String: Int] = [:]
            
            for feature in features {
                if let properties = feature["properties"] as? [String: Any],
                   let type = properties["type"] as? String {
                    typeCount[type, default: 0] += 1
                }
            }
            
            var info = "GeoJSON Diagnostics:\n"
            info += "Total features: \(features.count)\n"
            info += "Feature types:\n"
            for (type, count) in typeCount.sorted(by: { $0.key < $1.key }) {
                info += "  - \(type): \(count)\n"
            }
            
            return info
            
        } catch {
            return "Error reading file: \(error.localizedDescription)"
        }
    }
}
