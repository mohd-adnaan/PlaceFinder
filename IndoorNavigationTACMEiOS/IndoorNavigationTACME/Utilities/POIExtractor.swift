//
//  POIExtractor.swift
//  IndoorNavigationTACME
//

import Foundation

/// Utility for extracting Points of Interest from GeoJSON map data
enum POIExtractor {
    
    /// Extract POI names from a GeoJSON file in the bundle
    /// - Parameter fileName: Name of the JSON file (without extension)
    /// - Returns: Array of POI names, or nil if extraction fails
    static func extractPOINames(fileName: String = "map_data") -> [String]? {
        print("🗺️ POIExtractor: Attempting to load '\(fileName).json'")
        
        // Step 1: Check if file exists in bundle
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            print("❌ POIExtractor: File '\(fileName).json' NOT FOUND in bundle!")
            print("")
            print("💡 === FIX REQUIRED ===")
            print("   1. Add map_data.json to Xcode project")
            print("   2. Right-click IndoorNavigationTACME folder → Add Files")
            print("   3. Select map_data.json")
            print("   4. ☑️ Check 'Copy items if needed'")
            print("   5. ☑️ Check 'Add to targets: IndoorNavigationTACME'")
            print("   6. Verify in Build Phases → Copy Bundle Resources")
            print("")
            printBundleDiagnostics()
            return nil
        }
        
        print("✅ POIExtractor: File found at: \(url.path)")
        
        // Step 2: Read file data
        do {
            let data = try Data(contentsOf: url)
            print("✅ POIExtractor: Read \(data.count) bytes")
            return extractPOINames(from: data)
        } catch {
            print("❌ POIExtractor: Failed to read file: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extract POI names from GeoJSON data
    /// - Parameter data: Raw JSON data
    /// - Returns: Array of POI names
    static func extractPOINames(from data: Data) -> [String]? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ POIExtractor: Failed to parse JSON as dictionary")
                return nil
            }
            
            // Log GeoJSON metadata
            if let type = json["type"] as? String {
                print("✅ POIExtractor: GeoJSON type: \(type)")
            }
            if let name = json["name"] as? String {
                print("✅ POIExtractor: Map name: \(name)")
            }
            
            guard let features = json["features"] as? [[String: Any]] else {
                print("❌ POIExtractor: No 'features' array found")
                return nil
            }
            
            print("✅ POIExtractor: Found \(features.count) features")
            
            // Extract POI names
            var poiNames: [String] = []
            var nodeCount = 0
            var pathCount = 0
            
            for feature in features {
                guard let properties = feature["properties"] as? [String: Any],
                      let type = properties["type"] as? String else {
                    continue
                }
                
                if type == "path" {
                    pathCount += 1
                    continue
                }
                
                if type == "poi" {
                    if let name = properties["name"] as? String,
                       !name.isEmpty,
                       name.lowercased() != "null" {
                        poiNames.append(name)
                    } else {
                        nodeCount += 1
                    }
                }
            }
            
            let sortedNames = poiNames.sorted()
            
            // Print summary
            print("📊 POIExtractor Summary:")
            print("   - Named POIs: \(sortedNames.count)")
            print("   - Navigation nodes: \(nodeCount)")
            print("   - Path segments: \(pathCount)")
            print("   - Total features: \(features.count)")
            
            if !sortedNames.isEmpty {
                print("📍 Sample locations: \(sortedNames.prefix(5).joined(separator: ", "))...")
            }
            
            print("✅ POIExtractor: Successfully extracted \(sortedNames.count) POI names")
            return sortedNames
            
        } catch {
            print("❌ POIExtractor: JSON parsing error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Try multiple possible file names
    static func extractPOINamesWithFallback(fileNames: [String]) -> [String]? {
        for fileName in fileNames {
            if let names = extractPOINames(fileName: fileName), !names.isEmpty {
                return names
            }
        }
        return nil
    }
    
    /// Get diagnostic info
    static func getDiagnosticInfo(fileName: String = "map_data") -> String {
        var info = "=== GeoJSON Diagnostics ===\n"
        
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            info += "❌ File '\(fileName).json' not found\n"
            return info
        }
        
        info += "✅ File: \(url.lastPathComponent)\n"
        
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let features = json["features"] as? [[String: Any]] {
            info += "   Features: \(features.count)\n"
        }
        
        return info
    }
    
    // MARK: - Private Helpers
    
    private static func printBundleDiagnostics() {
        print("📦 Bundle Diagnostics:")
        print("   Path: \(Bundle.main.bundlePath)")
        
        if let resourcePath = Bundle.main.resourcePath,
           let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
            let jsonFiles = files.filter { $0.hasSuffix(".json") }
            if jsonFiles.isEmpty {
                print("   ⚠️ NO .json files found in bundle!")
            } else {
                print("   JSON files: \(jsonFiles)")
            }
        }
    }
}
