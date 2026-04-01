"""
Position Validator for Indoor Navigation
Validates and corrects user positions to keep them within corridor boundaries
"""

import math
from typing import List, Dict, Optional, Tuple
from config import PositionValidatorConfig

class PositionValidator:
    """
    Validates and corrects user positions to keep them within corridor boundaries
    """

    def __init__(self, corridor_width: float = PositionValidatorConfig.CORRIDOR_WIDTH):
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
        quarter_corridor_width = self.corridor_width / 4.0

        if distance > quarter_corridor_width:
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

        # Normalize and scale to close to the centre line
        quarter_width = self.corridor_width / 4.0

        corrected_x = cx + (dx / distance) * quarter_width
        corrected_y = cy + (dy / distance) * quarter_width

        return [corrected_x, corrected_y]