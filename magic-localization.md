# ARKit Localization Implementation Plan

## Objective
Implement a "passive" initial localization system for visually impaired users. Instead of manually selecting a starting room or scanning a QR code, the user simply holds their phone naturally. The app will use ARKit's `ARWorldMap` spatial memory to instantly recognize the environment and automatically detect the user's exact X, Y starting coordinates and bearing.

---

## 🏗️ Architecture Additions

We will introduce three new components to the iOS app, ensuring we do not break the existing IMU or QR Code logic.

### 1. `ARMappingManager.swift` (Developer Tool)
**Purpose:** Handles the creation and saving of the spatial map.
- Uses `ARWorldTrackingConfiguration`.
- Monitors mapping status (`ARFrame.WorldMappingStatus`).
- Exports the physical geometry of the building to a file (`BuildingMap.arexperience`).

### 2. `ARMappingView.swift` (Developer UI)
**Purpose:** A hidden SwiftUI screen used strictly by the developer/admin.
- Displays the live camera feed and a visual point cloud of Feature Points.
- Contains "Start Mapping" and "Save Map" buttons.
- Only used once per building to generate the map file.

### 3. `ARLocalizationManager.swift` (Production Tool)
**Purpose:** The engine running for the end user.
- Loads the bundled `BuildingMap.arexperience`.
- Runs an invisible `ARSession` when the app starts.
- Listens for `session.didChangeState = .normal` (Relocalized).
- Extracts the iPhone's `[X, Z]` translation matrix and `Y` rotation (bearing).
- Shuts down the camera to save battery once the initial position is locked.

---

## 🔗 Integration with Existing System

To make ARKit work with your existing `NavigationManager` and `IMUSensorManager`, we need to align the data.

### Coordinate Transformation
ARKit uses meters, but its `[0,0]` origin is arbitrary (wherever the map was originally started). 
- We will define a **Map Offset Variable** in `Config.xcconfig` or `Models.swift`.
- Example: If the physical front door is `ARKit [0,0]` but your GeoJSON backend expects the front door to be `GeoJSON [15.5, 20.0]`, we apply an offset: `realX = arkitX + 15.5`.

### Handoff to IMU
1. App opens. `ARLocalizationManager` starts.
2. User walks 2 steps. ARKit recognizes the hallway.
3. ARKit fires `onLocationLocked(x, y, bearing)`.
4. We inject these values into `NavigationManager.shared.currentX`, `currentY`, and `currentBearing`.
5. We kill the `ARSession` and start the existing `IMUSensorManager` for standard low-power dead reckoning.

---

## 🛤️ Implementation Phases

### Phase 1: Build the Mapper (Day 1)
1. Create `ARMappingManager.swift`.
2. Create `ARMappingView.swift`.
3. Add a temporary button to your main screen to open the Mapper.
4. **Action:** Walk down your hallway, press save, and verify the `.arexperience` file is generated.

### Phase 2: Build the Relocalizer (Day 2)
1. Create `ARLocalizationManager.swift`.
2. Add the generated `.arexperience` file to the Xcode Bundle.
3. Write the logic to load the file and listen for the `relocalizing` status.
4. **Action:** Print the coordinates to the Xcode console to prove the app recognizes the hallway instantly.

### Phase 3: Alignment & UI (Day 3)
1. Write the math function to convert ARKit `(X, Z)` to GeoJSON `(X, Y)`.
2. Update the main App Startup UI: Remove the "Select Source" dropdown. Replace it with an automatic loader that says *"Locating you..."* and uses TTS to announce when the location is found.
3. **Action:** Test the full flow. Open app -> ARKit finds position -> Handoff to IMU -> Navigation starts.

