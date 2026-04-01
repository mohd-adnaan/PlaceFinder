"""
Configuration file for Indoor Navigation API
Contains all constants and configuration settings
"""

import time

# Server configuration
SERVER_TITLE = "Indoor Navigation API"
SERVER_DESCRIPTION = "Navigation server for indoor wayfinding with IMU integration"
SERVER_VERSION = "1.0.0"

# Navigation constants
class NavigationConfig:
    # RouteTracker settings
    STEP_SIZE = 0.65  # meters
    MOVEMENT_PROGRESS_THRESHOLD = 0.80
    BEARING_DIFFERENCE_THRESHOLD = 25  # degrees
    MAX_ROUTE_DEVIATION_THRESHOLD = 1  # meters
    TURN_ANGLE_THRESHOLD = 25  # degrees
    TURN_THRESH = 0.80
    
    # Turn warning thresholds
    MIN_TURN_WARNING_THRESH_LEVEL1 = 0.01
    MAX_TURN_WARNING_THRESH_LEVEL1 = 0.5
    MIN_TURN_WARNING_THRESH_LEVEL2 = 0.2
    MAX_TURN_WARNING_THRESH_LEVEL2 = 0.5
    MIN_TURN_WARNING_THRESH = 0.10
    MAX_TURN_WARNING_THRESH = 0.5
    
    # Navigation thresholds
    IS_ON_TRACK_THRESH = 0.2
    APPROACHING_DESTINATION_THRESH = 0.1
    AT_DESTINATION_THRESH = 0.5
    SEGMENT_ADVANCE_THRESH = 0.8 #0.7
    
    # Error and timing settings
    ERROR_DECISION_WAIT_TIME = 10  # seconds
    STEP_METRE_SCALE = 1.25  # steps
    
    # QR Code IDs
    INITIATE_TURN_QR = '810870'
    CONFIRM_TURN_QR = '810800'

# Bearing Error Recovery settings
class BearingErrorConfig:
    BEARING_THRESHOLD = 45  # degrees difference to consider "wrong direction"
    DURATION_THRESHOLD = float('inf') #10  # seconds of wrong bearing before triggering recovery
    MIN_SAMPLES = 3  # minimum bearing samples needed
    RECOVERY_COOLDOWN = 5.0  # seconds between recovery instructions
    LARGE_BEARING_ERROR = 120  # degrees for opposite direction detection
    USER_POSITION_DEVIATION_THRESHOLD = 2.5 #2 #1  # meters
    USER_ERROR_DETECTION_THRESHOLD = 6 #2  # meters
    MAX_HISTORY = 10  # maximum bearing history entries

# Position Validator settings
class PositionValidatorConfig:
    CORRIDOR_WIDTH = 3.0  # meters

# Graph building settings
class GraphConfig:
    NODE_DISTANCE_THRESHOLD = 0.001  # Small threshold for exact point matching
    EDGE_DISTANCE_THRESHOLD = 0.5    # Threshold for connecting nodes
    LANDMARK_DISTANCE_THRESHOLD = 2.5   # Distance threshold for landmarks

# File paths
import os
GEOJSON_PATH = os.getenv('GEOJSON_PATH', '/app/data/mcgindoornavmerged.geojson')

# Server timing
SERVER_START_TIME = time.time()

# Global storage for active sessions
SESSIONS = {}

# Walking speed for time estimates
WALKING_SPEED = 1.4  # meters per second

# Logging configuration
LOGGING_CONFIG = {
    'level': 'INFO',
    'file': None  # Set to a file path to enable file logging
}