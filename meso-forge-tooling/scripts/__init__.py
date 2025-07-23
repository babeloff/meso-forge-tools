"""
meso-forge-tooling scripts package.

This package contains the core scripts and utilities for the meso-forge-tooling system.
"""

# Version information
__version__ = "0.1.5"

# Import main plugin system for convenience
from .plugins_source import PluginManager, SourcePlugin, VersionInfo

__all__ = ["PluginManager", "SourcePlugin", "VersionInfo"]
