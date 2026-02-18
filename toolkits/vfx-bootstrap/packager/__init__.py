"""
vfx-bootstrap Packager Module

Format-agnostic packaging system for VFX software distribution.
"""

from .exporters.archive import ArchiveExporter
from .exporters.conda import CondaExporter
from .exporters.tarball import TarballExporter
from .schema import PackageManifest

__all__ = [
    "PackageManifest",
    "CondaExporter",
    "TarballExporter",
    "ArchiveExporter",
]
__version__ = "0.1.0"
