"""
Conda package exporter for vfx-bootstrap.
"""

import json
import os
import tarfile
from pathlib import Path
from typing import List, Optional, Union

from ..schema import PackageManifest
from .base import Exporter


class CondaExporter(Exporter):
    """
    Export packages to conda format.

    Creates .conda or .tar.bz2 packages compatible with conda channels.
    """

    @property
    def format_name(self) -> str:
        return "conda"

    @property
    def file_extension(self) -> str:
        return ".tar.bz2"

    def export(
        self,
        source_dir: Union[str, Path],
        output_dir: Union[str, Path],
        components: Optional[List[str]] = None,
    ) -> Path:
        """
        Export to conda package format.

        Args:
            source_dir: Directory containing built files.
            output_dir: Directory for output package.
            components: Specific components to include.

        Returns:
            Path to the exported .tar.bz2 package.
        """
        source_dir = Path(source_dir)
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Validate source
        missing = self.validate_source(source_dir, components)
        if missing:
            raise FileNotFoundError(f"Missing files: {missing}")

        # Determine subdir (platform)
        import platform

        system = platform.system().lower()
        machine = platform.machine()
        if system == "linux":
            subdir = "linux-64" if machine == "x86_64" else f"linux-{machine}"
        elif system == "darwin":
            subdir = "osx-arm64" if machine == "arm64" else "osx-64"
        else:
            subdir = "noarch"

        # Create package filename
        pkg_name = f"{self.manifest.name}-{self.manifest.version}-py311_0"
        output_file = output_dir / subdir / f"{pkg_name}.tar.bz2"
        output_file.parent.mkdir(parents=True, exist_ok=True)

        # Create package archive
        with tarfile.open(output_file, "w:bz2") as tar:
            # Add files
            files = self.manifest.get_all_files(components)
            for file_mapping in files:
                self._add_files_to_tar(tar, source_dir, file_mapping)

            # Add conda metadata
            self._add_metadata(tar)

        return output_file

    def _add_files_to_tar(self, tar: tarfile.TarFile, source_dir: Path, file_mapping):
        """Add files matching a mapping to the tarball."""
        if "*" in file_mapping.src:
            for src_path in source_dir.glob(file_mapping.src):
                if src_path.is_file():
                    rel_path = src_path.relative_to(source_dir)
                    dst_path = file_mapping.dst.rstrip("/") + "/" + src_path.name
                    tar.add(src_path, arcname=dst_path)
        else:
            src_path = source_dir / file_mapping.src
            if src_path.exists():
                tar.add(src_path, arcname=file_mapping.dst.rstrip("/") + "/" + src_path.name)

    def _add_metadata(self, tar: tarfile.TarFile):
        """Add conda metadata files to the package."""
        import io

        # index.json
        index = {
            "name": self.manifest.name,
            "version": self.manifest.version,
            "build": "py311_0",
            "build_number": 0,
            "depends": self.manifest.get_all_dependencies(),
            "license": self.manifest.license,
            "timestamp": int(os.time() * 1000) if hasattr(os, "time") else 0,
        }

        index_json = json.dumps(index, indent=2).encode()
        info = tarfile.TarInfo(name="info/index.json")
        info.size = len(index_json)
        tar.addfile(info, io.BytesIO(index_json))

        # about.json
        about = {
            "description": self.manifest.description,
            "home": self.manifest.homepage,
            "license": self.manifest.license,
        }

        about_json = json.dumps(about, indent=2).encode()
        info = tarfile.TarInfo(name="info/about.json")
        info.size = len(about_json)
        tar.addfile(info, io.BytesIO(about_json))
