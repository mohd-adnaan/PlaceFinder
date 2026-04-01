"""
Directions utilities for Indoor Navigation
Contains functions for generating direction instructions and landmarks
"""

import math
from typing import List, Dict, Optional, Tuple
from core.geojson_handler import get_office_pois
from .calculations import calculate_distance, calculate_bearing, calculate_turn_angle

def get_direction_name(angle: float, use_clock: bool = False) -> str:
    """Convert angle to direction name (cardinal or clock directions)"""
    if not use_clock:
        # Cardinal direction method
        if -22.5 <= angle <= 22.5:
            return "straight ahead"
        elif 22.5 < angle <= 67.5:
            return "right"
        elif 67.5 < angle <= 112.5:
            return "right"
        elif 112.5 < angle <= 157.5:
            return "right"
        elif 157.5 < angle <= 180 or -180 <= angle < -157.5:
            return "make a U-turn"
        elif -157.5 <= angle < -112.5:
            return "left"
        elif -112.5 <= angle < -67.5:
            return "left"
        elif -67.5 <= angle < -22.5:
            return "left"
        return "unknown direction"
    else:
        # Clock position method
        if -90 <= angle < -22.5:  # Left
            clock_position = 9
        elif -22.5 <= angle <= 22.5:  # Straight ahead
            clock_position = 12
        elif 22.5 < angle <= 67.5:  # Right
            clock_position = 3
        elif 67.5 < angle <= 112.5:  # Sharp right
            clock_position = 4
        elif 112.5 < angle <= 157.5:  # Turn around right
            clock_position = 5
        elif 157.5 < angle <= 180 or -180 <= angle < -157.5:  # U-turn
            clock_position = 6
        elif -157.5 <= angle < -112.5:  # Turn around left
            clock_position = 7
        elif -112.5 <= angle < -67.5:  # Sharp left
            clock_position = 8

        return f"{clock_position} o'clock"

def find_nearby_landmarks(start_point: Tuple[float, float], end_point: Tuple[float, float]) -> List[Dict]:
    """Find office POIs near the given segment and label them left/right"""
    landmarks = []
    office_pois = get_office_pois()

    if office_pois:
        mid_point = [
            (start_point[0] + end_point[0]) / 2,
            (start_point[1] + end_point[1]) / 2
        ]

        # Bearing of the walking segment
        segment_bearing = calculate_bearing(start_point, end_point)

        for poi in office_pois:
            poi_coords = poi['geometry']['coordinates']
            poi_name = poi['properties']['name']

            # Distances from start, mid, end
            distance_to_start = math.dist(poi_coords, start_point)
            distance_to_end = math.dist(poi_coords, end_point)
            distance_to_mid = math.dist(poi_coords, mid_point)

            # Pick the closest reference point
            distances = {
                "start": distance_to_start,
                "end": distance_to_end,
                "mid": distance_to_mid
            }
            closest_point_name, min_dist = min(distances.items(), key=lambda x: x[1])

            if min_dist <= 3:  # within 3m threshold
                if closest_point_name == "start":
                    ref_point = start_point
                elif closest_point_name == "end":
                    ref_point = end_point
                else:
                    ref_point = mid_point

                # Bearing from ref_point to POI
                poi_bearing = calculate_bearing(ref_point, poi_coords)

                # Relative angle between walking direction and POI
                turn_angle = calculate_turn_angle(segment_bearing, poi_bearing)
                turn_direction = get_direction_name(turn_angle)

                if turn_direction == "make a U-turn":
                    turn_direction = "back"

                landmarks.append({
                    "name": poi_name,
                    "coordinates": poi_coords,
                    "direction": turn_direction
                })

    return landmarks[:4]  # limit to 4 landmarks

def get_landmark_direction(current_position: Tuple[float, float], 
                          current_segment: Tuple[Tuple[float, float], Tuple[float, float]],
                          current_segment_idx: int,
                          segments: List[Tuple[Tuple[float, float], Tuple[float, float]]],
                          use_landmarks_directions: bool = True,
                          user_bearing: Optional[float] = None) -> Optional[Dict]:
    """Get direction to nearby landmarks"""
    
    # Extract start coordinates from current segment
    start, end = current_segment
    office_pois = get_office_pois()

    # Check for the closest points of interest: This is to use landmark information
    print("use_landmarks_directions:", use_landmarks_directions)

    if office_pois and current_segment_idx < len(segments) - 2 and use_landmarks_directions:
        closest_poi = None
        min_distance = float('inf')
        name_of_closest_poi = ""

        # Loop through office POIs to find the closest one
        for poi in office_pois:
            poi_coords = poi['geometry']['coordinates']
            poi_name = poi['properties']['name']

            # Calculate Euclidean distance between user and POI
            distance = calculate_distance(current_position, poi_coords)

            # Update closest POI if this one is closer
            if distance < min_distance:
                min_distance = distance
                closest_poi = poi
                name_of_closest_poi = poi_name

        # If closest POI is within threshold, determine direction and return info
        print("Closest landmarks distance:", min_distance, "Closest_landmarks_name:", name_of_closest_poi)

        if min_distance <= 3 and closest_poi:
            poi_coords = closest_poi['geometry']['coordinates']
            poi_bearing = calculate_bearing(current_position, poi_coords)

            if user_bearing is None:
                 user_bearing = calculate_bearing(start, current_position)

            poi_angle = calculate_turn_angle(user_bearing, poi_bearing)
            poi_direction = get_direction_name(poi_angle)

            if poi_direction == "straight ahead":
                poi_direction = "front"

            return {
                "status": "landmark instructions",
                "message": f"{name_of_closest_poi} on your {poi_direction}.",
                "name": name_of_closest_poi,
                "direction": poi_direction
            }

        # Return None if no landmark found or conditions not met
        return None

def determine_destination_position(segments: List[Tuple[Tuple[float, float], Tuple[float, float]]], 
                                  segment_bearings: List[float]) -> str:
    """Determine if destination is on the left or right of the final approach"""
    if len(segments) < 2:
        return "ahead"

    # Calculate the bearing of the final approach segment
    final_approach_bearing = segment_bearings[-1]
    pre_final_approach_bearing = segment_bearings[-2]

    # Calculate the angle difference to determine left/right
    angle_to_destination = calculate_turn_angle(pre_final_approach_bearing, final_approach_bearing)
    destination_direction = get_direction_name(angle_to_destination)
    
    return destination_direction