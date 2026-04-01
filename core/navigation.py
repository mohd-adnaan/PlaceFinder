"""
RouteTracker for Indoor Navigation
Main navigation logic for tracking user progress along routes
"""

import math
from typing import List, Tuple, Optional, Dict
from .position_validator import PositionValidator
from .error_recovery import BearingErrorRecovery
from .geojson_handler import get_office_pois
from config import NavigationConfig
from utils.logging_config import get_logger, get_navigation_logger, get_position_logger

logger = get_logger(__name__)
nav_logger = get_navigation_logger()
pos_logger = get_position_logger()

class RouteTracker:
    def __init__(self, waypoints):
        """Initialize with a list of waypoints [(x1,y1), (x2,y2), ...]"""
        self.waypoints = waypoints
        self.segments = []
        self.segment_bearings = []
        
        # Configuration from NavigationConfig
        self.stepSize = NavigationConfig.STEP_SIZE
        self.current_segment_idx = 0
        self.last_position = waypoints[0]
        self.last_bearing = 0
        self.waypoint_proximity_alert = False
        self.activate_move_direction_checker = False
        self.movement_progress_threshold = NavigationConfig.MOVEMENT_PROGRESS_THRESHOLD
        self.bearing_difference_threshold = NavigationConfig.BEARING_DIFFERENCE_THRESHOLD
        self.max_route_deviation_threshold = NavigationConfig.MAX_ROUTE_DEVIATION_THRESHOLD
        self.use_clock_directions = False
        self.use_landmarks_directions = False
        self.set_overshoot_flag = False
        self.overshoot_reversed_error_flag = False
        self.turn_angle_threshold = NavigationConfig.TURN_ANGLE_THRESHOLD
        self.turn_thresh = NavigationConfig.TURN_THRESH
        self.min_turn_warning_thresh_level1 = NavigationConfig.MIN_TURN_WARNING_THRESH_LEVEL1
        self.max_turn_warning_thresh_level1 = NavigationConfig.MAX_TURN_WARNING_THRESH_LEVEL1
        self.min_turn_warning_thresh_level2 = NavigationConfig.MIN_TURN_WARNING_THRESH_LEVEL2
        self.max_turn_warning_thresh_level2 = NavigationConfig.MAX_TURN_WARNING_THRESH_LEVEL2
        self.min_turn_warning_thresh = NavigationConfig.MIN_TURN_WARNING_THRESH
        self.max_turn_warning_thresh = NavigationConfig.MAX_TURN_WARNING_THRESH
        self.is_on_track_thresh = NavigationConfig.IS_ON_TRACK_THRESH
        self.approaching_destination_thresh = NavigationConfig.APPROACHING_DESTINATION_THRESH
        self.at_destination_thresh = NavigationConfig.AT_DESTINATION_THRESH
        self.is_turn_signal_activated = False
        self.segment_advance_thresh = NavigationConfig.SEGMENT_ADVANCE_THRESH
        self.qr_code_status = False
        self.qr_id = None
        self.initiate_turn_qr = NavigationConfig.INITIATE_TURN_QR
        self.confirm_turn_qr = NavigationConfig.CONFIRM_TURN_QR
        self.error_decision_wait_time = NavigationConfig.ERROR_DECISION_WAIT_TIME
        self.step_metre_scale = NavigationConfig.STEP_METRE_SCALE

        # Role assignment for visual anchors
        self.visual_anchor_roles = {
            self.initiate_turn_qr: None,
            self.confirm_turn_qr: None
        }

        # Navigation state for visual anchor-based turns
        self.visual_anchor_turn_state = "WAITING_FOR_SIGNAL"
        self.anchor_roles_initialized = False
        self.last_qr_id = None

        # Position validation and error recovery
        self.position_validator = PositionValidator(corridor_width=3.0)
        self.last_validated_position = waypoints[0] if waypoints else None
        self.validation_stats = {
            "total_updates": 0,
            "corrections_applied": 0,
            "outside_corridor_count": 0,
            "gentle_corrections": 0
        }

        # Add bearing-based error recovery
        self.bearing_error_recovery = BearingErrorRecovery()
        # Set the reference to this RouteTracker instance
        self.bearing_error_recovery.set_route_tracker(self)

        # Precompute segments and their bearings
        for i in range(len(waypoints) - 1):
            start, end = waypoints[i], waypoints[i+1]
            segment = (start, end)
            self.segments.append(segment)

            # Calculate bearing of segment (in degrees)
            bearing = self.calculate_bearing(start, end)
            self.segment_bearings.append(bearing)

        if self.segment_bearings:
            self.last_bearing = self.segment_bearings[0]

    def calculate_distance(self, p1, p2):
        """Calculate Euclidean distance between two points"""
        return math.sqrt((p2[0] - p1[0])**2 + (p2[1] - p1[1])**2)

    def calculate_bearing(self, p1, p2):
        """Calculate bearing from p1 to p2 in degrees (0 = East, 90 = North)"""
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
    
    def get_user_route_progress(self, current_user_position, current_segment_start, current_segment_end):
        distance_traveled_by_user = self.calculate_distance(current_user_position, current_segment_start)
        segment_length = self.calculate_distance(current_segment_start, current_segment_end)

        progress = distance_traveled_by_user / segment_length
        progress_percent = progress * 100

        logger.info(f"[NAV] TRAVELLED_DIST: {distance_traveled_by_user}, ROUTE_DIST: {segment_length}, PROGRESS_PERCENT: {progress_percent}")

        return progress


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

    def is_direction_similar(self, bearing1, bearing2, angle_deviation_threshold=None):
        """Check if two bearings are similar (within threshold degrees)"""
        angle_diff = abs(self.calculate_turn_angle(bearing1, bearing2))
        logger.debug(f"Current bearing: {bearing1}, Segment bearing: {bearing2}")
        logger.debug(f"Angle difference: {angle_diff}")
        if angle_deviation_threshold is not None:
            return angle_diff <= angle_deviation_threshold
        else:
            return angle_diff < self.turn_angle_threshold

    def get_landmark_direction(self, current_position, current_segment, user_bearing=None):
        """Get direction to nearby landmarks"""
        # Extract start coordinates from current segment
        start, end = current_segment
        office_pois = get_office_pois()

        # Check for the closest points of interest: This is to use landmark information
        logger.debug(f"Use landmarks directions: {self.use_landmarks_directions}")

        if office_pois and self.current_segment_idx < len(self.segments) - 2 and self.use_landmarks_directions:
            closest_poi = None
            min_distance = float('inf')
            name_of_closest_poi = ""

            # Loop through office POIs to find the closest one
            for poi in office_pois:
                poi_coords = poi['geometry']['coordinates']
                poi_name = poi['properties']['name']

                # Calculate Euclidean distance between user and POI
                distance = self.calculate_distance(current_position, poi_coords)

                # Update closest POI if this one is closer
                if distance < min_distance:
                    min_distance = distance
                    closest_poi = poi
                    name_of_closest_poi = poi_name

            # If closest POI is within threshold, determine direction and return info
            logger.debug(f"Closest landmarks distance: {min_distance}, Closest landmarks name: {name_of_closest_poi}")

            if min_distance <= 3 and closest_poi:
                poi_coords = closest_poi['geometry']['coordinates']
                poi_bearing = self.calculate_bearing(current_position, poi_coords)

                if user_bearing is None:
                     user_bearing = self.calculate_bearing(start, current_position)

                poi_angle = self.calculate_turn_angle(user_bearing, poi_bearing)
                poi_direction = self.get_direction_name(poi_angle)

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
        return is_final_segment and normalized_dist_from_seg_start >= self.at_destination_thresh

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

    def update_position(self, current_position, current_bearing=None, current_magnetic_strength=None, 
                       reported_qr_status=False, reported_qr_id=None):
        """Enhanced update_position with validation and correction"""
        logger.info(f"[NAV] CURRENT_POS: {current_position}")
        logger.info(f"[NAV] CURRENT_BEARING: {current_bearing}")
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
        #if validation_result["correction_applied"]:
            #pos_logger.info(f"Position corrected: {validation_result['correction_type']} - {validation_result['error_distance']:.1f}m from route")
        #else:
            #pos_logger.debug(f"Position valid: {validation_result['error_distance']:.1f}m from route")

        # Add bearing-based error recovery check
        if (current_bearing is not None and
            self.current_segment_idx < len(self.segments)):

            # Get expected bearing for current segment
            if self.is_turn_signal_activated:
                expected_bearing = self.segment_bearings[self.current_segment_idx + 1]
                expected_segment = self.segments[self.current_segment_idx + 1]
                self.bearing_error_recovery.duration_threshold = self.error_decision_wait_time
                self.bearing_error_recovery.is_turn_signal_enabled = True
            else:
                expected_bearing = self.segment_bearings[self.current_segment_idx]
                expected_segment = self.segments[self.current_segment_idx]

            # Check for bearing-based navigation errors
            
            recovery_result = self.bearing_error_recovery.update_bearing_tracking(
                user_bearing=current_bearing,
                expected_bearing=expected_bearing,
                current_user_position=current_position,
                expected_segment=expected_segment
            )
            logger.debug(f"Recovery result: {recovery_result}")

            # If recovery instruction needed, return it immediately
            if recovery_result and recovery_result['status'] != "RECOVERY_COMPLETE":
                logger.error(f"BEARING ERROR RECOVERY: {recovery_result['message']}")
                return recovery_result
        

        # 5. Continue with your existing navigation logic using corrected position
        if recovery_result and recovery_result['status'] == "RECOVERY_COMPLETE":
            #navigation_n_recovery_result = self.handle_error_recovery_with_guidance_information(corrected_position, current_bearing)
            navigation_n_recovery_result = self.handle_error_recovery_with_guidance_information(current_position, current_bearing) # use current position and not corrected
            logger.debug(f"Navigation result: {navigation_n_recovery_result}")
            # 6. Add validation info to the response
            if navigation_n_recovery_result:
                return navigation_n_recovery_result

    def _handle_destination_reached(self, dest_segment_bearing, last_segment_bearing, user_dist_to_destination):
        """Handle when user reaches the final destination."""
        step_count = round(user_dist_to_destination / self.stepSize)
        turn_to_destination = self.calculate_turn_angle(dest_segment_bearing, last_segment_bearing)
        destination_direction = self.get_direction_name(turn_to_destination)

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
        """Handle navigation guidance based on user's current position relative to the route."""

        # Validate we have segments to work with
        if not self.segments or len(self.segments) < 1:
            return None

        # Get route information
        last_segment = self.segments[-1]
        last_segment_bearing = self.segment_bearings[-1]

        destination_segment = self.segments[-2]
        dest_segment_bearing = self.segment_bearings[-2]
        dest_segment_start, dest_segment_end = destination_segment

        current_segment = self.segments[self.current_segment_idx]
        current_segment_bearing = self.segment_bearings[self.current_segment_idx]
        current_segment_start, current_segment_end = current_segment

        snapped_user_position, normalized_dist_from_seg_start = self.get_closest_point_on_segment(current_user_position, current_segment)
        normalized_dist_from_seg_start = self.get_user_route_progress(current_user_position, current_segment_start,current_segment_end)
        #current_user_position = snapped_user_position  # More accurate than the reported position
        current_user_bearing = current_bearing

        last_segment_start, last_segment_end = last_segment

        # Calculate key distances and positions
        user_dist_to_destination = self.calculate_distance(current_user_position, dest_segment_end)
        user_dist_to_seg_end = self.calculate_distance(current_user_position, current_segment_end)
        #deviation_distance = self.calculate_distance(current_user_position, snapped_user_position)

        # Check if user is at the final destination
        if self._is_user_at_destination(normalized_dist_from_seg_start, user_dist_to_destination):
            return self._handle_destination_reached(dest_segment_bearing, last_segment_bearing, user_dist_to_destination)

        # Check if we're approaching the destination
        if self._is_approaching_destination(normalized_dist_from_seg_start):
            nav_logger.info(f"APPROACHING DESTINATION - Segment {self.current_segment_idx}, Progress: {normalized_dist_from_seg_start:.2f}")

            return {
                "status": "Approaching destination",
                "message": "Approaching destination!"
            }

        # Provide general progress feedback
        if (self._is_on_track(normalized_dist_from_seg_start) and self.qr_code_status==False):
            nav_logger.info(f"ON TRACK - Segment {self.current_segment_idx}, Progress: {normalized_dist_from_seg_start:.2f}")

            return {
                "status": "On track information",
                "message": "You are on track!"
            }

        # Handle segment transitions and turns
        if self._should_advance_segment():
            next_segment_bearing = self.segment_bearings[self.current_segment_idx + 1]

            turn_result = self._handle_segment_transition(
                normalized_dist_from_seg_start, user_dist_to_seg_end, current_segment_bearing, 
                next_segment_bearing, current_user_position, current_user_bearing)

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
        logger.info(f"Visual anchor roles initialized: {self.visual_anchor_roles}")

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
            logger.info(f"Signal visual anchor detected: {qr_id}, turn signal activated")
            return "TURN_SIGNAL"

        return None

    def _handle_confirm_anchor(self, qr_id):
        """Handle when a confirm visual anchor is detected"""
        if self.visual_anchor_turn_state == "SIGNAL_RECEIVED":
            self.visual_anchor_turn_state = "CONFIRMED"
            logger.info(f"Confirm visual anchor detected: {qr_id}, turn confirmed")
            return "TURN_CONFIRMED"

        return None

    def reset_visual_anchor_turn_state(self):
        """Reset the visual anchor turn state for the next turn sequence"""
        self.visual_anchor_turn_state = "WAITING_FOR_SIGNAL"

    def _handle_segment_transition(self, normalized_dist_from_seg_start, user_dist_to_segment_end,
                                 current_segment_bearing, next_segment_bearing, current_user_position,
                                 current_user_bearing):
        """Enhanced segment transition handling with visual anchor role assignment"""
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
                logger.info("Turn confirmed by direction alignment")

            # Check visual anchor-based confirmation
            elif self.qr_code_status:
                anchor_result = self.handle_visual_anchor_detection(self.qr_id, is_significant_turn, next_segment_bearing)
                if anchor_result == "TURN_CONFIRMED":
                    turn_confirmed = True
                    logger.info("Turn confirmed by confirm visual anchor")

            # Execute turn if confirmed
            if turn_confirmed:
                nav_logger.info(f"TURN EXECUTED - Completed turn to segment {self.current_segment_idx}, Bearing: {current_user_bearing}, QR: {self.qr_code_status}")

                self.current_segment_idx += 1
                self.is_turn_signal_activated = False
                self.reset_visual_anchor_turn_state()

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
             self.current_segment_idx < len(self.segments) - 2):
            should_turn_now = True
            logger.info("Turn signal activated by distance threshold")

        # Visual anchor-based turn signal condition with role assignment
        elif (is_significant_turn and
               self.current_segment_idx < len(self.segments) - 2 and
              self.qr_code_status):

            anchor_result = self.handle_visual_anchor_detection(self.qr_id, is_significant_turn, next_segment_bearing)
            if anchor_result == "TURN_SIGNAL":
                should_turn_now = True
                logger.info("Turn signal activated by signal visual anchor")

        elif (is_significant_turn == False
              and  self.current_segment_idx < len(self.segments) - 2
              and self.current_segment_idx + 2 < len(self.segment_bearings)
              and self.segment_bearings[self.current_segment_idx+2] != self.segment_bearings[-2]
              and self.qr_code_status
              and self.last_qr_id != self.qr_id
              and self.is_turn_signal_activated == False):

              next_next_segment_bearing = self.segment_bearings[self.current_segment_idx+2]
              next_turn_angle = self.calculate_turn_angle(next_segment_bearing, next_next_segment_bearing)
              is_significant_turn_next = abs(next_turn_angle) > self.turn_angle_threshold

              if is_significant_turn_next:
                should_turn_now = True
                logger.info("Turn signal activated by signal visual anchor before the actual segment")
                self.current_segment_idx += 1
                turn_direction = self.get_direction_name(next_turn_angle)

        if should_turn_now and self.is_turn_signal_activated == False:
            nav_logger.info(f"TURN SIGNAL - Segment {self.current_segment_idx}, Progress: {normalized_dist_from_seg_start:.2f}, Turn: {turn_direction}, QR: {self.qr_code_status}")
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
            nav_logger.info(f"SEGMENT CHANGE - Now on segment {self.current_segment_idx}, Progress: {normalized_dist_from_seg_start:.2f}")
            self.current_segment_idx += 1
            self.reset_visual_anchor_turn_state()

            start_pos, end_pos = self.segments[self.current_segment_idx]

            if self.use_landmarks_directions:
                landmarks_instruction = self.get_landmark_direction(current_user_position, self.segments[self.current_segment_idx-1])

                if landmarks_instruction == None:
                    return {
                        "status": "segment_change",
                        "message": "Keep moving!",
                        "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]],
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
                          "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]],
                          "segment_info": {
                              "segment_index": self.current_segment_idx,
                              "is_significant_turn": False
                          }
                      }
            if self.use_landmarks_directions == False:
                return {
                        "status": "segment_change",
                        "message": "Keep moving!",
                        "new_map_position": [start_pos[0], start_pos[1], self.segment_bearings[self.current_segment_idx]],
                        "segment_info": {
                            "segment_index": self.current_segment_idx,
                            "is_significant_turn": False
                        }
                    }

        nav_logger.info(f"ON TRACK - Segment {self.current_segment_idx}, Progress: {normalized_dist_from_seg_start:.2f}")

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