"""
Main FastAPI application for Indoor Navigation API
Refactored from monolithic file into modular structure
"""

import os
import uvicorn
from fastapi import FastAPI
from typing import Union

from config import SERVER_TITLE, SERVER_DESCRIPTION, SERVER_VERSION, GEOJSON_PATH, LOGGING_CONFIG
from utils.logging_config import setup_logging, get_logger
from models import InitializeRequest, UpdateRequest, NavigationResponse, HealthResponse
from api.routes import wayfinder, health_check
from core import load_geojson

# Setup logging first
setup_logging(log_level=LOGGING_CONFIG['level'], log_file=LOGGING_CONFIG['file'])
logger = get_logger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title=SERVER_TITLE,
    description=SERVER_DESCRIPTION,
    version=SERVER_VERSION
)

# Add the main wayfinder endpoint
@app.post("/wayfinder", response_model=NavigationResponse)
async def wayfinder_endpoint(
    request: Union[InitializeRequest, UpdateRequest],
    session_id: str = "default"
):
    """Main wayfinding endpoint"""
    return await wayfinder(request, session_id)

# Add health check endpoint
@app.get("/health", response_model=HealthResponse)
async def health_endpoint():
    """Health check endpoint"""
    return await health_check()

# Startup event
@app.on_event("startup")
async def startup_event():
    """Load GeoJSON data on server startup"""
    logger.info("Starting Navigation Server...")

    # Use environment variable if set, otherwise default
    geojson_file_path = GEOJSON_PATH
    logger.info(f"Looking for GeoJSON file at: {geojson_file_path}")

    # Check if file exists
    if not os.path.exists(geojson_file_path):
        logger.error(f"GeoJSON file not found at {geojson_file_path}")
        logger.error("Please ensure your GeoJSON file is in the mounted data folder.")
        return  # Let server start but log the error

    # Try loading the GeoJSON
    try:
        with open(geojson_file_path, 'r') as f:
            geojson_str = f.read()
            load_geojson(geojson_str)
        logger.info(f"GeoJSON loaded successfully from {geojson_file_path}")
    except Exception as e:
        logger.error(f"Failed to load GeoJSON: {e}")

# Development server (only runs if script is executed directly)
if __name__ == "__main__":
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=5000,
        reload=False,  # Set to True for development
        log_level="debug"
    )