"""
API package for Indoor Navigation API
Contains the API routes and endpoints
"""

from .routes import wayfinder, health_check

__all__ = ['wayfinder', 'health_check']