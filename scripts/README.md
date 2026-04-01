# Indoor Navigation API - Refactored

This is a refactored version of the Indoor Navigation API, broken down from a single monolithic file into a more maintainable modular structure with proper logging instead of print statements.

## Project Structure

```
indoor_navigation_app/
├── main.py                    # Main FastAPI application and startup
├── config.py                  # Configuration constants and settings
├── requirements.txt           # Python dependencies
├── README.md                  # This file
├── scripts/                   # Development and utility scripts (optional)
│   └── README.md             # Documentation for scripts
├── api/                       # API endpoints and routes
│   ├── __init__.py
│   └── routes.py             # Wayfinder and health check endpoints
├── models/                    # Pydantic models for requests/responses
│   ├── __init__.py
│   ├── requests.py           # Request models
│   └── responses.py          # Response models
├── core/                     # Core navigation logic
│   ├── __init__.py
│   ├── geojson_handler.py    # GeoJSON loading and graph building
│   ├── position_validator.py # Position validation and correction
│   ├── error_recovery.py     # Bearing-based error recovery
│   ├── navigation.py         # RouteTracker class
│   └── navigation_session.py # NavigationSession class
└── utils/                    # Utility functions
    ├── __init__.py
    ├── calculations.py       # Mathematical calculations
    ├── directions.py         # Direction and landmark utilities
    ├── conversation.py       # Conversation mode utilities
    └── logging_config.py     # Logging configuration and setup
```

## Key Components

### Configuration (`config.py`)
- All constants and configuration settings
- Navigation thresholds and parameters
- QR code IDs and file paths
- Logging configuration settings

### Core Components (`core/`)
- **GeoJSON Handler**: Loads and processes navigation data, builds graphs
- **Position Validator**: Validates and corrects user positions within corridors
- **Error Recovery**: Bearing-based error detection and recovery instructions
- **RouteTracker**: Main navigation logic for tracking progress along routes
- **NavigationSession**: Manages individual navigation sessions

### Utilities (`utils/`)
- **Calculations**: Mathematical helper functions for navigation
- **Directions**: Direction instructions and landmark detection
- **Conversation**: Detailed trip information and conversation mode responses
- **Logging Config**: Proper logging setup and configuration

### API (`api/`)
- **Routes**: FastAPI endpoint implementations
- Wayfinder endpoint for navigation requests
- Health check endpoint

### Models (`models/`)
- **Requests**: Pydantic models for API input validation
- **Responses**: Pydantic models for API responses

## Logging System

The application now uses Python's built-in `logging` module instead of print statements for better production-ready logging.

### Logging Configuration

The logging system is configured in `utils/logging_config.py` with:

- **Multiple log levels**: DEBUG, INFO, WARNING, ERROR, CRITICAL
- **Custom navigation levels**: NAVIGATION (25), BEARING_ANALYSIS (15), POSITION_UPDATE (12)
- **Configurable output**: Console and optional file logging
- **Structured format**: Timestamps, module names, function names, and line numbers

### Log Levels Used

- **ERROR**: Critical navigation errors, bearing recovery triggers
- **WARNING**: Wrong direction detection, significant deviations  
- **INFO**: Navigation milestones, turn confirmations, visual anchor events
- **NAVIGATION**: High-level navigation state changes (custom level)
- **DEBUG**: Detailed position updates, bearing calculations, landmark detection
- **BEARING_ANALYSIS**: Bearing-specific analysis (custom level)
- **POSITION_UPDATE**: Position validation details (custom level)

### Configuring Logging

You can configure logging behavior in `config.py`:

```python
LOGGING_CONFIG = {
    'level': 'INFO',        # Set to 'DEBUG' for verbose logging
    'file': None           # Set to a file path for file logging
}
```

Or set environment variables:
```bash
export LOG_LEVEL=DEBUG
export LOG_FILE=/path/to/logfile.log
```

### Example Log Output

```
2024-01-15 10:30:15 - indoor_navigation.core.navigation - INFO - update_position:320 - Signal visual anchor detected: 810870, turn signal activated
2024-01-15 10:30:16 - indoor_navigation.core.navigation - NAVIGATION - _handle_segment_transition:588 - normalized_dist_from_seg_start: 0.85, segment_id: 2, signal: turn_signal, current_user_position: [45.2, 23.1], turn_angle: True
2024-01-15 10:30:17 - indoor_navigation.core.error_recovery - ERROR - _trigger_recovery:195 - RECOVERY TRIGGERED - Avg bearing error: 135.2°
```

## Running the Application

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Ensure your GeoJSON file is available at the configured path (default: `/app/data/mcgillindoornavmerged.geojson`)

3. Configure logging (optional):
   ```bash
   export LOG_LEVEL=INFO
   export LOG_FILE=navigation.log
   ```

4. Run the application:
   ```bash
   python main.py
   ```
   Or with uvicorn:
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 5000
   ```

## Key Features Preserved

- All original functionality and behavior preserved
- Indoor wayfinding with IMU integration
- Bearing-based error recovery
- Position validation and correction
- Visual anchor (QR code) support
- Landmark-based directions
- Conversation mode with detailed trip information
- Clock and cardinal direction support

## Improvements Made

- **Modularity**: Code organized into logical modules
- **Maintainability**: Easier to understand, modify, and extend
- **Separation of Concerns**: Each module has specific responsibility
- **Professional Logging**: Structured, configurable logging system
- **Reusability**: Utility functions can be easily reused
- **Testing**: Individual components can be tested in isolation
- **Documentation**: Clear structure and comprehensive documentation

## Environment Variables

- `GEOJSON_PATH`: Path to the GeoJSON navigation data file (default: `/app/data/mcgindoornavmerged.geojson`)
- `LOG_LEVEL`: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- `LOG_FILE`: Optional path for log file output

## Dependencies

- FastAPI: Web framework
- Uvicorn: ASGI server
- Pydantic: Data validation
- NumPy: Numerical computations
- NetworkX: Graph algorithms
- SciPy: Scientific computing

## Development

For development, you can enable debug logging and file output:

```python
# In config.py
LOGGING_CONFIG = {
    'level': 'DEBUG',
    'file': 'navigation_debug.log'
}
```

All functionality, logging behavior, and navigation logic from the original monolithic file has been preserved in this refactored version with enhanced maintainability and professional logging capabilities.