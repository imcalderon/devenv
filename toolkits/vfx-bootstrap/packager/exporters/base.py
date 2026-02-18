"""
Base exporter interface for vfx-bootstrap packager.
"""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import List, Optional, Union

from ..schema import PackageManifest


class Exporter(ABC):
    """
    Base class for package exporters.

    Exporters convert a PackageManifest into a specific distribution format.
    """

    def __init__(self, manifest: PackageManifest):
        """
        Initialize the exporter.

        Args:
            manifest: Package manifest to export.
        """
        self.manifest = manifest

    @property
    @abstractmethod
    def format_name(self) -> str:
        """Name of the export format."""
        pass

    @property
    @abstractmethod
    def file_extension(self) -> str:
        """File extension for exported packages."""
        pass

    @abstractmethod
    def export(
        self,
        source_dir: Union[str, Path],
        output_dir: Union[str, Path],
        components: Optional[List[str]] = None,
    ) -> Path:
        """
        Export the package to the target format.

        Args:
            source_dir: Directory containing built files.
            output_dir: Directory for output package.
            components: Specific components to include (None = all required).

        Returns:
            Path to the exported package file.
        """
        pass

    def get_output_filename(self) -> str:
        """Generate output filename for the package."""
        return f"{self.manifest.name}-{self.manifest.version}{self.file_extension}"

    def validate_source(
        self, source_dir: Path, components: Optional[List[str]] = None
    ) -> List[str]:
        """
        Validate that all required files exist in source directory.

        Args:
            source_dir: Directory containing built files.
            components: Components to validate.

        Returns:
            List of missing files.
        """
        files = self.manifest.get_all_files(components)
        missing = []

        for file_mapping in files:
            # Handle glob patterns
            if "*" in file_mapping.src:
                import glob

                matches = list(source_dir.glob(file_mapping.src))
                if not matches and not file_mapping.optional:
                    missing.append(file_mapping.src)
            else:
                src_path = source_dir / file_mapping.src
                if not src_path.exists() and not file_mapping.optional:
                    missing.append(file_mapping.src)

        return missing
