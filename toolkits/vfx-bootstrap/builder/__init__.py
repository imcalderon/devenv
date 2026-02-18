"""
vfx-bootstrap Builder Module

Build orchestration for VFX Platform-compliant packages.
Wraps conda-build with caching, logging, and dependency management.
"""

from .cache import BuildCache
from .container import ContainerBuilder
from .core import VFXBuilder

__all__ = ["VFXBuilder", "BuildCache", "ContainerBuilder"]
__version__ = "0.1.0"
