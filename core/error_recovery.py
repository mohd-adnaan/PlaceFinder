"""
Bearing Error Recovery for Indoor Navigation
Pure bearing-based error recovery system that doesn't rely on position data
"""

import time
import math
from config import BearingErrorConfig
from utils.logging_config import get_logger, get_recovery_logger

logger = get_logger(__name__)
recovery_logger = get_recovery_logger()

class BearingErrorRecovery:
    """
    Pure bearing-based error recovery system that doesn't rely on position data
    """
    def __init__(self, bearing_threshold=BearingErrorConfig.BEARING_THRESHOLD, 
                 duration_threshold=BearingErrorConfig.DURATION_THRESHOLD, 
                 min_samples=BearingErrorConfig.MIN_SAMPLES):
        self.bearing_threshold = bearing_threshold  # degrees difference to consider "wrong direction"
        self.duration_threshold = duration_threshold  # seconds of wrong bearing before triggering recovery
        self.min_samples = min_samples  # minimum bearing samples needed

        # Error tracking state
        self.wrong_bearing_start_time = None
        self.wrong_bearing_samples = []
        self.is_in_recovery_mode = False
        self.recovery_instruction_given = False
        self.last_recovery_time = None
        self.recovery_cooldown = BearingErrorConfig.RECOVERY_COOLDOWN  # seconds between recovery instructions

        # Bearing history for analysis
        self.bearing_history = []
        self.max_history = BearingErrorConfig.MAX_HISTORY

        # Will be set by RouteTracker after initialization
        self.route_tracker = None
        self.segments = None
        self.current_segment_idx = None
        self.use_landmarks_directions = None
        self.is_turn_signal_enabled = False
        self.re_alignment_start_time = None
        self.avg_bearing_error = 0.0
        self.activate_final_recovery_instruction = False
        self.large_bearing_error = BearingErrorConfig.LARGE_BEARING_ERROR
        self.last_known_user_position_before_error = None
        self.user_position_deviation_threshold = BearingErrorConfig.USER_POSITION_DEVIATION_THRESHOLD  # metres
        self.user_error_detection_threshold = BearingErrorConfig.USER_ERROR_DETECTION_THRESHOLD  # metres

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

        logger.info(f"[DEBUG] Bearing: User {user_bearing:.1f}°, Expected {expected_bearing:.1f}°, Diff {bearing_diff:.1f}°, Wrong: {is_wrong_direction}")

        # Track wrong direction episodes
        if is_wrong_direction:
            if self.wrong_bearing_start_time is None:
                # Start tracking wrong direction
                self.wrong_bearing_start_time = timestamp
                self.wrong_bearing_samples = [bearing_diff]
                self.last_known_user_position_before_error = current_user_position
                recovery_logger.warning(f"WRONG DIRECTION detected - starting tracking at: {self.last_known_user_position_before_error}")
            else:
                # Continue tracking wrong direction
                self.wrong_bearing_samples.append(bearing_diff)

            # Check if error has persisted long enough
            error_duration = timestamp - self.wrong_bearing_start_time
            enough_samples = len(self.wrong_bearing_samples) >= self.min_samples
            logger.info(f"[ERROR] USER_DIST_FROM_LAST_KNOWM_POS: {user_distance_error}")
            logger.debug(f"Wrong direction: {error_duration:.1f}s, samples: {len(self.wrong_bearing_samples)}")
            # Trigger recovery if duration exceeded and we have enough samples
            if ((error_duration >= self.duration_threshold and
                enough_samples and not self.is_in_recovery_mode)
                  or user_distance_error >= self.user_error_detection_threshold and not self.is_in_recovery_mode):
                recovery_logger.error(f"RECOVERY TRIGGERED - Bearing Error: {self.avg_bearing_error:.1f}° at {current_user_position}")

                return self._trigger_recovery(bearing_diff, expected_bearing, user_bearing, expected_segment, current_user_position)
            
            
            elif self.is_in_recovery_mode and abs(self.avg_bearing_error) < self.large_bearing_error:
                logger.info(f"Recovering but not yet at the point to turn.")
                if user_distance_error <= self.user_position_deviation_threshold and self.activate_final_recovery_instruction == False:
                    # Direction for recovery
                    current_user_bearing = self.route_tracker.calculate_bearing(current_user_position, expected_segment[0])
                    turn_angle = self.route_tracker.calculate_turn_angle(current_user_bearing, expected_bearing)
                    turn_direction = self.route_tracker.get_direction_name(turn_angle)
                    message = f"Turn {turn_direction}"
                    logger.info(f"[DEBUG] User receives {message} instruction to complete recovery. current_position: {current_user_position}, last_known_pos_before_error: {self.last_known_user_position_before_error}, userDisterror:{user_distance_error}")
                    self.activate_final_recovery_instruction = True
                    
                    return {
                        "status": "error_recovery",
                        "message": message
                    }
                    
                
        
        else:
            # User is going correct direction
            if self.is_in_recovery_mode and self.is_turn_signal_enabled and abs(self.avg_bearing_error) >= self.large_bearing_error: ## # recovery from direct opposite direction (180 degrees) after turn instructions

                if self.re_alignment_start_time == None:
                  self.re_alignment_start_time = time.time()

                re_alignment_duration = time.time() - self.re_alignment_start_time
                logger.debug(f"Realignment duration:{re_alignment_duration}")
                
                logger.info(f"[ERROR] USER_DIST_TO_LAST_KNOWN_POS: {user_distance_error}")
                if re_alignment_duration >= self.duration_threshold or user_distance_error <= self.user_position_deviation_threshold: 
                  # User has corrected their bearing - exit recovery mode
                  logger.info(f"User has fully recovered to the last error point at {current_user_position}.")
                  recovery_complete = self._complete_recovery()
                  return recovery_complete
                

            elif self.is_in_recovery_mode and abs(self.avg_bearing_error) >= self.large_bearing_error: ## # recovery from direct opposite direction (180 degrees) without turn instructions

                if self.re_alignment_start_time == None:
                  self.re_alignment_start_time = time.time()

                re_alignment_duration = time.time() - self.re_alignment_start_time
                logger.debug(f"Realignment duration:{re_alignment_duration}")
                
                logger.info(f"[ERROR] USER_DIST_TO_LAST_KNOWN_POS: {user_distance_error}")
                if re_alignment_duration >= self.duration_threshold or user_distance_error <= self.user_position_deviation_threshold: 
                  # User has corrected their bearing - exit recovery mode
                  logger.info(f"User has fully recovered to the last error point at {current_user_position}.")
                  recovery_complete = self._complete_recovery()
                  return recovery_complete

            elif self.is_in_recovery_mode and self.is_turn_signal_enabled and abs(self.avg_bearing_error) < self.large_bearing_error: # Recovery from adjacent direction (90) after turn instructions
           
                logger.info(f"[ERROR] USER_DIST_TO_LAST_KNOWN_POS: {user_distance_error}")
                if user_distance_error <= self.user_position_deviation_threshold:
                    recovery_complete = self._complete_recovery()
                    return recovery_complete
            
            elif self.is_in_recovery_mode and abs(self.avg_bearing_error) < self.large_bearing_error: # Recovery from adjacent direction (90) without turn instructions
        
                logger.info(f"[ERROR] USER_DIST_TO_LAST_KNOWN_POS: {user_distance_error}")
                if user_distance_error <= self.user_position_deviation_threshold: 
                    recovery_complete = self._complete_recovery()
                    return recovery_complete


            else:
              recovery_complete = self._complete_recovery()
              return recovery_complete

            # Reset wrong direction tracking
            #self._reset_wrong_direction_tracking() i dont know what this is doing yet

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

        logger.error(f"RECOVERY TRIGGERED - Avg bearing error: {self.avg_bearing_error:.1f}°")

        # Get current segment from the route tracker
        if self.route_tracker and self.route_tracker.current_segment_idx < len(self.route_tracker.segments):
            current_segment = self.route_tracker.segments[self.route_tracker.current_segment_idx]
            previous_segment = None
            if self.route_tracker.current_segment_idx > 0:
                previous_segment = self.route_tracker.segments[self.route_tracker.current_segment_idx - 1]
                previous_start, previous_end = previous_segment
            start, end = current_segment
            

            if self.route_tracker.use_landmarks_directions:
                
                current_landmarks_result = self.route_tracker.get_landmark_direction(start, current_segment)
                logger.debug(f"Current landmarks: {current_landmarks_result}")

                previous_landmarks_result = None
                if self.route_tracker.current_segment_idx > 0: # to avoid picking last segment [-1]
                    previous_landmarks_result = self.route_tracker.get_landmark_direction(previous_start, previous_segment)
                    logger.debug(f"Previous landmarks: {previous_landmarks_result}")

                if current_landmarks_result:
                    nearby_landmarks.append(current_landmarks_result)

                if previous_landmarks_result: 
                    nearby_landmarks.append(previous_landmarks_result)
                
                if nearby_landmarks == None or len(nearby_landmarks) < 1:
                    # Determine recovery action based on bearing difference
                    if abs(self.avg_bearing_error) >= self.large_bearing_error:
                        # User is going roughly opposite direction
                        recovery_type = "TURN_AROUND"
                        message = "Wrong direction! Turn around and continue straight."

                    elif abs(self.avg_bearing_error) > self.bearing_threshold:
                        recovery_type = "BACKTRACK_AND_TURN"
                        #message = f"Wrong direction! Backtrack, then turn {turn_direction}."
                        message = f"Wrong direction! Backtrack!"

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

                if nearby_landmarks != None and len(nearby_landmarks) > 0:
                    landmark_names = [landmark['name'] for landmark in nearby_landmarks]
                    
                    # Extract landmark names and remove duplicates while preserving order
                    landmark_names = list(dict.fromkeys([
                    landmark['name'] for landmark in nearby_landmarks 
                    if landmark.get('name') and landmark['name'].strip()]))
                    logger.debug(f"Landmark names for recovery: {landmark_names}")
            
                    # Create concise landmark info
                    if len(landmark_names) == 1:
                          base_message = f", You are not too far away from {landmark_names[0]}"
                    elif len(landmark_names) == 2:
                          base_message = f", You are not too far away from {landmark_names[0]} and {landmark_names[1]}"
                    else:
                          # For more than 2 landmarks, show first 2
                          base_message = f", You are not too far away from {landmark_names[0]} and {landmark_names[1]}"
                             
                    # Determine recovery action based on bearing difference
                    if abs(self.avg_bearing_error) >= self.large_bearing_error:
                        recovery_type = "TURN_AROUND"
                        message = f"Wrong direction! Turn around and continue straight. {base_message}"

                    elif abs(self.avg_bearing_error) > self.bearing_threshold:
                        recovery_type = "BACKTRACK_AND_TURN"
                        #message = f"Wrong direction! Backtrack, then turn {turn_direction}. {base_message}"
                        message = f"Wrong direction! Backtrack! {base_message}"


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
                if abs(self.avg_bearing_error) >= self.large_bearing_error:
                    recovery_type = "TURN_AROUND"
                    message = "Wrong direction! Turn around and continue straight."
                elif abs(self.avg_bearing_error) > self.bearing_threshold:
                    
                    recovery_type = "BACKTRACK_AND_TURN"
                    #message = f"Wrong direction! Backtrack, then turn {turn_direction}."
                    message = f"Wrong direction! Backtrack!" 
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
        recovery_logger.info("RECOVERY COMPLETED - User back on correct direction")
        self.is_in_recovery_mode = False
        self._reset_wrong_direction_tracking()
        self.re_alignment_start_time = None
        self.is_turn_signal_enabled = False
        self.activate_final_recovery_instruction = False
        self.last_known_user_position_before_error = None

        return {
            "status": "RECOVERY_COMPLETE",
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