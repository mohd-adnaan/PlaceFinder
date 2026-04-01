import os
import numpy as np
import math
import json
import networkx as nx
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import List, Dict, Optional, Any, Tuple, Union
from scipy.spatial import distance
import time
import sys
import uvicorn

# Initialize FastAPI app
app = FastAPI(
    title="Indoor Navigation API",
    description="Navigation server for indoor wayfinding with IMU integration",
    version="1.0.0"
)

# Store active navigation sessions
sessions = {}

# Load GeoJSON data
geojson_data = None
navigation_graph = nx.Graph()
poi_mapping = {}
office_pois = {}

# Request/Response Models
class InitializeRequest(BaseModel):
    action: str = "initialize"
    source: str
    destination: str
    useClockDirections: bool = False
    useLandmarks: bool = False
    conversationMode: bool = False
    qrId: Optional[str] = None

class UpdateRequest(BaseModel):
    action: str = "update"
    currentX: float
    currentY: float
    currentBearing: float
    magneticFieldStrength: Optional[float] = None
    qrDetected: bool = False
    qrCodeId: Optional[str] = None

class CalibrationData(BaseModel):
    mapStartX: float
    mapStartY: float
    initialBearing: Optional[float] = None

class SegmentInfo(BaseModel):
    segmentIndex: int
    isSignificantTurn: Optional[bool] = None

class NavigationResponse(BaseModel):
    status: str
    message: Optional[str] = None
    instructions: Optional[str] = None
    navigationStarted: Optional[bool] = None
    pathCoordinates: Optional[List[List[float]]] = None
    pathBearings: Optional[List[float]] = None
    calibration: Optional[CalibrationData] = None
    waypoint: Optional[List[float]] = None
    distance_passed: Optional[float] = None
    return_turn: Optional[str] = None
    return_angle: Optional[float] = None
    correct_turn: Optional[str] = None
    correct_angle: Optional[float] = None
    deviation_type: Optional[str] = None
    correction_point: Optional[List[float]] = None
    new_map_position: Optional[List[float]] = None
    conversation_mode: Optional[bool] = None
    conversation_data: Optional[Any] = None
    segmentInfo: Optional[SegmentInfo] = None
    validation_stats: Optional[Dict] = None


class HealthResponse(BaseModel):
    status: str
    timestamp: float
    geojson_loaded: bool
    total_sessions: int
    uptime_seconds: float


# Store server start time for uptime calculation
server_start_time = time.time()



# Store active navigation sessions
sessions = {}

# Load GeoJSON data - this would be loaded from a file in production
geojson_data = None  # Will be loaded when the server starts

# Track route segment
segment_count = 0
def load_geojson(geojson_str):
    """Load GeoJSON data from string"""
    global geojson_data
    geojson_data = json.loads(geojson_str)
    build_navigation_graph()



# Graph to store the navigable network
navigation_graph = nx.Graph()
# Dictionary to map POI names to node coordinates
poi_mapping = {}
office_pois = {}

def build_navigation_graph():
    """Build a navigation graph from GeoJSON data"""
    global navigation_graph, poi_mapping, office_pois

    # Clear existing graph
    navigation_graph.clear()

    # Extract room offices as landmarks
    office_pois = [
        feature for feature in geojson_data['features']
        if feature['geometry']['type'] == 'Point' and feature.get('properties') 
            and feature['properties'].get('category') != 'node'
    ]

    #print(f"Office_Pois: {office_pois}")


    # Extract POIs (nodes)
    for feature in geojson_data['features']:
        if feature['geometry']['type'] == 'Point':
            coords = feature['geometry']['coordinates']
            node_id = feature['properties']['id']
            #node_name = feature['properties']['name']
            node_name = feature.get('properties', {}).get('name')

            if not node_name:  # 
                node_name = f"node_{node_id}"
                #print (f"node_name: {node_name}")


            # Add node to graph
            navigation_graph.add_node(node_id,
                                      coordinates=(coords[0], coords[1]),
                                      name=node_name)

            # Add to POI mapping
            poi_mapping[node_name] = (coords[0], coords[1])
    #print(f"POI_Mapping: {poi_mapping}")

    # Extract paths (edges)
    for feature in geojson_data['features']:
        if feature['properties']['type'] == 'path':
            if feature['geometry']['type'] == 'MultiLineString':
                path_coords = feature['geometry']['coordinates'][0]  # Get first linestring

                # Connect each segment in the path
                for i in range(len(path_coords) - 1):
                    # Find closest nodes to the start and end of this segment
                    start_point = (path_coords[i][0], path_coords[i][1])
                    end_point = (path_coords[i+1][0], path_coords[i+1][1])

                    start_node = find_closest_node(start_point)
                    end_node = find_closest_node(end_point)

                    if start_node and end_node and start_node != end_node:
                        # Calculate Euclidean distance between nodes
                        dist = np.sqrt((start_point[0] - end_point[0])**2 +
                                      (start_point[1] - end_point[1])**2)

                        # Add edge to graph with weight equal to distance
                        navigation_graph.add_edge(start_node, end_node, weight=dist)



def find_closest_node(point):
    """Find the closest node in the graph to the given point"""
    min_dist = float('inf')
    closest_node = None

    for node, attrs in navigation_graph.nodes(data=True):
        node_coords = attrs['coordinates']
        dist = np.sqrt((point[0] - node_coords[0])**2 + (point[1] - node_coords[1])**2)

        # Use a small threshold to match exact points
        if dist < 0.001:  # Small distance threshold
            return node

        if dist < min_dist:
            min_dist = dist
            closest_node = node

    # Only return nodes that are reasonably close (to avoid connecting unrelated points)
    if min_dist < 0.5:  # Threshold distance
        return closest_node
    return None

def get_point_from_name(name):
    """Get coordinates for a named POI"""
    if name in poi_mapping:
        return poi_mapping[name]
    return None


class BearingErrorRecovery:
    """
    Pure bearing-based error recovery system that doesn't rely on position data
    """
    def __init__(self, bearing_threshold=45, duration_threshold=2, min_samples=3):
        self.bearing_threshold = bearing_threshold  # degrees difference to consider "wrong direction"
        self.duration_threshold = duration_threshold  # seconds of wrong bearing before triggering recovery
        self.min_samples = min_samples  # minimum bearing samples needed

        # Error tracking state
        self.wrong_bearing_start_time = None
        self.wrong_bearing_samples = []
        self.is_in_recovery_mode = False
        self.recovery_instruction_given = False
        self.last_recovery_time = None
        self.recovery_cooldown = 5.0  # seconds between recovery instructions

        # Bearing history for analysis
        self.bearing_history = []
        self.max_history = 10

        # Will be set by RouteTracker after initialization
        self.route_tracker = None
        self.segments = None
        self.current_segment_idx = None
        self.use_landmarks_directions = None
        self.is_turn_signal_enabled = False
        self.re_alignment_start_time = None
        self.avg_bearing_error = 0.0
        self.large_bearing_error = 120 #125 I may need to increase back to 125, then set threshold distance to higher from 2 in case the user is not a turn when receive turn instruction. otherwise this would be the best approach to prevent user from going far before getting error alert
        self.last_known_user_position_before_error = None
        self.user_position_deviation_threshold = 1 ## metres
        self.user_error_detection_threshold = 2 # metres

    def set_route_tracker(self, route_tracker):
      """Set reference to the parent RouteTracker instance"""
      self.route_tracker = route_tracker
      self.segments = route_tracker.segments
      self.current_segment_idx = route_tracker.current_segment_idx
      self.use_landmarks_directions = route_tracker.use_landmarks_directions
      



    def update_bearing_tracking(self, user_bearing, expected_bearing, current_user_position, expected_segment, timestamp=None):
        """
        Update bearing tracking and detect if user is going wrong direction

        Args:
            user_bearing: Current bearing from client (compass/gyroscope)
            expected_bearing: Expected bearing for current segment
            timestamp: Current time (will use current time if None)

        Returns:
            dict: Recovery instruction if error detected, None otherwise
        """

        if timestamp is None:
            timestamp = time.time()

        # Skip if no user bearing available
        if user_bearing is None:
            return None

        # Update bearing history
        self.bearing_history.append({
            'user_bearing': user_bearing,
            'expected_bearing': expected_bearing,
            'timestamp': timestamp
        })

        user_distance_error = 0.0
        if self.last_known_user_position_before_error is not None:
            user_distance_error = self.route_tracker.calculate_distance(
            self.last_known_user_position_before_error, current_user_position)

        # Limit history size
        if len(self.bearing_history) > self.max_history:
            self.bearing_history.pop(0)

        # Calculate bearing difference
        bearing_diff = self._calculate_bearing_difference(user_bearing, expected_bearing)
        is_wrong_direction = abs(bearing_diff) > self.bearing_threshold

        print(f"Bearing Analysis - User: {user_bearing:.1f}°, Expected: {expected_bearing:.1f}°, Diff: {bearing_diff:.1f}°, Wrong: {is_wrong_direction}, current_user_position: {current_user_position}, is_turn_signal_enabled: {self.is_turn_signal_enabled}, avg_bearing_error: {abs(self.avg_bearing_error)}")

        # Track wrong direction episodes
        if is_wrong_direction:
            if self.wrong_bearing_start_time is None:
                # Start tracking wrong direction
                self.wrong_bearing_start_time = timestamp
                self.wrong_bearing_samples = [bearing_diff]
                self.last_known_user_position_before_error = current_user_position
                print(f"Started tracking wrong direction at {timestamp}")
                print(f"Last known user position before error: {self.last_known_user_position_before_error}")
            else:
                # Continue tracking wrong direction
                self.wrong_bearing_samples.append(bearing_diff)

            # Check if error has persisted long enough
            error_duration = timestamp - self.wrong_bearing_start_time
            enough_samples = len(self.wrong_bearing_samples) >= self.min_samples

            print(f"Wrong direction duration: {error_duration:.1f}s, samples: {len(self.wrong_bearing_samples)}")
            #user_distance_error = self.route_tracker.calculate_distance(self.last_known_user_position_before_error, current_user_position)
            print(f"User distance_error_from_actual_point: {user_distance_error}")
            # Trigger recovery if duration exceeded and we have enough samples
            if ((error_duration >= self.duration_threshold and
                enough_samples and not self.is_in_recovery_mode)
                  or user_distance_error >= self.user_error_detection_threshold and not self.is_in_recovery_mode):
                print(f"Recovery mode triggered.")

                return self._trigger_recovery(bearing_diff, expected_bearing, user_bearing, expected_segment, current_user_position)

        else:
            # User is going correct direction
            if self.is_in_recovery_mode and self.is_turn_signal_enabled and abs(self.avg_bearing_error) > self.large_bearing_error: ## 180 degree deviations

                if self.re_alignment_start_time == None:
                  self.re_alignment_start_time = time.time()

                re_alignment_duration = time.time() - self.re_alignment_start_time
                print(f"Realighnment duration:{re_alignment_duration}")
                

                #user_distance_error = self.route_tracker.calculate_distance(self.last_known_user_position_before_error, current_user_position)
                print(f"User error distance error in recovery from opposite direction: {user_distance_error}")
                if re_alignment_duration >= self.duration_threshold or user_distance_error <= self.user_position_deviation_threshold:
                  # User has corrected their bearing - exit recovery mode
                  print(f"User has fully recovered to the last error point.")
                  recovery_complete = self._complete_recovery()
                  ###recovery_complete["hand_off_recovery"] = True

                  return recovery_complete #{"message": "RECOVERY_COMPLETE"}#recovery_complete

            elif self.is_in_recovery_mode and user_distance_error <= self.user_position_deviation_threshold:
        
        
              print(f"User error distance error in recovery: {user_distance_error}")
              recovery_complete = self._complete_recovery()
              #if recovery_complete:
              #recovery_complete["hand_off_recovery"] = True
             

              return recovery_complete #{"message": "RECOVERY_COMPLETE"}#recovery_complete


            else:
            #elif not self.is_in_recovery_mode:

              recovery_complete = self._complete_recovery()

              return recovery_complete #{"message": "RECOVERY_COMPLETE"}#recovery_complete
              #return recovery_complete = self._complete_recovery()

            # Reset wrong direction tracking
            self._reset_wrong_direction_tracking()
            




        return None

    def _calculate_bearing_difference(self, user_bearing, expected_bearing):
        """Calculate signed difference between bearings (-180 to +180)"""
        diff = (user_bearing - expected_bearing) % 360
        if diff > 180:
            diff -= 360
        return diff

    def circular_mean(self, bearing_diff_buffer):

      angles_rad = [math.radians(e) for e in bearing_diff_buffer]
      sin_sum = sum(math.sin(a) for a in angles_rad)
      cos_sum = sum(math.cos(a) for a in angles_rad)
      circular_mean = math.atan2(sin_sum, cos_sum)
      circular_mean_deg = math.degrees(circular_mean)

      return circular_mean_deg

    def _trigger_recovery(self, bearing_diff, expected_bearing, user_bearing, expected_segment, current_user_position):
      """Generate recovery instructions based on bearing analysis"""

      nearby_landmarks = []
      current_time = time.time()

      # Check cooldown to prevent spam
      if (self.last_recovery_time and
          current_time - self.last_recovery_time < self.recovery_cooldown):
          return None

      self.is_in_recovery_mode = True
      self.last_recovery_time = current_time

      # Direction for recovery
      current_user_bearing = self.route_tracker.calculate_bearing(current_user_position, expected_segment[0])
      turn_angle = self.route_tracker.calculate_turn_angle(current_user_bearing, expected_bearing)
      turn_direction = self.route_tracker.get_direction_name(turn_angle)
      

      # Analyze the average bearing error
      self.avg_bearing_error = self.circular_mean(self.wrong_bearing_samples) # robust average (-180,180)

      latest_error = self.wrong_bearing_samples[-1]               # latest signed diff

      print(f"RECOVERY TRIGGERED - Avg bearing error: {self.avg_bearing_error:.1f}°")

      # Get current segment from the route tracker
      if self.route_tracker and self.route_tracker.current_segment_idx < len(self.route_tracker.segments):
          current_segment = self.route_tracker.segments[self.route_tracker.current_segment_idx]
          previous_segment = self.route_tracker.segments[self.route_tracker.current_segment_idx - 1]
          start, end = current_segment
          previous_start, previous_end = previous_segment

          if self.route_tracker.use_landmarks_directions:
              
              #landmarks_instruction = self.route_tracker.get_landmark_direction(end, current_segment, user_bearing)
              #if self.route_tracker and hasattr(self.route_tracker, 'session'):
                    #session = self.route_tracker.session
                    
              current_landmarks_result = self.route_tracker.get_landmark_direction(start, current_segment)
              print(f"currentLand:{current_landmarks_result}")

              previous_landmarks_result = self.route_tracker.get_landmark_direction(previous_start, previous_segment)
              print(f"previuousLandmarks:{previous_landmarks_result}")

              if current_landmarks_result:
                  nearby_landmarks.append(current_landmarks_result)

              if previous_landmarks_result: 
                  nearby_landmarks.append(previous_landmarks_result)
              
              #if landmarks_instruction == None:
              if nearby_landmarks == None or len(nearby_landmarks) < 1:
                  # Determine recovery action based on bearing difference
                  if abs(self.avg_bearing_error) > self.large_bearing_error:
                      # User is going roughly opposite direction
                      recovery_type = "TURN_AROUND"
                      message = "Wrong direction! Turn around and continue straight."

                  elif abs(self.avg_bearing_error) > self.bearing_threshold:
                      # User took a significant wrong turn
                      #if latest_error > 0:
                          # User bearing is clockwise from expected (turned too far right)
                          ##else:
                          # User bearing is counter-clockwise from expected (turned too far left)
                          #turn_direction = "left"

                      recovery_type = "BACKTRACK_AND_TURN"
                      message = f"Wrong direction! Backtrack, then turn {turn_direction}."

                  else:
                      # This shouldn't happen, but handle gracefully
                      recovery_type = "MINOR_CORRECTION"
                      message = "Wrong direction! Adjust your direction to stay on path."

                  return {
                      "status": "error_recovery",
                      "error_type": recovery_type,
                      "message": message,
                      "bearing_error": self.avg_bearing_error,
                      "expected_bearing": expected_bearing,
                      "recovery_action": recovery_type,
                      "severity": self._get_severity(abs(self.avg_bearing_error))
                  }

              #if landmarks_instruction != None:
              if nearby_landmarks != None and len(nearby_landmarks) > 0:
                  #landmarks_instruct = landmarks_instruction['message']
                  landmark_names = [landmark['name'] for landmark in nearby_landmarks]
                  
                  # Extract landmark names and remove duplicates while preserving order
                  landmark_names = list(dict.fromkeys([
                  landmark['name'] for landmark in nearby_landmarks 
                  if landmark.get('name') and landmark['name'].strip()]))
                  print(f"landmark_names for_recovery: {landmark_names}")
        
                  # Create concise landmark info
                  if len(landmark_names) == 1:
                        base_message = f", You are not too far away from {landmark_names[0]}"
                  elif len(landmark_names) == 2:
                        base_message = f", You are not too far away from {landmark_names[0]} and {landmark_names[1]}"
                  else:
                        # For more than 2 landmarks, show first 2
                        base_message = f", You are not too far away from {landmark_names[0]} and {landmark_names[1]}"
                           
                  # Determine recovery action based on bearing difference
                  if abs(self.avg_bearing_error) > self.large_bearing_error:
                      recovery_type = "TURN_AROUND"
                      message = f"Wrong direction! Turn around and continue straight. {base_message}"

                  elif abs(self.avg_bearing_error) > self.bearing_threshold:
                      #if latest_error > 0:
                          #turn_direction = "right"
                      #else:
                          #turn_direction = "left"

                      recovery_type = "BACKTRACK_AND_TURN"
                      message = f"Wrong direction! Backtrack, then turn {turn_direction}. {base_message}"

                  else:
                      recovery_type = "MINOR_CORRECTION"
                      message = f"Wrong direction! Adjust your direction to stay on path. {base_message}"

                  return {
                      "status": "error_recovery",
                      "error_type": recovery_type,
                      "message": message,
                      "bearing_error": self.avg_bearing_error,
                      "expected_bearing": expected_bearing,
                      "recovery_action": recovery_type,
                      "severity": self._get_severity(abs(self.avg_bearing_error))
                  }

          # If landmarks not enabled, fall back to basic recovery
          else:
              # Basic recovery without landmarks
              if abs(self.avg_bearing_error) > self.large_bearing_error: #120:
                  recovery_type = "TURN_AROUND"
                  message = "Wrong direction! Turn around and continue straight."
              elif abs(self.avg_bearing_error) > self.bearing_threshold:
                  
                  
                  recovery_type = "BACKTRACK_AND_TURN"
                  message = f"Wrong direction! Backtrack, then turn {turn_direction}."
              else:
                  recovery_type = "MINOR_CORRECTION"
                  message = "Wrong direction! Adjust your direction to stay on path."

              return {
                  "status": "error_recovery",
                  "error_type": recovery_type,
                  "message": message,
                  "bearing_error": self.avg_bearing_error,
                  "expected_bearing": expected_bearing,
                  "recovery_action": recovery_type,
                  "severity": self._get_severity(abs(self.avg_bearing_error))
              }

      # Fallback if no route tracker available
      return {
          "status": "error_recovery",
          "error_type": "MINOR_CORRECTION",
          "message": "Wrong direction! Adjust your direction to stay on path.",
          "bearing_error": self.avg_bearing_error,
          "expected_bearing": expected_bearing,
          "recovery_action": "MINOR_CORRECTION",
          "severity": self._get_severity(abs(self.avg_bearing_error))
      }


    def _complete_recovery(self):
        """Handle completion of error recovery"""
        print("RECOVERY COMPLETED - User back on correct bearing")
        self.is_in_recovery_mode = False
        self._reset_wrong_direction_tracking()
        self.re_alignment_start_time = None
        self.is_turn_signal_enabled = False

        return {
            "status": "RECOVERY_COMPLETE", #"recovery_complete",
            "message": "Great! You're back on the right direction.",
            "recovery_action": "CONTINUE_NORMAL"
        }

    def _reset_wrong_direction_tracking(self):
        """Reset all wrong direction tracking variables"""
        self.wrong_bearing_start_time = None
        self.wrong_bearing_samples = []

    def _get_severity(self, bearing_error):
        """Determine severity level based on bearing error magnitude"""
        if bearing_error > 135:
            return "critical"  # Going opposite direction
        elif bearing_error > 90:
            return "high"      # Significant wrong turn
        elif bearing_error > 45:
            return "medium"    # Notable deviation
        else:
            return "low"       # Minor correction needed

    def get_recovery_status(self):
        """Get current recovery status for debugging"""
        return {
            "is_in_recovery": self.is_in_recovery_mode,
            "wrong_bearing_duration": (
                time.time() - self.wrong_bearing_start_time
                if self.wrong_bearing_start_time else 0
            ),
            "wrong_bearing_samples": len(self.wrong_bearing_samples),
            "last_recovery_time": self.last_recovery_time
        }









class PositionValidator:
    """
    Validates and corrects user positions to keep them within corridor boundaries
    """

    def __init__(self, corridor_width: float = 2.0):
        self.corridor_width = corridor_width


    def validate_and_correct_position(self,
                                    reported_position: List[float],
                                    route_waypoints: List[Tuple[float, float]],
                                    last_known_position: Optional[List[float]] = None,
                                    user_bearing: Optional[float] = None) -> Dict:
        """
        Main validation function that checks position validity and provides corrections
        """




        # Find closest point on route and calculate deviation
        route_info = self._find_closest_route_point(reported_position, route_waypoints)
        closest_point = route_info["closest_point"]
        distance_to_route = route_info["distance"]
        segment_index = route_info["segment_index"]

        # Determine if correction is needed
        correction_info = self._determine_correction(
            reported_position,
            closest_point,
            distance_to_route,
            user_bearing
        )

        # Apply appropriate correction
        if correction_info["correction_type"] == "OUTSIDE_CORRIDOR":
            corrected_position = self._snap_to_corridor_boundary(
                reported_position,
                closest_point
            )

            return {
                "is_valid": False,
                "corrected_position": corrected_position,
                "correction_type": "OUTSIDE_CORRIDOR",
                "error_distance": distance_to_route,
                "closest_route_point": closest_point,
                "segment_index": segment_index,
                "message": f"Position outside corridor ({distance_to_route:.1f}m from route), snapped to boundary",
                "correction_applied": True,
                "original_position": reported_position
            }


        else:
            # Position is valid, no correction needed
            return {
                "is_valid": True,
                "corrected_position": reported_position,
                "correction_type": "NONE",
                "error_distance": distance_to_route,
                "closest_route_point": closest_point,
                "segment_index": segment_index,
                "message": f"Position valid ({distance_to_route:.1f}m from route)",
                "correction_applied": False,
                "original_position": reported_position
            }


    def _find_closest_route_point(self, position: List[float], waypoints: List[Tuple[float, float]]) -> Dict:
        """Find the closest point on the route to the given position"""
        min_distance = float('inf')
        closest_point = None
        closest_segment_index = 0

        x, y = position

        for i in range(len(waypoints) - 1):
            segment_start = waypoints[i]
            segment_end = waypoints[i + 1]

            # Find closest point on this segment
            point_on_segment = self._closest_point_on_segment(position, segment_start, segment_end)
            dist = math.sqrt((x - point_on_segment[0])**2 + (y - point_on_segment[1])**2)

            if dist < min_distance:
                min_distance = dist
                closest_point = point_on_segment
                closest_segment_index = i

        return {
            "closest_point": closest_point,
            "distance": min_distance,
            "segment_index": closest_segment_index
        }

    def _closest_point_on_segment(self, point: List[float], segment_start: Tuple[float, float], segment_end: Tuple[float, float]) -> List[float]:
        """Find closest point on a line segment"""
        x, y = point
        x1, y1 = segment_start
        x2, y2 = segment_end

        dx = x2 - x1
        dy = y2 - y1

        if dx == 0 and dy == 0:
            return [x1, y1]

        # Calculate projection parameter
        t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)
        t = max(0, min(1, t))  # Clamp to segment

        return [x1 + t * dx, y1 + t * dy]

    def _determine_correction(self, position: List[float], closest_point: List[float], distance: float, bearing: Optional[float] = None) -> Dict:
        """Determine what type of correction is needed"""
        #half_corridor_width = self.corridor_width / 2.0
        quarter_corridor_width = self.corridor_width / 4.0

        if distance > quarter_corridor_width: #half_corridor_width:
            return {"correction_type": "OUTSIDE_CORRIDOR"}

        else:
            return {"correction_type": "NONE"}

    def _snap_to_corridor_boundary(self, position: List[float], closest_route_point: List[float]) -> List[float]:
        """Snap position to corridor boundary"""
        x, y = position
        cx, cy = closest_route_point

        # Calculate direction from route to position
        dx = x - cx
        dy = y - cy
        distance = math.sqrt(dx*dx + dy*dy)

        if distance == 0:
            return position

        # Normalize and scale to corridor boundary
        #half_width = self.corridor_width / 2.0

        # Normalize and scale to close to the centre line
        quarter_width = self.corridor_width / 4.0

        corrected_x = cx + (dx / distance) * quarter_width
        corrected_y = cy + (dy / distance) * quarter_width

        return [corrected_x, corrected_y]


class RouteTracker:
    def __init__(self, waypoints):
        """Initialize with a list of waypoints [(x1,y1), (x2,y2), ...]"""
        self.waypoints = waypoints
        self.segments = []
        self.segment_bearings = []
        self.stepSize = 0.65 #  meteres
        self.current_segment_idx = 0 # Index for the second segment
        self.last_position = waypoints[0]
        self.last_bearing = self.segment_bearings[0] if self.segment_bearings else 0
        self.waypoint_proximity_alert = False  # Flag to track if we've notified about approaching a waypoint
        self.activate_move_direction_checker = False
        self.movement_progress_threshold = 0.80
        self.bearing_difference_threshold =  25 #20 # In degrees
        self.max_route_deviation_threshold = 1 #2.0 #1.0 # in metres
        self.use_clock_directions = False  # Default to cardinal directions
        self.use_landmarks_directions = False # Default to cardinal or clock directions
        self.set_overshoot_flag = False
        self.overshoot_reversed_error_flag = False
        self.turn_angle_threshold = 25 # degrees
        self.turn_thresh = 0.80
        self.min_turn_warning_thresh_level1 = 0.01
        self.max_turn_warning_thresh_level1 = 0.5
        self.min_turn_warning_thresh_level2 = 0.2
        self.max_turn_warning_thresh_level2 = 0.5
        self.min_turn_warning_thresh = 0.10
        self.max_turn_warning_thresh = 0.5
        self.is_on_track_thresh = 0.2
        self.approaching_destination_thresh = 0.1
        self.at_destination_thresh = 0.5
        self.is_turn_signal_activated = False
        self.segment_advance_thresh =  0.7
        self.qr_code_status = False
        self.qr_id = None
        self.initiate_turn_qr = '810870' #'466126' #453394'
        self.confirm_turn_qr = '810800' #'466168'
        self.error_decision_wait_time = 10 # secs
        self.step_metre_scale = 1.25 # steps

        # Role assignment for visual anchors
        self.visual_anchor_roles = {
            self.initiate_turn_qr: None,  # Will be assigned "signal" or "confirm"
            self.confirm_turn_qr: None    # Will be assigned "signal" or "confirm"
        }

        # Navigation state for visual anchor-based turns
        self.visual_anchor_turn_state = "WAITING_FOR_SIGNAL"  # States: WAITING_FOR_SIGNAL, SIGNAL_RECEIVED, WAITING_FOR_CONFIRM, CONFIRMED
        self.anchor_roles_initialized = False

        self.last_qr_id = None




        self.position_validator = PositionValidator(corridor_width=3.0)  # 3 meter corridor
        self.last_validated_position = waypoints[0] if waypoints else None
        self.validation_stats = {
            "total_updates": 0,
            "corrections_applied": 0,
            "outside_corridor_count": 0,
            "gentle_corrections": 0
        }

        # Add bearing-based error recovery
        self.bearing_error_recovery = BearingErrorRecovery(
            bearing_threshold=45,      # 35 degrees tolerance before considering "wrong direction"
            duration_threshold=2,    # 3 seconds of wrong bearing before recovery
            min_samples=3,              # Need at least 3 bearing samples

        )

        # Set the reference to this RouteTracker instance
        self.bearing_error_recovery.set_route_tracker(self)



        # Precompute segments and their bearings and their segment lenght in steps 
        for i in range(len(waypoints) - 1):
            start, end = waypoints[i], waypoints[i+1]
            segment = (start, end)
            self.segments.append(segment)

            # Calculate bearing of segment (in degrees)
            bearing = self.calculate_bearing(start, end)
            self.segment_bearings.append(bearing)

            # Calculate the steps of segment
            #segment_length = self.calculate_distance(start, end)
            #step_counts = round(segment_length / self.step_size)
            #self.segment_step_counts.append(step_counts)



    def calculate_distance(self, p1, p2):
        """Calculate Euclidean distance between two points"""
        return math.sqrt((p2[0] - p1[0])**2 + (p2[1] - p1[1])**2)




    def calculate_bearing(self, p1, p2):
        #Calculate bearing from p1 to p2 in degrees (0 = East, 90 = North)
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        angle = math.degrees(math.atan2(dy, dx))
        # Convert to 0-360 range
        bearing = (90 - angle) % 360
        return bearing

    def get_closest_point_on_segment(self, point, segment):
        """Find closest point on segment to the given point"""
        p = point
        s1, s2 = segment

        # Vector from s1 to s2
        v = (s2[0] - s1[0], s2[1] - s1[1])

        # Vector from s1 to p
        w = (p[0] - s1[0], p[1] - s1[1])

        # Project w onto v
        c1 = w[0]*v[0] + w[1]*v[1]  # dot product
        if c1 <= 0:  # Point is before s1
            return s1, 0

        c2 = v[0]*v[0] + v[1]*v[1]  # Length of v squared
        if c2 <= c1:  # Point is after s2
            return s2, 1

        # Projection scalar
        b = c1 / c2

        # Projected point
        pb = (s1[0] + b*v[0], s1[1] + b*v[1])

        return pb, b  # Return point and progress (0-1)

    def calculate_turn_angle(self, current_bearing, target_bearing):
        """Calculate the angle to turn from current bearing to target bearing"""
        angle = (target_bearing - current_bearing) % 360
        # Convert to -180 to 180 range for more intuitive instructions
        if angle > 180:
            angle -= 360
        return angle

    def get_direction_name(self, angle, use_clock=False):
      if not self.use_clock_directions:
          """Convert angle to cardinal direction"""
          if -22.5 <= angle <= 22.5:
              return "straight ahead"
          elif 22.5 < angle <= 67.5:
              return "right"
          elif 67.5 < angle <= 112.5:
              return "right"#"sharp right"
          elif 112.5 < angle <= 157.5:
              return "right"
          elif 157.5 < angle <= 180 or -180 <= angle < -157.5:
              return "make a U-turn"
          elif -157.5 <= angle < -112.5:
              return "left"
          elif -112.5 <= angle < -67.5:
              return "left" #"sharp left"
          elif -67.5 <= angle < -22.5:
              return "left"
          return "unknown direction"
      else:
          # Clock position method
          # Convert angle to 0-360 format for easier clock calculations

          # Adjust the clock angle mapping to better represent the compass directions
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


    def is_direction_similar(self, bearing1, bearing2, angle_deviation_threshold = None):
        """Check if two bearings are similar (within threshold degrees)"""
        angle_diff = abs(self.calculate_turn_angle(bearing1, bearing2))
        print("currentbearing:", bearing1, "segment bearing:", bearing2)
        print("angle_diff:", angle_diff)
        if angle_deviation_threshold is not None:
          return angle_diff <= angle_deviation_threshold
        else:
          return angle_diff < self.turn_angle_threshold


    def get_landmark_direction(self, current_position, current_segment, user_bearing = None):

     
      # Extract start coordinates from current segment
      start, end = current_segment

      # Check for the closest points of interest: This is to use landmark information
      print("use_landmarks_directions:", self.use_landmarks_directions)

      if office_pois and self.current_segment_idx < len(self.segments) - 2 and self.use_landmarks_directions:
          closest_poi = None
          min_distance = float('inf')
          name_of_closest_poi = ""

          # Loop through office POIs to find the closest one
          for poi in office_pois:
              poi_coords = poi['geometry']['coordinates']
              poi_name = poi['properties']['name']

              # Calculate Euclidean distance between user and POI
              distance = self.calculate_distance(current_position, poi_coords)  # You'll need to pass this function or define it

              # Update closest POI if this one is closer
              if distance < min_distance:
                  min_distance = distance
                  closest_poi = poi
                  name_of_closest_poi = poi_name

          # If closest POI is within threshold, determine direction and return info
          print("Closest landmarks distance:", min_distance, "Closest_landmarks_name:", name_of_closest_poi)

          if min_distance <= 3 and closest_poi: #1.5
              poi_coords = closest_poi['geometry']['coordinates']
              poi_bearing = self.calculate_bearing(current_position, poi_coords)

              if user_bearing is None:
                   user_bearing = self.calculate_bearing(start, current_position)
          
             
              poi_angle = self.calculate_turn_angle(user_bearing, poi_bearing)
              poi_direction = self.get_direction_name(poi_angle)  # You'll need to pass this function

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



    def _is_user_at_destination(self, normalized_dist_from_seg_start, user_dist_to_destination):
        """Check if user has reached the final destination."""
        is_final_segment = self.current_segment_idx == len(self.segments) - 2
        return (is_final_segment and normalized_dist_from_seg_start >= self.at_destination_thresh) #or \
              #(user_dist_to_destination <= self.max_route_deviation_threshold and is_final_segment)

    def _is_approaching_destination(self, normalized_dist_from_seg_start):
        """Check if user is approaching the destination."""

        is_final_segment = self.current_segment_idx == len(self.segments) - 2

        return is_final_segment and normalized_dist_from_seg_start >= self.approaching_destination_thresh


    def _is_on_track(self, normalized_dist_from_seg_start):
        """Check if user is making good progress on current segment."""

        return (normalized_dist_from_seg_start < self.is_on_track_thresh and
                self.current_segment_idx < len(self.segments) - 2)

    def _should_advance_segment(self):
        """Check if we should consider advancing to the next segment."""

        return self.current_segment_idx < len(self.segments) - 2


    def get_validation_stats(self):
      """Get position validation statistics"""
      total = self.validation_stats["total_updates"]
      if total == 0:
          return "No position updates yet"

      correction_rate = (self.validation_stats["corrections_applied"] / total) * 100
      outside_rate = (self.validation_stats["outside_corridor_count"] / total) * 100

      return {
          "total_updates": total,
          "correction_rate": f"{correction_rate:.1f}%",
          "outside_corridor_rate": f"{outside_rate:.1f}%",
          "gentle_corrections": self.validation_stats["gentle_corrections"]
      }


    def update_position(self, current_position, current_bearing=None, current_magnetic_strength=None, reported_qr_status=False, reported_qr_id=None):
        """Enhanced update_position with validation and correction"""

        self.validation_stats["total_updates"] += 1
        self.current_magnetic_strength = current_magnetic_strength

        self.qr_code_status = reported_qr_status
        self.last_qr_id = self.qr_id

        if self.qr_code_status:
          self.qr_id = reported_qr_id

        # 1. Validate and correct position
        validation_result = self.position_validator.validate_and_correct_position(
            reported_position=current_position,
            route_waypoints=self.waypoints,
            last_known_position=self.last_validated_position,
            user_bearing=current_bearing
        )

        # 2. Update statistics
        if validation_result["correction_applied"]:
            self.validation_stats["corrections_applied"] += 1

            if validation_result["correction_type"] == "OUTSIDE_CORRIDOR":
                self.validation_stats["outside_corridor_count"] += 1
            elif validation_result["correction_type"] == "GENTLE_SNAP":
                self.validation_stats["gentle_corrections"] += 1

        # 3. Use corrected position for navigation logic
        corrected_position = validation_result["corrected_position"]
        self.last_validated_position = corrected_position

        # 4. Log significant corrections
        #if not validation_result["is_valid"] or validation_result["error_distance"] > 1.5:
        print(f"Position validation: {validation_result['message']}")
        print(f"  Original: ({current_position[0]:.2f}, {current_position[1]:.2f})")
        print(f"  Corrected: ({corrected_position[0]:.2f}, {corrected_position[1]:.2f})")


         # Add bearing-based error recovery check
        if (current_bearing is not None and
            self.current_segment_idx < len(self.segments)):

            # Get expected bearing for current segment
            if self.is_turn_signal_activated:
              expected_bearing = self.segment_bearings[self.current_segment_idx + 1]
              expected_segment = self.segments[self.current_segment_idx + 1]
              self.bearing_error_recovery.duration_threshold = self.error_decision_wait_time # secs Allow user enough time at corner
              self.bearing_error_recovery.is_turn_signal_enabled = True
            else:
              expected_bearing = self.segment_bearings[self.current_segment_idx]
              expected_segment = self.segments[self.current_segment_idx]




            # Check for bearing-based navigation errors
            recovery_result = self.bearing_error_recovery.update_bearing_tracking(
                user_bearing=current_bearing,
                expected_bearing=expected_bearing,
                current_user_position=current_position,
                expected_segment = expected_segment



            )
            print(f"rec:{recovery_result}")

            # If recovery instruction needed, return it immediately
            if recovery_result and recovery_result['status'] != "RECOVERY_COMPLETE":
                print(f"BEARING ERROR RECOVERY: {recovery_result['message']}")
                return recovery_result


        # 5. Continue with your existing navigation logic using corrected position
        if recovery_result and recovery_result['status'] == "RECOVERY_COMPLETE":

          navigation_n_recovery_result = self.handle_error_recovery_with_guidance_information(corrected_position, current_bearing)
          print(f"nav:{navigation_n_recovery_result}")
          # 6. Add validation info to the response
          if navigation_n_recovery_result:

            return navigation_n_recovery_result


    def _handle_destination_reached(self, dest_segment_bearing, last_segment_bearing, user_dist_to_destination):
        """Handle when user reaches the final destination."""
        step_count = round(user_dist_to_destination / self.stepSize)
        turn_to_destination = self.calculate_turn_angle(dest_segment_bearing, last_segment_bearing)
        destination_direction = self.get_direction_name(turn_to_destination)

        #print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id:, {self.current_segment_idx}, current_user_position: {current_user_position}, signal: destination reached")

        if destination_direction == "straight ahead":
            return {
            "status": "destination_reached",
            "message": f"Arrived! Destination in front of you!",
            "deviation_type": "COMPLETED"
        }
        
        return {
            "status": "destination_reached",
            "message": f"Arrived! Destination on your {destination_direction}!",
            "deviation_type": "COMPLETED"
        }



    def handle_error_recovery_with_guidance_information(self, current_user_position, current_bearing=None):
      """
      Handle navigation guidance based on user's current position relative to the route.

      Args:
          current_user_position: Current GPS/position coordinates of the user
          current_bearing: Optional current bearing of the user

      Returns:
          dict: Navigation status and guidance message, or None if no guidance needed
      """

      # Validate we have segments to work with
      if not self.segments or len(self.segments) < 1:
          return None

      # Get route information
      last_segment = self.segments[-1]  # Last segment
      last_segment_bearing = self.segment_bearings[-1]  # Last segment bearing

      destination_segment = self.segments[-2]
      dest_segment_bearing = self.segment_bearings[-2] # Destination segment bearing
      dest_segment_start, dest_segment_end = destination_segment # Segment nodes for destination

      current_segment = self.segments[self.current_segment_idx]
      current_segment_bearing = self.segment_bearings[self.current_segment_idx]
      current_segment_start, current_segment_end = current_segment # Segment nodes for last segment


      snapped_user_position, normalized_dist_from_seg_start = self.get_closest_point_on_segment(current_user_position, current_segment)

      current_user_position = snapped_user_position ### More accurate than the reported position

      #current_user_bearing = self.calculate_bearing(current_segment_start, current_user_position)
      current_user_bearing = current_bearing



      last_segment_start, last_segment_end = last_segment # Segment nodes for last segment



      # Calculate key distances and positions
      user_dist_to_destination = self.calculate_distance(current_user_position, dest_segment_end)



      user_dist_to_seg_end = self.calculate_distance(current_user_position, current_segment_end)

      deviation_distance = self.calculate_distance(current_user_position, snapped_user_position)

      # Calculate bearings and angles



      # Check if user is at the final destination
      if self._is_user_at_destination(normalized_dist_from_seg_start, user_dist_to_destination):
          return self._handle_destination_reached(dest_segment_bearing, last_segment_bearing, user_dist_to_destination)

      # Check if we're approaching the destination
      if self._is_approaching_destination(normalized_dist_from_seg_start):


          print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id:, {self.current_segment_idx}, current_user_position: {current_user_position}, signal: approaching destination, current_magnetic_strength: {self.current_magnetic_strength}")

          return {
              "status": "Approaching destination",
              "message": "Approaching destination!"

          }


      # Provide general progress feedback
      if (self._is_on_track(normalized_dist_from_seg_start) and self.qr_code_status==False):

          print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id:, {self.current_segment_idx}, current_user_position: {current_user_position}, signal: on track, current_magnetic_strength: {self.current_magnetic_strength}")


          return {
              "status": "On track information",
              "message": "You are on track!"

          }


      # Handle segment transitions and turns
      if self._should_advance_segment():
          next_segment_bearing = self.segment_bearings[self.current_segment_idx + 1]

          #following_segment_bearing = self.segment_bearings[self.current_segment_idx + 1] ## Following segment is the following segment after next segment

          turn_result = self._handle_segment_transition(
              normalized_dist_from_seg_start, user_dist_to_seg_end, current_segment_bearing, next_segment_bearing, current_user_position
              , current_user_bearing)



          if turn_result:
              return turn_result



      return None


    def initialize_visual_anchor_roles(self, first_qr_id):
        """Initialize roles based on the first QR code encountered"""
        if self.anchor_roles_initialized:
            return

        if first_qr_id == self.initiate_turn_qr:
            self.visual_anchor_roles[self.initiate_turn_qr] = "signal"
            self.visual_anchor_roles[self.confirm_turn_qr] = "confirm"
        elif first_qr_id == self.confirm_turn_qr:
            self.visual_anchor_roles[self.confirm_turn_qr] = "signal"
            self.visual_anchor_roles[self.initiate_turn_qr] = "confirm"

        self.anchor_roles_initialized = True
        print(f"Visual anchor roles initialized: {self.visual_anchor_roles}")



    def handle_visual_anchor_detection(self, qr_id, is_significant_turn, next_segment_bearing):
        """Handle QR code detection based on assigned visual anchor roles"""
        if not self.anchor_roles_initialized:
            self.initialize_visual_anchor_roles(qr_id)

        # Only process if this is one of our visual anchor QR codes
        if qr_id not in self.visual_anchor_roles:
            return None

        role = self.visual_anchor_roles[qr_id]

        if role == "signal":
            return self._handle_signal_anchor(qr_id, is_significant_turn, next_segment_bearing)
        elif role == "confirm":
            return self._handle_confirm_anchor(qr_id)

        return None

    def _handle_signal_anchor(self, qr_id, is_significant_turn, next_segment_bearing):
        """Handle when a signal visual anchor is detected"""
        if (self.visual_anchor_turn_state == "WAITING_FOR_SIGNAL" and
            is_significant_turn and
            next_segment_bearing != self.segment_bearings[-1]):

            self.visual_anchor_turn_state = "SIGNAL_RECEIVED"
            print(f"Signal visual anchor detected: {qr_id}, turn signal activated")
            return "TURN_SIGNAL"

        return None

    def _handle_confirm_anchor(self, qr_id):
        """Handle when a confirm visual anchor is detected"""
        if self.visual_anchor_turn_state == "SIGNAL_RECEIVED":
            self.visual_anchor_turn_state = "CONFIRMED"
            print(f"Confirm visual anchor detected: {qr_id}, turn confirmed")
            return "TURN_CONFIRMED"

        return None

    def reset_visual_anchor_turn_state(self):
        """Reset the visual anchor turn state for the next turn sequence"""
        self.visual_anchor_turn_state = "WAITING_FOR_SIGNAL"


    def _handle_segment_transition(self, normalized_dist_from_seg_start, user_dist_to_segment_end,
                                 current_segment_bearing, next_segment_bearing, current_user_position,
                                 current_user_bearing):
        """
        Enhanced segment transition handling with visual anchor role assignment
        """
        # Calculate turn information
        turn_angle = self.calculate_turn_angle(current_segment_bearing, next_segment_bearing)
        is_significant_turn = abs(turn_angle) > self.turn_angle_threshold
        turn_direction = self.get_direction_name(turn_angle)

        next_segment_start, next_segment_end = self.segments[self.current_segment_idx+1]

        # Handle turn confirmation (when turn signal is already activated)
        if self.is_turn_signal_activated:
            turn_confirmed = False

            # Check direction-based confirmation
            if self.is_direction_similar(current_user_bearing, next_segment_bearing):
                turn_confirmed = True
                print("Turn confirmed by direction alignment")

            # Check visual anchor-based confirmation
            elif self.qr_code_status:
                anchor_result = self.handle_visual_anchor_detection(self.qr_id, is_significant_turn, next_segment_bearing)
                if anchor_result == "TURN_CONFIRMED":
                    turn_confirmed = True
                    print("Turn confirmed by confirm visual anchor")

            # Execute turn if confirmed
            if turn_confirmed:
                print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id: {self.current_segment_idx}, signal: turn_executed, current_user_position:{current_user_position}, turn_angle:{is_significant_turn}, current_magnetic_strength: {self.current_magnetic_strength}, current_user_bearing:{current_user_bearing}, qr_code_status:{self.qr_code_status}, turn_qr_id:{self.qr_id}")


                self.current_segment_idx += 1
                self.is_turn_signal_activated = False
                self.reset_visual_anchor_turn_state()  # Reset for next turn sequence

                start_pos, end_pos = self.segments[self.current_segment_idx]

                return {
                    "status": "segment_change",
                    "message": "Turn completed!",
                    "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]],
                    "segment_info": {
                        "segment_index": self.current_segment_idx,
                        "is_significant_turn": True
                    }
                }

        # Handle turn signal activation
        should_turn_now = False

        # Original distance-based condition
        if (is_significant_turn and
            normalized_dist_from_seg_start >= self.turn_thresh and
             self.current_segment_idx < len(self.segments) - 2): #next_segment_bearing != self.segment_bearings[-1]): ## Maybe later, the condition should be better checked against segments and not segment bearings
            should_turn_now = True
            print("Turn signal activated by distance threshold")

        # Visual anchor-based turn signal condition with role assignment
        elif (is_significant_turn and
               self.current_segment_idx < len(self.segments) - 2 and #next_segment_bearing != self.segment_bearings[-1] and
              self.qr_code_status):

            anchor_result = self.handle_visual_anchor_detection(self.qr_id, is_significant_turn, next_segment_bearing)
            if anchor_result == "TURN_SIGNAL":
                should_turn_now = True
                print("Turn signal activated by signal visual anchor")

        elif (is_significant_turn == False
              and  self.current_segment_idx < len(self.segments) - 2 #next_segment_bearing != self.segment_bearings[-1]
              and self.current_segment_idx + 2 < len(self.segment_bearings) # Short circuit
              and self.segment_bearings[self.current_segment_idx+2] != self.segment_bearings[-2]
              and self.qr_code_status
              and self.last_qr_id != self.qr_id
              and self.is_turn_signal_activated == False):# Even if is_significant_turn is not true. Seeing QR code means it is at the turn. Go with visual

              next_next_segment_bearing = self.segment_bearings[self.current_segment_idx+2]
              next_turn_angle = self.calculate_turn_angle(next_segment_bearing, next_next_segment_bearing)
              is_significant_turn_next = abs(next_turn_angle) > self.turn_angle_threshold

              if is_significant_turn_next:
                should_turn_now = True
                print("Turn signal activated by signal visual anchor before the actual segment")
                self.current_segment_idx += 1
                turn_direction = self.get_direction_name(next_turn_angle)


        if should_turn_now and self.is_turn_signal_activated == False: # Avoid repeat of turn instruction by another logic if already set by one of the triggers
            print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id: {self.current_segment_idx}, signal: turn_signal, current_user_position:{current_user_position}, turn_angle:{is_significant_turn}, current_magnetic_strength: {self.current_magnetic_strength}, qr_code_status:{self.qr_code_status},  qr_id:{self.qr_id}")
            self.is_turn_signal_activated = True


            start_pos, end_pos = self.segments[self.current_segment_idx]

            if self.use_landmarks_directions:
                landmarks_instruction = self.get_landmark_direction(current_user_position, self.segments[self.current_segment_idx])

                if landmarks_instruction != None and landmarks_instruction['name']:

                    landmarks_name = landmarks_instruction['name']

                    return {
                        "status": "no_segment_ending",
                        "message": f"Turn {turn_direction} at {landmarks_name}!",
                        "new_map_position": [end_pos[0], end_pos[1], current_segment_bearing],
                        "segment_info": {
                            "segment_index": self.current_segment_idx,
                            "is_significant_turn": True
                        }
                    }

                else:
                    return {
                    "status": "no_segment_ending",
                    "message": f"Turn {turn_direction}!",
                    "new_map_position": [end_pos[0], end_pos[1], current_segment_bearing],
                    "segment_info": {
                        "segment_index": self.current_segment_idx,
                        "is_significant_turn": True
                    }
                }

            elif self.use_landmarks_directions == False:

                    
                return {
                "status": "no_segment_ending",
                "message": f"Turn {turn_direction}!",
                "new_map_position": [end_pos[0], end_pos[1], current_segment_bearing],
                "segment_info": {
                    "segment_index": self.current_segment_idx,
                    "is_significant_turn": True
                }
            }


        # Handle general segment advancement (no significant turn)
        should_advance = (
            normalized_dist_from_seg_start >= self.segment_advance_thresh and
            self.current_segment_idx < len(self.segments) - 2 and
            not is_significant_turn
        )

        if should_advance:
            print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id:, {self.current_segment_idx}, current_user_position: {current_user_position}, signal: segment_change, turn_angle:{is_significant_turn}, current_magnetic_strength: {self.current_magnetic_strength}")
            self.current_segment_idx += 1
            self.reset_visual_anchor_turn_state()  # Reset for next turn sequence

            start_pos, end_pos = self.segments[self.current_segment_idx]

            # Check if use landmark direction is enabled

            if self.use_landmarks_directions:
              landmarks_instruction = self.get_landmark_direction(current_user_position, self.segments[self.current_segment_idx-1])

              if landmarks_instruction == None:

                return {
                    "status": "segment_change",
                    "message": "Keep moving!",
                    "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]], #current_segment_bearing],
                    "segment_info": {
                        "segment_index": self.current_segment_idx,
                        "is_significant_turn": False
                    }
                }

              if landmarks_instruction != None:

                landmarks_instruct = landmarks_instruction['message']

                if "make a U turn" in landmarks_instruct or "make a U-turn" in landmarks_instruct:
                    landmarks_instruct = landmarks_instruct.replace("make a U turn", "back").replace("make a U-turn", "back")

                base_message = "Keep moving!"

                message = f"{landmarks_instruct} {base_message}"

                return {
                      "status": "segment_change",
                      "message": message,
                      "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]], #current_segment_bearing],
                      "segment_info": {
                          "segment_index": self.current_segment_idx,
                          "is_significant_turn": False
                      }
                  }
            if self.use_landmarks_directions == False:

              return {
                      "status": "segment_change",
                      "message": "Keep moving!",
                      "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]], #current_segment_bearing],
                      "segment_info": {
                          "segment_index": self.current_segment_idx,
                          "is_significant_turn": False
                      }
                  }


        print(f"normalized_dist_from_seg_start: {normalized_dist_from_seg_start:.2f}, segment_id:, {self.current_segment_idx}, current_user_position: {current_user_position}, signal: on track, current_magnetic_strength: {self.current_magnetic_strength}")

        return {
            "status": "On track information",
            "message": "You are on track!"
        }

    def get_visual_anchor_role_status(self):
        """Get current visual anchor role assignment status for debugging"""
        return {
            "anchor_roles_initialized": self.anchor_roles_initialized,
            "visual_anchor_roles": self.visual_anchor_roles,
            "current_state": self.visual_anchor_turn_state
        }



class NavigationSession:
    def __init__(self, source_name, destination_name, use_clock_directions=False, use_landmarks_directions = False ):
        # Get source and destination coordinates from names
        self.source_name = source_name
        self.destination_name = destination_name

        self.source = get_point_from_name(source_name)
        self.destination = get_point_from_name(destination_name)
        self.use_clock_directions = use_clock_directions
        self.use_landmarks_directions = use_landmarks_directions


        if not self.source or not self.destination:
            raise ValueError("Invalid source or destination name")



        self.path = [] # List of path nodes [(x1, y1), (x2, y2), ...]

        self.current_position = self.source
        self.generate_path()


        # Initialize the RouteTracker with our path
        self.route_tracker = RouteTracker(self.path)
        self.route_tracker.session = self
        
    
        # Pass the direction preference to the route tracker
        self.route_tracker.use_clock_directions = self.use_clock_directions

        self.route_tracker.use_landmarks_directions = self.use_landmarks_directions

    def find_nearest_graph_node(self, point):
        """Find the nearest node in the navigation graph to the given point"""
        min_dist = float('inf')
        closest_node = None

        for node, attrs in navigation_graph.nodes(data=True):
            node_coords = attrs['coordinates']
            dist = np.sqrt((point[0] - node_coords[0])**2 + (point[1] - node_coords[1])**2)

            if dist < min_dist:
                min_dist = dist
                closest_node = node

        return closest_node, min_dist

    def generate_path(self):
        """
        Generate a path from source to destination using the navigation graph.
        """
        # Find nearest nodes in the graph to our source and destination
        source_node, _ = self.find_nearest_graph_node(self.source)
        dest_node, _ = self.find_nearest_graph_node(self.destination)

        if source_node is None or dest_node is None:
            # Fallback to direct path if no graph nodes are close
            self.path = [self.source, self.destination]
            return

        try:
            # Use Dijkstra's algorithm to find shortest path
            path_nodes = nx.shortest_path(navigation_graph, source=source_node,
                                        target=dest_node, weight='weight')

            # Convert node IDs to coordinates
            self.path = [navigation_graph.nodes[node]['coordinates'] for node in path_nodes]

            # Add actual source and destination if they're different from the nearest nodes
            if distance.euclidean(self.source, self.path[0]) > 0.001:
                self.path.insert(0, self.source)

            if distance.euclidean(self.destination, self.path[-1]) > 0.001:
                self.path.append(self.destination)

        except nx.NetworkXNoPath:
            # No path found in graph, use direct path
            self.path = [self.source, self.destination]

    def detect_deviation(self, reported_position, reported_bearing=None, reported_magnetic_strength=None, reported_qr_status=False, reported_qr_id=None):
        """
        Uses the RouteTracker to detect deviations and get recovery instructions
        """
        # Update user position in the RouteTracker
        result = self.route_tracker.update_position(reported_position, reported_bearing, reported_magnetic_strength, reported_qr_status, reported_qr_id)

        # Update current position
        #self.current_position = reported_position
        if result is not None:
          return result
        else:
          return None

def get_poi_name_from_coordinates(coordinates):
    """Find the name of a POI based on coordinates"""
    for node, attrs in navigation_graph.nodes(data=True):
        node_coords = attrs['coordinates']
        if distance.euclidean(coordinates, node_coords) < 0.1:  # Small threshold
            return attrs['name']
    return "a waypoint"


def generate_conversation_mode_response(session, door_qr_code):
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
            segment_distance = route_tracker.calculate_distance(path_coords[i], path_coords[i + 1])
            total_distance += segment_distance

        # Estimate total duration (assuming average walking speed of 1.4 m/s)
        walking_speed = 1.4  # meters per second
        total_duration = total_distance / walking_speed

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


def generate_overall_direction_summary(session, door_qr_code, segments, segment_bearings):
    """Generate a high-level summary of the entire route with merged straight segments"""
    route_tracker = session.route_tracker
    step_metre_scale = route_tracker.step_metre_scale

    if len(segment_bearings) < 2:
        return f"Continue straight to {session.destination_name}."

    actions = []

    # Handle initial door exit and first turn
    initial_bearing = segment_bearings[0]
    next_bearing = segment_bearings[1]
    turn_angle = route_tracker.calculate_turn_angle(initial_bearing, next_bearing)
    turn_direction = route_tracker.get_direction_name(turn_angle)
   
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
        turn_angle = route_tracker.calculate_turn_angle(current_bearing, next_bearing)

        # add segment length to running total
        segment_distance = route_tracker.calculate_distance(segments[i][0], segments[i][1])
        accumulated_distance += segment_distance

        if abs(turn_angle) > route_tracker.turn_angle_threshold:
            # flush the accumulated straight distance before the turn
            actions[-1] += f" and continue for {accumulated_distance * step_metre_scale:.0f} steps"
            accumulated_distance = 0.0
            # add the new turn instruction
            turn_dir = route_tracker.get_direction_name(turn_angle)
            actions.append(f"Then turn {turn_dir}")

    # handle last straight stretch before destination
    if accumulated_distance > 0:
        actions[-1] += f" and continue for {accumulated_distance * step_metre_scale:.0f} steps"

    # Final destination
    destination_position = determine_destination_position(session, segments, segment_bearings)
    if destination_position == "straight ahead":
        destination_position = "front"

    actions.append(f"Destination will be {session.destination_name} at the {destination_position}")

    return ". ".join(actions) + "."


def determine_destination_position(session, segments, segment_bearings):
    """Determine if destination is on the left or right of the final approach"""
    if len(segments) < 2:
        return "ahead"

    route_tracker = session.route_tracker

  

    # Calculate the bearing of the final approach segment
    final_approach_bearing = segment_bearings[-1]
    pre_final_approach_bearing = segment_bearings[-2]

   
    # Calculate the angle difference to determine left/right
    angle_to_destination = route_tracker.calculate_turn_angle(pre_final_approach_bearing, final_approach_bearing)
    destination_direction = route_tracker.get_direction_name(angle_to_destination)
    
    return destination_direction


def generate_detailed_trips(session, segments, segment_bearings, path_coords):
    """Generate detailed step-by-step trip information"""
    route_tracker = session.route_tracker
    trips = []
    step_metre_scale = route_tracker.step_metre_scale #steps
    for i in range(len(segments)):
        start_point, end_point = segments[i]
        segment_distance = route_tracker.calculate_distance(start_point, end_point)

        # Generate action description
        if i == 0:
            # First segment - exit room
            action = "Continue straight ahead" #"Exit room" # and begin walking"
        else:
            # Calculate turn from previous segment
            prev_bearing = segment_bearings[i - 1]
            current_bearing = segment_bearings[i]
            turn_angle = route_tracker.calculate_turn_angle(prev_bearing, current_bearing)



            if abs(turn_angle) > route_tracker.turn_angle_threshold:
                turn_direction = route_tracker.get_direction_name(turn_angle)
                action = f"Turn {turn_direction} and Continue"
            else:
                action = "Continue"

            # Add distance information
            action += f" for about {segment_distance * step_metre_scale:.0f} steps"

        # Find nearby landmarks
        nearby_landmarks = find_nearby_landmarks(session, start_point, end_point)

        

        # Determine path type
        path_type = "hallway"  # Default assumption for indoor navigation

        # Additional info for final segment
        additional_info = ""
        if i == len(segments) - 1:
            turn_angle = route_tracker.calculate_turn_angle(segment_bearings[-2], segment_bearings[-1])
            turn_direction = route_tracker.get_direction_name(turn_angle)

            if turn_direction == "straight ahead":
                additional_info = f"destination {session.destination_name} in the front." 

            else:

                additional_info = f"destination {session.destination_name} on the {turn_direction}." #will be reached"

            trip_info = {   #"nearby_landmarks": nearby_landmarks,  # Now contains objects with name and coordinates, #"distance": f"{segment_distance:.0f} metres",
                "destination_info": additional_info,
                "path": path_type,
                "additional_info": additional_info
            }
        else:

          trip_info = {
                "actions": action,
                "distance": f"{segment_distance * step_metre_scale:.0f} steps",
                "nearby_landmarks": nearby_landmarks,  # Now contains objects with name and coordinates
                "path": path_type,
                "additional_info": additional_info
            }



        trips.append(trip_info)

    return trips



def find_nearby_landmarks(session, start_point, end_point):
    """Find office POIs near the given segment and label them left/right"""

    route_tracker = session.route_tracker
    landmarks = []

    if office_pois:
        mid_point = [
            (start_point[0] + end_point[0]) / 2,
            (start_point[1] + end_point[1]) / 2
        ]

        # Bearing of the walking segment
        segment_bearing = route_tracker.calculate_bearing(start_point, end_point)

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

            if min_dist <= 3:  # within 1.5 m threshold
                if closest_point_name == "start":
                    ref_point = start_point
                elif closest_point_name == "end":
                    ref_point = end_point
                else:
                    ref_point = mid_point

                # Bearing from ref_point to POI
                poi_bearing = route_tracker.calculate_bearing(ref_point, poi_coords)

                # Relative angle between walking direction and POI
                turn_angle = route_tracker.calculate_turn_angle(segment_bearing, poi_bearing)
                turn_direction = route_tracker.get_direction_name(turn_angle)

                if turn_direction == "make a U-turn":
                    turn_direction = "back"

                landmarks.append({
                    "name": poi_name,
                    "coordinates": poi_coords,
                    "direction": turn_direction
                })

    return landmarks[:4]  # limit to 4 landmarks




# Modified wayfinder endpoint to handle conversation mode

@app.post("/wayfinder", response_model=NavigationResponse)
async def wayfinder(
    request: Union[InitializeRequest, UpdateRequest],
    session_id: Optional[str] = Header(default="default", alias="Session-ID")
):
    """Main wayfinding endpoint"""
    try:
        if isinstance(request, InitializeRequest) or request.action == 'initialize':
            # Handle initialization
            if isinstance(request, UpdateRequest):
                # Convert UpdateRequest to InitializeRequest-like data
                raise HTTPException(status_code=400, detail="Invalid request format for initialization")
            
            init_req = request
            
            try:
                # Initialize a new navigation session
                source_name = init_req.source.strip()
                destination_name = init_req.destination.strip()
                use_clock_directions = init_req.useClockDirections
                use_landmarks_directions = init_req.useLandmarks
                door_qr_code = init_req.qrId
                conversation_mode = init_req.conversationMode

                print(f"Initializing: {source_name} -> {destination_name}")
                print(f"QR Code: {door_qr_code}, Conversation: {conversation_mode}")
                print(f"Source '{source_name}' in POI mapping: {source_name in poi_mapping}")
                print(f"Destination '{destination_name}' in POI mapping: {destination_name in poi_mapping}")

                #session = NavigationSession(source_name, destination_name, use_clock_directions, use_landmarks_directions)
                #sessions[session_id] = session
                try:
                    session = NavigationSession(source_name, destination_name, use_clock_directions, use_landmarks_directions)
                    sessions[session_id] = session
                except Exception as e:
                    print(f"Error creating NavigationSession: {e}")
                    print(f"Source: {source_name}, Destination: {destination_name}")
                    raise e

                # Handle conversation mode
                if conversation_mode:
                    conversation_response = generate_conversation_mode_response(session, door_qr_code)
                    if conversation_response:
                        return NavigationResponse(
                            status='success',
                            conversation_mode=True,
                            message='Route calculated successfully in conversation mode',
                            instructions='Route calculated successfully in conversation mode',
                            conversation_data=conversation_response
                        )
                    else:
                        raise HTTPException(status_code=500, detail="Failed to generate conversation mode response")

                # Regular navigation mode
                path_coords = session.path
                print(f"path_coords: {path_coords}")
                #start_node = path_coords[0]
                #end_node = path_coords[1] if len(path_coords) > 1 else path_coords[0]

                path_bearings = session.route_tracker.segment_bearings
                print(f"path_bearings: {path_bearings}")

                first_segment_bearing = path_bearings[0]

                """
                Because we want to investigate the recovery functionality, we woul not want to give initial recommendation
                to the users, so we we comment out the section for part below and we equally set the current_segment_idx  to 0.
                """

                """

                if len(path_coords) > 3:
                   
                    subsequent_segment_bearing = path_bearings[1]

                    turn_angle = session.route_tracker.calculate_turn_angle(first_segment_bearing, subsequent_segment_bearing)
                    turn_direction = session.route_tracker.get_direction_name(turn_angle)

                    if turn_direction == "straight ahead":
                        instructions = f"Press start navigation button!"

                    else:

                        instructions = f"Turn {turn_direction}. Afterwards, press start navigation button!"

                elif len(path_coords) <= 3:

                    instructions = f"Press start navigation button!"
                """

                    # We are not using this for now.
                    #if door_qr_code == "492159":
                        #instructions = f"Exit the room and turn {turn_direction}. Afterwards, press start navigation button!"
                    #elif door_qr_code == "500751":
                        #instructions = f"Turn {turn_direction}. Afterwards, press start navigation button!"
                    #else:
                        #instructions = f"Exit the room and turn {turn_direction}. Afterwards, press reset button!"
                 
                               #instructions = f"Turn {turn_direction}. Afterwards, press start navigation button!"

                # Added this to test the recovery part:
                if len(path_coords) >= 3: # No explicit initial heading recommendation.
                    instructions = f"Press start navigation button!"


                return NavigationResponse(
                    status='success',
                    navigationStarted=True,
                    instructions=instructions,
                    message=instructions,
                    pathCoordinates=path_coords,
                    pathBearings=path_bearings,
                    calibration=CalibrationData(
                        mapStartX=path_coords[0][0],
                        mapStartY=path_coords[0][1],
                        initialBearing=first_segment_bearing
                    )
                )

            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        elif isinstance(request, UpdateRequest) or request.action == 'update':
            # Handle position update
            if session_id not in sessions:
                raise HTTPException(status_code=404, detail="No active navigation session found")

            update_req = request if isinstance(request, UpdateRequest) else UpdateRequest(**request.dict())

            try:
                session = sessions[session_id]
                reported_position = [update_req.currentX, update_req.currentY]
                reported_bearing = update_req.currentBearing
                reported_magnetic_strength = update_req.magneticFieldStrength
                reported_qr_status = update_req.qrDetected
                reported_qr_id = update_req.qrCodeId

                detailed_result = session.detect_deviation(
                    reported_position, reported_bearing, reported_magnetic_strength, 
                    reported_qr_status, reported_qr_id
                )

                print(f"QR_status: {reported_qr_status}, QR_Id: {reported_qr_id}")

                if detailed_result is not None:
                    # Add validation stats if available
                    if hasattr(session.route_tracker, 'get_validation_stats'):
                        detailed_result['validation_stats'] = session.route_tracker.get_validation_stats()

                    detailed_result['segmentInfo'] = {
                        'segmentIndex': session.route_tracker.current_segment_idx
                    }
                    

                    return NavigationResponse(**detailed_result)
                else:
                    return NavigationResponse(
                        status='Error',
                        message='No value return'
                    )

            except Exception as e:
                raise HTTPException(status_code=500, detail=str(e))

        else:
            raise HTTPException(status_code=400, detail="Invalid action")

    except Exception as e:
        print(f"Wayfinder error: {e}")
        raise HTTPException(status_code=500, detail=str(e))



# Startup event
@app.on_event("startup")
async def startup_event():
    """Load GeoJSON data on server startup"""
    print("Starting Navigation Server...")

    # Use environment variable if set, otherwise default to /app/data
    geojson_file_path = os.getenv('GEOJSON_PATH', '/app/data/mcgillindoornavmerged.geojson')
    print(f"Looking for GeoJSON file at: {geojson_file_path}")

    # Check if file exists
    if not os.path.exists(geojson_file_path):
        print(f"GeoJSON file not found at {geojson_file_path}")
        print("Please ensure your GeoJSON file is in the mounted data folder.")
        return  # Let server start but log the error

    # Try loading the GeoJSON
    try:
        with open(geojson_file_path, 'r') as f:
            geojson_str = f.read()
            load_geojson(geojson_str)
        print(f"GeoJSON loaded successfully from {geojson_file_path}")
    except Exception as e:
        print(f"Failed to load GeoJSON: {e}")



# Development server (only runs if script is executed directly)
if __name__ == "__main__":
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=5000,
        reload=False,  # Set to True for development
        log_level="info"
    )