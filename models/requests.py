"""
Request models for the Indoor Navigation API
"""

from pydantic import BaseModel
from typing import Optional

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