"""
Logging configuration for Indoor Navigation API
Sets up proper logging with readable formats and useful contextual information
"""

import logging
import logging.config
import sys
from typing import Dict, Any

def setup_logging(log_level: str = "INFO", log_file: str = None) -> None:
    """
    Set up logging configuration for the application
    
    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_file: Optional file path to write logs to
    """
    
    # Define log formats - much more readable and concise
    console_format = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    file_format = "%(asctime)s [%(levelname)s] %(name)s - %(funcName)s:%(lineno)d - %(message)s"
    navigation_format = "%(asctime)s [NAV] %(message)s"
    simple_format = "%(asctime)s: %(message)s"
    
    date_format = "%H:%M:%S"
    
    # Configure logging
    logging_config = {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "console": {
                "format": console_format,
                "datefmt": date_format
            },
            "file": {
                "format": file_format,
                "datefmt": "%Y-%m-%d %H:%M:%S"
            },
            "navigation": {
                "format": navigation_format,
                "datefmt": date_format
            },
            "simple": {
                "format": simple_format,
                "datefmt": date_format
            }
        },
        "handlers": {
            "console": {
                "level": log_level,
                "class": "logging.StreamHandler",
                "formatter": "console",
                "stream": sys.stdout
            },
            "navigation_console": {
                "level": "INFO",
                "class": "logging.StreamHandler", 
                "formatter": "navigation",
                "stream": sys.stdout
            }
        },
        "loggers": {
            "": {  # Root logger
                "level": log_level,
                "handlers": ["console"],
                "propagate": False
            },
            "indoor_navigation": {
                "level": "DEBUG",  
                "handlers": ["console"],
                "propagate": False
            },
            "indoor_navigation.navigation": {  # Special handler for navigation events
                "level": "INFO",
                "handlers": ["navigation_console"],
                "propagate": False
            },
            "indoor_navigation.position": {  # Special handler for position updates
                "level": "INFO", 
                "handlers": ["navigation_console"],
                "propagate": False
            },
            "indoor_navigation.recovery": {  # Special handler for error recovery
                "level": "INFO",
                "handlers": ["navigation_console"], 
                "propagate": False
            }
        }
    }
    
    # Add file handler if log_file is specified
    if log_file:
        logging_config["handlers"]["file"] = {
            "level": log_level,
            "class": "logging.FileHandler",
            "formatter": "file",
            "filename": log_file,
            "mode": "a"
        }
        # Add file handler to all loggers
        for logger_name in logging_config["loggers"]:
            if "handlers" in logging_config["loggers"][logger_name]:
                logging_config["loggers"][logger_name]["handlers"].append("file")
    
    # Apply configuration
    logging.config.dictConfig(logging_config)

def get_logger(name: str = None) -> logging.Logger:
    """
    Get a logger instance for the given name
    
    Args:
        name: Logger name (usually __name__)
        
    Returns:
        Logger instance
    """
    if name:
        # Create shorter, more readable logger names
        short_name = name.split('.')[-1]  # Just the module name, not full path
        return logging.getLogger(f"indoor_navigation.{short_name}")
    else:
        return logging.getLogger("indoor_navigation")

def get_navigation_logger() -> logging.Logger:
    """Get a special logger for navigation events with cleaner output"""
    return logging.getLogger("indoor_navigation.navigation")

def get_position_logger() -> logging.Logger:
    """Get a special logger for position updates"""
    return logging.getLogger("indoor_navigation.position")

def get_recovery_logger() -> logging.Logger:
    """Get a special logger for error recovery events"""
    return logging.getLogger("indoor_navigation.recovery")

# Navigation-specific log levels
class NavigationLogLevel:
    """Custom log levels for navigation-specific events"""
    
    # Add custom levels
    NAVIGATION = 25  # Between INFO and WARNING
    BEARING_ANALYSIS = 15  # Between DEBUG and INFO
    POSITION_UPDATE = 12  # Between DEBUG and INFO
    
    @classmethod
    def setup_custom_levels(cls):
        """Add custom logging levels"""
        logging.addLevelName(cls.NAVIGATION, "NAV")
        logging.addLevelName(cls.BEARING_ANALYSIS, "BEARING")
        logging.addLevelName(cls.POSITION_UPDATE, "POS")
        
        # Add methods to Logger class for easier usage
        def navigation(self, message, *args, **kwargs):
            if self.isEnabledFor(cls.NAVIGATION):
                self._log(cls.NAVIGATION, message, args, **kwargs)
                
        def bearing_analysis(self, message, *args, **kwargs):
            if self.isEnabledFor(cls.BEARING_ANALYSIS):
                self._log(cls.BEARING_ANALYSIS, message, args, **kwargs)
                
        def position_update(self, message, *args, **kwargs):
            if self.isEnabledFor(cls.POSITION_UPDATE):
                self._log(cls.POSITION_UPDATE, message, args, **kwargs)
        
        logging.Logger.navigation = navigation
        logging.Logger.bearing_analysis = bearing_analysis  
        logging.Logger.position_update = position_update

# Initialize custom levels
NavigationLogLevel.setup_custom_levels()