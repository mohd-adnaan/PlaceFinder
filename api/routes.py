"""
API Routes for Indoor Navigation
Contains the main wayfinder endpoint and other API routes
"""

from fastapi import HTTPException, Header
from typing import Union, Optional
import time

from models import InitializeRequest, UpdateRequest, NavigationResponse, CalibrationData
from core import NavigationSession, get_poi_mapping
from utils.conversation import generate_conversation_mode_response
from utils.logging_config import get_logger
from config import SESSIONS

logger = get_logger(__name__)

async def wayfinder(
    request: Union[InitializeRequest, UpdateRequest],
    session_id: Optional[str] = Header(default="default", alias="Session-ID")
) -> NavigationResponse:
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

                logger.info(f"Navigation: {source_name} → {destination_name} | QR: {door_qr_code} | Mode: {'Conversation' if conversation_mode else 'Standard'}")

                try:
                    session = NavigationSession(source_name, destination_name, use_clock_directions, use_landmarks_directions)
                    SESSIONS[session_id] = session
                except Exception as e:
                    logger.error(f"Error creating NavigationSession: {e}")
                    logger.debug(f"Source: {source_name}, Destination: {destination_name}")
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
                path_bearings = session.route_tracker.segment_bearings
                first_segment_bearing = path_bearings[0]

                # Added this to test the recovery part:
                if len(path_coords) >= 3: # No explicit initial heading recommendation.
                    instructions = f"Press start navigation button!"

                logger.info(f"Route ready: {len(path_coords)} waypoints, {len(path_bearings)} segments")

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
            if session_id not in SESSIONS:
                raise HTTPException(status_code=404, detail="No active navigation session found")

            update_req = request if isinstance(request, UpdateRequest) else UpdateRequest(**request.dict())

            try:
                session = SESSIONS[session_id]
                reported_position = [update_req.currentX, update_req.currentY]
                reported_bearing = update_req.currentBearing
                reported_magnetic_strength = update_req.magneticFieldStrength
                reported_qr_status = update_req.qrDetected
                reported_qr_id = update_req.qrCodeId

                detailed_result = session.detect_deviation(
                    reported_position, reported_bearing, reported_magnetic_strength, 
                    reported_qr_status, reported_qr_id
                )

                logger.debug(f"Update: QR {reported_qr_status}, ID {reported_qr_id}")

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
        logger.error(f"Wayfinder error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def health_check():
    """Health check endpoint"""
    from models import HealthResponse
    from core.geojson_handler import get_geojson_data
    from config import SERVER_START_TIME
    
    return HealthResponse(
        status="healthy",
        timestamp=time.time(),
        geojson_loaded=get_geojson_data() is not None,
        total_sessions=len(SESSIONS),
        uptime_seconds=time.time() - SERVER_START_TIME
    )