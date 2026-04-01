# Indoor Navigation API 

A clean, maintainable indoor navigation system built with FastAPI.

## 🏗️ Architecture

The codebase has been refactored from a single 1000+ line file into a modular, maintainable structure:

```
indoor_navigation/
├── app.py                    # Main FastAPI application
├── config.py                 # Configuration settings
├── models.py                 # Data models and types
├── utils.py                  # Mathematical utilities
├── position_validator.py     # Position validation logic
├── error_recovery.py         # Error recovery system
├── route_tracker.py          # Core route tracking
├── navigation_session.py     # Session management
├── requirements.txt          # Dependencies
└── README.md                # This file
```



## Installation

```bash
pip install -r requirements.txt
```

## Configuration

Modify `config.py` to adjust navigation parameters:

```python
# Navigation settings
nav_config.step_size = 0.65  # meters
nav_config.bearing_threshold = 45  # degrees
nav_config.corridor_width = 3.0  # meters

# Error recovery settings
nav_config.duration_threshold = 2  # seconds
nav_config.recovery_cooldown = 5.0  # seconds
```

## Running the Application

```bash
python app.py
```

The server will start on `http://localhost:5000`

## API Endpoints

### Initialize Navigation
```http
POST /wayfinder
Content-Type: application/json
Session-ID: user123

{
  "action": "initialize",
  "source": "Room 101",
  "destination": "Room 205",
  "useClockDirections": false,
  "useLandmarks": true,
  "conversationMode": false
}
```

### Update Position
```http
POST /wayfinder
Content-Type: application/json
Session-ID: user123

{
  "action": "update",
  "currentX": 10.5,
  "currentY": 15.2,
  "currentBearing": 45.0,
  "qrDetected": true,
  "qrCodeId": "810870"
}
```

### Health Check
```http
GET /health
```

## Module Details

### `config.py`
Centralized configuration management using dataclasses:
- Navigation parameters
- Error recovery settings
- Server configuration
- QR code settings

### `models.py`
Type-safe data models using Pydantic:
- API request/response models
- Navigation state enums
- Data classes for internal use

### `utils.py`
Mathematical and utility functions:
- `MathUtils`: Distance, bearing, angle calculations
- `DirectionUtils`: Direction naming and conversion
- `GeometryUtils`: Geometric operations
- `ValidationUtils`: Data validation helpers

### `position_validator.py`
Position validation and correction:
- Validates user positions against route corridors
- Provides position corrections when needed
- Tracks validation statistics

### `error_recovery.py`
Bearing-based error recovery:
- Detects wrong direction navigation
- Provides recovery instructions
- Manages recovery state machine

### `route_tracker.py`
Core route tracking logic:
- Manages navigation along waypoints
- Handles segment transitions
- Coordinates with validation and recovery modules

### `navigation_session.py`
Session and graph management:
- Manages individual user sessions
- Handles graph pathfinding
- Provides landmark detection

### `app.py`
Main FastAPI application:
- API endpoint definitions
- Request routing
- Session management
- Error handling


## Error Handling

The system provides comprehensive error handling:
- Position validation errors
- Navigation path errors
- QR code detection errors
- Session management errors
- Configuration errors



