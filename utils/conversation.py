"""
Conversation Mode utilities for Indoor Navigation
Handles generation of detailed conversation mode responses with trip information
"""

from typing import List, Dict, Tuple, Any
from .calculations import calculate_distance, calculate_bearing, calculate_turn_angle
from .directions import get_direction_name, find_nearby_landmarks, determine_destination_position
from config import WALKING_SPEED

def generate_conversation_mode_response(session, door_qr_code: str) -> Dict[str, Any]:
    """
    Generate a detailed conversation mode response with trip information and step-by-step directions
    """
    try:
        # Get path coordinates and route information
        path_coords = session.path
        route_tracker = session.route_tracker
        segments = route_tracker.segments
        segment_bearings = route_tracker.segment_bearings
        step_metre_scale = route_tracker.step_metre_scale

        # Calculate total distance
        total_distance = 0.0
        for i in range(len(path_coords) - 1):
            segment_distance = calculate_distance(path_coords[i], path_coords[i + 1])
            total_distance += segment_distance

        # Estimate total duration (assuming average walking speed)
        total_duration = total_distance / WALKING_SPEED

        # Generate overall basic direction information
        overall_direction = generate_overall_direction_summary(session, door_qr_code, segments, segment_bearings)
        print(f"overall_direction: {overall_direction}")
        
        # Generate detailed trip directions
        detailed_trips = generate_detailed_trips(session, segments, segment_bearings, path_coords)
        print(f"detailed_instruction: {detailed_trips}")
        
        # Build the response
        response = {
            "search_parameters": {
                "start_address": session.source_name,
                "stop_address": session.destination_name,
                "start_address_coordinates": list(session.source),
                "stop_address_coordinates": list(session.destination)
            },
            "overall_trip_information": {
                "total_distance": f"{total_distance * step_metre_scale:.1f} steps.",  # in meters
                "total_duration": f"{total_duration:.1f} seconds.",  # in seconds
                "overall_basic_direction_information": overall_direction
            },
            "detailed_directions": {
                "travel_mode": "walking",
                "trips": detailed_trips
            }
        }

        return response

    except Exception as e:
        print(f"Error generating conversation mode response: {str(e)}")
        return None

def generate_overall_direction_summary(session, door_qr_code: str, segments: List, segment_bearings: List[float]) -> str:
    """Generate a high-level summary of the entire route with merged straight segments"""
    step_metre_scale = session.route_tracker.step_metre_scale

    if len(segment_bearings) < 2:
        return f"Continue straight to {session.destination_name}."

    actions = []

    # Handle initial door exit and first turn
    initial_bearing = segment_bearings[0]
    next_bearing = segment_bearings[1]
    turn_angle = calculate_turn_angle(initial_bearing, next_bearing)
    turn_direction = get_direction_name(turn_angle)
   
    if door_qr_code == "492159":
        actions.append(f"Exit the room and turn {turn_direction}")
    elif turn_direction == "straight ahead":
        actions.append("Continue straight ahead")
    else:
        actions.append(f"Turn {turn_direction}")

    # Accumulate distance until the next turn
    accumulated_distance = 0.0

    for i in range(1, len(segments) - 2):  # stop before the final destination segment
        current_bearing = segment_bearings[i]
        next_bearing = segment_bearings[i + 1] if i + 1 < len(segment_bearings) else current_bearing
        turn_angle = calculate_turn_angle(current_bearing, next_bearing)

        # add segment length to running total
        segment_distance = calculate_distance(segments[i][0], segments[i][1])
        accumulated_distance += segment_distance

        if abs(turn_angle) > 25:  # turn_angle_threshold
            # flush the accumulated straight distance before the turn
            actions[-1] += f" and continue for {accumulated_distance * step_metre_scale:.0f} steps"
            accumulated_distance = 0.0
            # add the new turn instruction
            turn_dir = get_direction_name(turn_angle)
            actions.append(f"Then turn {turn_dir}")

    # handle last straight stretch before destination
    if accumulated_distance > 0:
        actions[-1] += f" and continue for {accumulated_distance * step_metre_scale:.0f} steps"

    # Final destination
    destination_position = determine_destination_position(segments, segment_bearings)
    if destination_position == "straight ahead":
        destination_position = "front"

    actions.append(f"Destination will be {session.destination_name} at the {destination_position}")

    return ". ".join(actions) + "."

def generate_detailed_trips(session, segments: List, segment_bearings: List[float], path_coords: List) -> List[Dict]:
    """Generate detailed step-by-step trip information"""
    trips = []
    step_metre_scale = session.route_tracker.step_metre_scale

    for i in range(len(segments)):
        start_point, end_point = segments[i]
        segment_distance = calculate_distance(start_point, end_point)

        # Generate action description
        if i == 0:
            # First segment - exit room
            action = "Continue straight ahead"
        else:
            # Calculate turn from previous segment
            prev_bearing = segment_bearings[i - 1]
            current_bearing = segment_bearings[i]
            turn_angle = calculate_turn_angle(prev_bearing, current_bearing)

            if abs(turn_angle) > 25:  # turn_angle_threshold
                turn_direction = get_direction_name(turn_angle)
                action = f"Turn {turn_direction} and Continue"
            else:
                action = "Continue"

            # Add distance information
            action += f" for about {segment_distance * step_metre_scale:.0f} steps"

        # Find nearby landmarks
        nearby_landmarks = find_nearby_landmarks(start_point, end_point)

        # Determine path type
        path_type = "hallway"  # Default assumption for indoor navigation

        # Additional info for final segment
        additional_info = ""
        if i == len(segments) - 1:
            turn_angle = calculate_turn_angle(segment_bearings[-2], segment_bearings[-1])
            turn_direction = get_direction_name(turn_angle)

            if turn_direction == "straight ahead":
                additional_info = f"destination {session.destination_name} in the front." 
            else:
                additional_info = f"destination {session.destination_name} on the {turn_direction}."

            trip_info = {
                "destination_info": additional_info,
                "path": path_type,
                "additional_info": additional_info
            }
        else:
            trip_info = {
                "actions": action,
                "distance": f"{segment_distance * step_metre_scale:.0f} steps",
                "nearby_landmarks": nearby_landmarks,
                "path": path_type,
                "additional_info": additional_info
            }

        trips.append(trip_info)

    return trips