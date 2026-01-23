# Indoor Navigation TACME - Android

[![Platform](https://img.shields.io/badge/platform-Android-green.svg)](https://developer.android.com/)
[![Kotlin](https://img.shields.io/badge/Kotlin-1.9.0-purple.svg)](https://kotlinlang.org/)
[![Jetpack Compose](https://img.shields.io/badge/UI-Jetpack%20Compose-blue.svg)](https://developer.android.com/jetpack/compose)

A complete indoor navigation system for visually impaired users, built with Kotlin and Jetpack Compose.

## 🎯 Features

- **IMU-based Dead Reckoning**: Weinberg step detection with gyroscope bearing integration
- **Smart QR Synchronization**: Real-time drift correction with QR codes
- **Bearing Correction**: Path-based correction at navigation segment changes
- **Step Calibration**: User-specific step length calibration
- **Priority TTS**: Multi-level instruction filtering system
- **AI Conversation**: Natural language route queries via OpenAI/Ollama
- **Bilingual Support**: English and French language support

## 📋 Requirements

- Android 8.0 (API level 26) or higher
- Android Studio Hedgehog or newer
- Physical Android device (sensors require real hardware)
- OpenAI API key (or local Ollama setup)

## 🚀 Quick Start
```bash
# Open the project
cd IndoorNavigationTACMEAndroidApp
# Open in Android Studio
```

### Configure API Key

Add your OpenAI API key in the app's conversation manager or configure Ollama endpoint.

### Build and Run

1. Connect a physical Android device
2. Enable Developer Options and USB Debugging
3. Click Run in Android Studio

## 📱 Android Framework Stack

- **SensorManager**: IMU sensor processing
- **ML Kit**: QR code detection
- **TextToSpeech**: Voice feedback
- **SpeechRecognizer**: Voice input
- **Jetpack Compose**: Modern declarative UI
- **Kotlin Coroutines**: Async operations
- **StateFlow**: Reactive state management
- **Retrofit**: Networking (optional)

## 📂 Project Structure
```
IndoorNavigationTACMEAndroidApp/
├── app/src/main/
│   ├── AndroidManifest.xml
│   ├── assets/
│   │   └── map_data.json
│   └── java/com/example/imunavigation/
│       ├── MainActivity.kt
│       ├── DataClasses.kt
│       ├── api/
│       │   └── NavigationAPI.kt
│       ├── calibration/
│       │   ├── IMUCalibrationManager.kt
│       │   └── UserStepFactorCalibration.kt
│       ├── conversation/
│       │   ├── ConversationManager.kt
│       │   └── OpenAIAPI.kt
│       ├── language/
│       │   └── LanguageManager.kt
│       ├── navigation/
│       │   └── NavigationManager.kt
│       ├── qr/
│       │   ├── QRCodeDetector.kt
│       │   └── QRIdExtractor.kt
│       ├── sensors/
│       │   ├── IMUSensorManager.kt
│       │   └── AccelerationDataLogger.kt
│       ├── tts/
│       │   └── TTSManager.kt
│       ├── voice/
│       │   └── VoiceInputManager.kt
│       └── screens/
│           └── NavigationScreen.kt
```

## 🔗 Related Projects

- **iOS Version**: See [`ios`](https://github.com/mohd-adnaan/PlaceFinder/tree/ios) branch
- **Navigation Server**: [IndoorNavigationTACME Backend](https://indoornavigationtacme-production.up.railway.app)

## 📖 Documentation

For detailed implementation and algorithms, see the source code documentation.

## 🎓 Research Context

This project is part of accessibility research at McGill University, focusing on indoor navigation solutions for visually impaired individuals.

## 📄 License

This project is part of the TACME Indoor Navigation research project.
