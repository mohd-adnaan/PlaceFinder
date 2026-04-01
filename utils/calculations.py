"""
Calculation utilities for Indoor Navigation
Contains mathematical helper functions for navigation calculations
"""

import math
from typing import List, Tuple

def calculate_distance(p1: Tuple[float, float], p2: Tuple[float, float]) -> float:
    """Calculate Euclidean distance between two points"""
    return math.sqrt((p2[0] - p1[0])**2 + (p2[1] - p1[1])**2)

def calculate_bearing(p1: Tuple[float, float], p2: Tuple[float, float]) -> float:
    """Calculate bearing from p1 to p2 in degrees (0 = East, 90 = North)"""
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    angle = math.degrees(math.atan2(dy, dx))
    # Convert to 0-360 range
    bearing = (90 - angle) % 360
    return bearing

def calculate_turn_angle(current_bearing: float, target_bearing: float) -> float:
    """Calculate the angle to turn from current bearing to target bearing"""
    angle = (target_bearing - current_bearing) % 360
    # Convert to -180 to 180 range for more intuitive instructions
    if angle > 180:
        angle -= 360
    return angle

def circular_mean(angles_deg: List[float]) -> float:
    """Calculate circular mean of angles in degrees"""
    angles_rad = [math.radians(angle) for angle in angles_deg]
    sin_sum = sum(math.sin(a) for a in angles_rad)
    cos_sum = sum(math.cos(a) for a in angles_rad)
    circular_mean_rad = math.atan2(sin_sum, cos_sum)
    return math.degrees(circular_mean_rad)

def normalize_angle(angle: float) -> float:
    """Normalize angle to 0-360 range"""
    return angle % 360

def angle_difference(angle1: float, angle2: float) -> float:
    """Calculate signed difference between two angles (-180 to +180)"""
    diff = (angle1 - angle2) % 360
    if diff > 180:
        diff -= 360
    return diff