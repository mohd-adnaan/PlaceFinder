"""
Response models for the Indoor Navigation API
"""

from pydantic import BaseModel
from typing import List, Dict, Optional, Any

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