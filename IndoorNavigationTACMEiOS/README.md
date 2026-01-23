# Indoor Navigation TACME - iOS

A complete indoor navigation system for visually impaired users, converted from Android (Kotlin/Jetpack Compose) to iOS (Swift/SwiftUI).

## Features

- **IMU-based Dead Reckoning**: Weinberg step detection with gyroscope bearing integration
- **Smart QR Synchronization**: 3-second persistence window, rapid change detection for drift correction
- **Bearing Correction**: Path-based correction at navigation segment changes
- **Step Calibration**: User-specific step length calibration (20m walk)
- **Priority TTS**: Never-miss, critical, priority, regular instruction filtering
- **AI Conversation**: Natural language route queries via OpenAI GPT
- **Bilingual Support**: Real-time translation between English and French

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Physical iOS device (sensors require real hardware)
- Google Gemini API key for AI conversation features

## Project Structure

```
IndoorNavigationTACME/
├── IndoorNavigationTACMEApp.swift       # Main app entry point
├── Info.plist                            # App configuration & permissions
├── Assets.xcassets/                      # App icons and colors
├── Models/
│   └── Models.swift                      # All data structures
├── Network/
│   ├── NavigationAPIService.swift        # Navigation server API
│   └── GeminiService.swift               # Google Gemini API integration
├── Managers/
│   ├── IMUSensorManager.swift            # CoreMotion step detection
│   ├── IMUCalibrationManager.swift       # Position/bearing calibration
│   ├── TTSManager.swift                  # AVSpeechSynthesizer with priorities
│   ├── QRCodeDetector.swift              # Vision framework QR detection
│   ├── LanguageManager.swift             # Bilingual support
│   ├── NavigationManager.swift           # Core navigation coordinator
│   └── ConversationManager.swift         # Speech recognition & AI
├── Views/
│   ├── NavigationScreen.swift            # Main navigation interface
│   └── Components/
│       ├── StatusIndicatorView.swift
│       ├── NavigationInputSection.swift
│       ├── StepCalibrationCard.swift
│       ├── InstructionCard.swift
│       ├── NavigationControlsView.swift
│       ├── QRDetectionCard.swift
│       └── ConversationSection.swift
└── Utilities/
    └── POIExtractor.swift                # POI extraction from map data
```

## Setup Instructions

### 1. Clone and Open Project

```bash
# Open the project in Xcode
open IndoorNavigationTACME.xcodeproj
```

### 2. Configure API Key

Add your Google Gemini API key in one of these ways:

**Option A: Environment Variable (Recommended)**
1. Edit scheme (Product → Scheme → Edit Scheme)
2. Go to Run → Arguments → Environment Variables
3. Add: `GEMINI_API_KEY` = `your-api-key-here`

**Option B: Build Settings**
1. Go to Build Settings
2. Add User-Defined Setting: `GEMINI_API_KEY` = `your-api-key-here`

### 3. Configure Signing

1. Select the project in the navigator
2. Select the "IndoorNavigationTACME" target
3. Go to "Signing & Capabilities"
4. Select your Development Team
5. Update Bundle Identifier if needed

### 4. Build and Run

1. Connect a physical iOS device (required for sensors)
2. Select your device as the build target
3. Press Cmd+R to build and run

## iOS Framework Mappings

| Feature | Android | iOS |
|---------|---------|-----|
| Motion Sensors | SensorManager | CoreMotion (CMMotionManager) |
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
- 50Hz update rate (0.02s interval)
- Butterworth filter approximation for step detection
- Weinberg method: `stepLength = beta * (peakValleyDiff)^0.25`
- iOS gyroscope Z-axis inverted: `bearing += gyroZ * dt * (-180/π)`

### QR Code Detection
- Vision framework `VNDetectBarcodesRequest` with `.qr` symbology
- 1280x720 capture resolution
- Walking mode: process every 3rd frame for performance
- Smart sync: 3s persistence, 200ms change detection window

### TTS Manager
- Priority system: Emergency > Critical > Never-miss > Priority > Regular
- One-time instructions: "arrived", "reached" spoken once per session
- Speech rate: 0.52 (slightly faster than default)
- Audio session: `.playback` with duck others

### Navigation Manager
- Session ID: `ios_session_{timestamp}`
- Update interval: 50ms
- Smart QR state: immediate detection + 3s persistence
- Bearing correction threshold: 25°

## API Endpoints

- **Navigation Server**: `https://indoornavigationtacme-production.up.railway.app/wayfinder`
- **Google Gemini**: `https://generativelanguage.googleapis.com/v1beta/models`

## Permissions Required

The app requires the following permissions (configured in Info.plist):

- **Camera**: QR code detection for navigation accuracy
- **Microphone**: Voice commands and AI conversation
- **Speech Recognition**: Processing voice input
- **Motion Sensors**: Step detection and indoor positioning
- **Background Audio**: Continuous TTS during navigation

## Testing Checklist

- [ ] IMU sensor initialization and step detection
- [ ] QR code detection with Vision framework
- [ ] TTS priority system and language switching
- [ ] Navigation API communication
- [ ] Calibration flow (initial + recalibration)
- [ ] Smart QR synchronization
- [ ] Bearing correction at segment changes
- [ ] Voice conversation with OpenAI
- [ ] Bilingual translation (EN↔FR)
- [ ] Step length calibration (20m walk)
- [ ] Complete navigation session (source → destination)

## Troubleshooting

### Sensors not working
- Ensure you're running on a physical device, not simulator
- Check that motion permissions are granted in Settings

### QR detection issues
- Verify camera permission is granted
- Ensure adequate lighting for QR code visibility
- Check QR codes match expected format: `QR_Id:https://qrco.de/...`

### TTS not speaking
- Check device is not on silent mode
- Verify audio permission is granted
- Check TTS language matches current app language

### API errors
- Verify Gemini API key is configured correctly
- Check network connectivity
- Ensure navigation server is accessible

## License

This project is part of the TACME Indoor Navigation research project.

## Credits

Converted from Android by Claude AI assistant.
Original Android implementation: IndoorNavigationTACMEAndroidApp
