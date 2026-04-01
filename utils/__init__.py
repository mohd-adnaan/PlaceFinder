"""
Utils package for Indoor Navigation API
Contains utility functions for calculations, directions, conversation mode, and logging
"""

from .calculations import (
    calculate_distance, calculate_bearing, calculate_turn_angle,
    circular_mean, normalize_angle, angle_difference
)
from .directions import (
    get_direction_name, find_nearby_landmarks, get_landmark_direction,
    determine_destination_position
)
from .conversation import (
    generate_conversation_mode_response, generate_overall_direction_summary,
    generate_detailed_trips
)
from .logging_config import setup_logging, get_logger

__all__ = [
    'calculate_distance',
    'calculate_bearing',
    'calculate_turn_angle',
    'circular_mean',
    'normalize_angle',
    'angle_difference',
    'get_direction_name',
    'find_nearby_landmarks',
    'get_landmark_direction',
    'determine_destination_position',
    'generate_conversation_mode_response',
    'generate_overall_direction_summary',
    'generate_detailed_trips',
    'setup_logging',
    'get_logger'
]