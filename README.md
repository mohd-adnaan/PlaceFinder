# TACME — Indoor Navigation for the Visually Impaired (iOS)

A complete indoor navigation system for visually impaired users. Originally converted from an Android (Kotlin/Jetpack Compose) prototype to iOS (Swift/SwiftUI), and since extended with ARKit-based spatial localization, voice-driven navigation, and conversational AI wayfinding.

This project is the basis of the peer-reviewed paper **["It Could Literally Change My Life": Exploring the Potential of Conversational Interaction for Indoor Wayfinding Among People with Visual Impairments](https://www.researchgate.net/publication/405480831)** — see [Research](#research) below.

## Features

- **IMU-based Dead Reckoning**: Weinberg step detection with gyroscope bearing integration (50 Hz, Butterworth-filtered)
- **ARKit World-Map Localization**: passive, automatic initial positioning by recognizing the environment (spatial cone matching + visual fingerprints + IMU cross-check) instead of manual source selection or QR scanning
- **Smart QR Synchronization**: 3-second persistence window, rapid change detection for drift correction
- **Bearing Correction**: path-based correction at navigation segment changes
- **Step Calibration**: user-specific step length calibration (20 m walk)
- **Priority TTS**: never-miss, critical, priority, regular instruction filtering
- **Voice-Controlled Navigation**: set source/destination hands-free via speech, with fuzzy POI matching and a confirmation flow
- **AI Conversation**: natural language route queries via OpenAI and Google Gemini
- **Bilingual Support**: real-time translation between English and French
- **Debug Tooling**: in-app debug overlay, session data export, and remote logging for field testing

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Physical iOS device (motion sensors and ARKit require real hardware)
- API keys: Google Gemini and OpenAI (for AI conversation features)

## Project Structure

```
IndoorNavigationTACMEiOS/
├── IndoorNavigationTACME.xcodeproj
└── IndoorNavigationTACME/
    ├── IndoorNavigationTACMEApp.swift       # Main app entry point
    ├── Info.plist                            # App configuration & permissions
    ├── Config.xcconfig                        # API keys & endpoints (gitignored)
    ├── Config_EXAPMLE.xcconfig                # Template for Config.xcconfig
    ├── Assets.xcassets/                      # App icons and colors
    ├── map_data.json                          # Building POI / map data
    ├── Models/
    │   └── Models.swift                      # All data structures
    ├── Network/
    │   ├── NavigationAPIService.swift        # Navigation server API
    │   ├── GeminiService.swift               # Google Gemini integration
    │   ├── OpenAIService.swift                # OpenAI integration
    │   └── LogWebAppService.swift             # Remote session logging
    ├── Managers/
    │   ├── IMUSensorManager.swift            # CoreMotion step detection
    │   ├── IMUCalibrationManager.swift       # Position/bearing calibration
    │   ├── ARMappingManager.swift             # ARKit world-map build & localization
    │   ├── TTSManager.swift                  # AVSpeechSynthesizer with priorities
    │   ├── QRCodeDetector.swift              # Vision framework QR detection
    │   ├── LanguageManager.swift             # Bilingual support
    │   ├── NavigationManager.swift           # Core navigation coordinator
    │   ├── ConversationManager.swift         # Speech recognition & AI conversation
    │   └── VoiceNavigationManager.swift       # Voice-driven source/destination input
    ├── Views/
    │   ├── NavigationScreen.swift            # Main navigation interface
    │   ├── NavigationSettingsView.swift       # Settings, calibration, debug mode
    │   ├── ARMappingView.swift                # AR localization + map visualization preview
    │   ├── LandingPageView.swift               # App entry / launch screen
    │   ├── ConversationOrbView.swift           # Audio-reactive voice UI
    │   └── Components/
    │       ├── StatusIndicatorView.swift
    │       ├── NavigationInputSection.swift
    │       ├── StepCalibrationCard.swift
    │       ├── InstructionCard.swift
    │       ├── NavigationControlsView.swift
    │       ├── QRDetectionCard.swift
    │       ├── ConversationSection.swift
    │       └── DebugOverlayView.swift
    └── Utilities/
        ├── POIExtractor.swift                 # POI extraction from map data
        ├── DataExportManager.swift            # Session data export
        └── DebugLogger.swift                  # Structured debug logging
```

## Setup Instructions

### 1. Clone and Open Project

```bash
open IndoorNavigationTACMEiOS/IndoorNavigationTACME.xcodeproj
```

### 2. Configure API Keys

Copy `Config_EXAPMLE.xcconfig` to `Config.xcconfig` in the same directory and fill in your keys:

```xcconfig
GEMINI_API_KEY = "your-api-key-here",
OPENAI_API_KEY = "your-api-key-here"
LOG_WEB_APP_URL = "https://script.google.com/macros/s/your-web-app-id/exec"
```

`Config.xcconfig` is gitignored — never commit real keys.

### 3. Configure Signing

1. Select the project in the navigator
2. Select the "IndoorNavigationTACME" target
3. Go to "Signing & Capabilities"
4. Select your Development Team
5. Update the Bundle Identifier if needed

### 4. Build and Run

1. Connect a physical iOS device (required for sensors and ARKit)
2. Select your device as the build target
3. Press Cmd+R to build and run

## iOS Framework Mappings

| Feature | Android | iOS |
|---------|---------|-----|
| Motion Sensors | SensorManager | CoreMotion (CMMotionManager) |
| Spatial Localization | — | ARKit (ARWorldTrackingConfiguration) |
| QR Detection | ML Kit Barcode | Vision (VNDetectBarcodesRequest) |
| Text-to-Speech | TextToSpeech | AVSpeechSynthesizer |
| Speech Recognition | SpeechRecognizer | Speech (SFSpeechRecognizer) |
| Networking | Retrofit | URLSession + async/await |
| Concurrency | Coroutines | Swift Concurrency (Task/async) |
| UI Framework | Jetpack Compose | SwiftUI |
| Storage | SharedPreferences | UserDefaults |

## Key Implementation Details

### IMU Sensor Manager
- Uses `CMMotionManager` with `.xArbitraryZVertical` reference frame
- 50 Hz update rate (0.02 s interval)
- Butterworth filter approximation for step detection
- Weinberg method: `stepLength = beta * (peakValleyDiff)^0.25`
- iOS gyroscope Z-axis inverted: `bearing += gyroZ * dt * (-180/π)`
- Map/IMU frame convention: +X east, +Y north, bearing 0° = N

### ARKit World-Map Localization

- `ARMappingManager` builds a spatial map from POI visual fingerprints and feature-point clouds, then relocalizes returning users automatically instead of requiring manual source selection or a QR scan
- Matching combines spatial cone matching, visual fingerprint comparison, and an IMU motion cross-check, gated by a stability threshold (5 consecutive frames / 1.2 s) before a fix is trusted
- ARKit's `.gravityAndHeading` session uses +X east, **-Z north** — converting to the map frame requires negating Z: `heading = atan2(x, -z)`
- `ARMappingView` includes a live map visualization preview (rendered POI layout and scan progress) for verifying coverage while mapping a building

### QR Code Detection
- Vision framework `VNDetectBarcodesRequest` with `.qr` symbology
- 1280x720 capture resolution
- Walking mode: process every 3rd frame for performance
- Smart sync: 3 s persistence, 200 ms change detection window

### TTS Manager
- Priority system: Emergency > Critical > Never-miss > Priority > Regular
- One-time instructions: "arrived", "reached" spoken once per session
- Speech rate: 0.52 (slightly faster than default)
- Audio session: `.playback` with duck others

### Voice Navigation & Conversation

- `VoiceNavigationManager` drives hands-free source/destination selection: listen → fuzzy-match against POIs → confirm → repeat for the other endpoint
- `ConversationManager` layers natural-language route queries and Q&A on top, backed by OpenAI and Gemini
- `ConversationOrbView` gives an audio-reactive visual (mic RMS-driven particle orb) as a companion cue during voice interaction

### Navigation Manager
- Session ID: `ios_session_{timestamp}`
- Update interval: 50 ms
- Smart QR state: immediate detection + 3 s persistence
- Bearing correction threshold: 25°

### Debug Tools

- In-app debug overlay (`DebugOverlayView`), toggled from Settings, surfaces live sensor/localization state during field testing
- `DataExportManager` exports full session traces for offline analysis
- `LogWebAppService` streams session logs to a remote Google Apps Script endpoint

## API Endpoints

- **Navigation Server**: `https://indoornavigationtacme-production.up.railway.app/wayfinder`
- **Google Gemini**: `https://generativelanguage.googleapis.com/v1beta/models`
- **OpenAI**: standard OpenAI API

## Permissions Required

The app requires the following permissions (configured in Info.plist):

- **Camera**: QR code detection and ARKit world-map localization
- **Microphone**: voice commands and AI conversation
- **Speech Recognition**: processing voice input
- **Motion Sensors**: step detection and indoor positioning
- **Background Audio**: continuous TTS during navigation

## Testing Checklist

- [ ] IMU sensor initialization and step detection
- [ ] ARKit world-map localization (initial fix + relocalization)
- [ ] QR code detection with Vision framework
- [ ] TTS priority system and language switching
- [ ] Navigation API communication
- [ ] Calibration flow (initial + recalibration)
- [ ] Smart QR synchronization
- [ ] Bearing correction at segment changes
- [ ] Voice-driven source/destination selection
- [ ] Voice conversation (OpenAI + Gemini)
- [ ] Bilingual translation (EN↔FR)
- [ ] Step length calibration (20 m walk)
- [ ] Complete navigation session (source → destination)

## Troubleshooting

### Sensors not working

- Ensure you're running on a physical device, not the simulator
- Check that motion permissions are granted in Settings

### ARKit localization not recognizing the environment

- Ensure adequate, consistent lighting — ARKit relies on visual feature points
- Re-map the building if furniture/layout has changed significantly since the last map was built
- Check the debug overlay for stability-gate and match-confidence values

### QR detection issues
- Verify camera permission is granted
- Ensure adequate lighting for QR code visibility
- Check QR codes match expected format: `QR_Id:https://qrco.de/...`

### TTS not speaking
- Check device is not on silent mode
- Verify audio permission is granted
- Check TTS language matches current app language

### API errors

- Verify Gemini/OpenAI API keys are configured correctly in `Config.xcconfig`
- Check network connectivity
- Ensure navigation server is accessible

## Research

This application is the platform behind:

> **"It Could Literally Change My Life": Exploring the Potential of Conversational Interaction for Indoor Wayfinding Among People with Visual Impairments**
> [ResearchGate publication](https://www.researchgate.net/publication/405480831_It_Could_Literally_Change_My_Life_Exploring_the_Potential_of_Conversational_Interaction_for_Indoor_Wayfinding_Among_People_with_Visual_Impairments)

The paper reports on user studies exploring how conversational, voice-driven interaction (as implemented in `VoiceNavigationManager` and `ConversationManager`) affects indoor wayfinding outcomes and experience for people with visual impairments.

## License

This project is part of the TACME Indoor Navigation research project.
