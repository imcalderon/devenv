"""
Tarball exporter for vfx-bootstrap.
"""

import json
import tarfile
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Union

from ..schema import PackageManifest
from .base import Exporter


class TarballExporter(Exporter):
    """
    Export packages to tarball format with manifest.

    Creates a .tar.gz archive with a JSON manifest for version tracking.
    This is a simple, portable format that works on any platform.
    """

    @property
    def format_name(self) -> str:
        return "tarball"

    @property
    def file_extension(self) -> str:
        return ".tar.gz"

    def export(
        self,
        source_dir: Union[str, Path],
        output_dir: Union[str, Path],
        components: Optional[List[str]] = None,
    ) -> Path:
        """
        Export to tarball format with manifest.

        Args:
            source_dir: Directory containing built files.
            output_dir: Directory for output package.
            components: Specific components to include.

        Returns:
            Path to the exported .tar.gz package.
        """
        source_dir = Path(source_dir)
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Validate source
        missing = self.validate_source(source_dir, components)
        if missing:
            raise FileNotFoundError(f"Missing files: {missing}")

        output_file = output_dir / self.get_output_filename()

        # Create tarball
        with tarfile.open(output_file, "w:gz") as tar:
            # Add a top-level directory with package name
            root_dir = f"{self.manifest.name}-{self.manifest.version}"

            # Add files
            files = self.manifest.get_all_files(components)
            file_list = []

            for file_mapping in files:
                added = self._add_files_to_tar(tar, source_dir, file_mapping, root_dir)
                file_list.extend(added)

            # Add manifest
            self._add_manifest(tar, root_dir, file_list)

        return output_file

    def _add_files_to_tar(
        self, tar: tarfile.TarFile, source_dir: Path, file_mapping, root_dir: str
    ) -> List[str]:
        """Add files matching a mapping to the tarball."""
        added_files = []

        if "*" in file_mapping.src:
            for src_path in source_dir.glob(file_mapping.src):
                if src_path.is_file():
                    dst = f"{root_dir}/{file_mapping.dst.rstrip('/')}/{src_path.name}"
                    tar.add(src_path, arcname=dst)
                    added_files.append(dst)
        else:
            src_path = source_dir / file_mapping.src
            if src_path.exists():
                if src_path.is_file():
                    dst = f"{root_dir}/{file_mapping.dst.rstrip('/')}/{src_path.name}"
                    tar.add(src_path, arcname=dst)
                    added_files.append(dst)
                elif src_path.is_dir():
                    for item in src_path.rglob("*"):
                        if item.is_file():
                            rel = item.relative_to(src_path)
                            dst = f"{root_dir}/{file_mapping.dst.rstrip('/')}/{rel}"
                            tar.add(item, arcname=dst)
                            added_files.append(dst)

        return added_files

    def _add_manifest(self, tar: tarfile.TarFile, root_dir: str, file_list: List[str]):
        """Add manifest.json to the tarball."""
        import io

        manifest = {
            "name": self.manifest.name,
            "version": self.manifest.version,
            "description": self.manifest.description,
            "license": self.manifest.license,
            "homepage": self.manifest.homepage,
            "dependencies": self.manifest.get_all_dependencies(),
            "files": file_list,
            "created": datetime.utcnow().isoformat() + "Z",
            "format": "vfx-bootstrap-tarball-v1",
        }

        manifest_json = json.dumps(manifest, indent=2).encode()
        info = tarfile.TarInfo(name=f"{root_dir}/manifest.json")
        info.size = len(manifest_json)
        tar.addfile(info, io.BytesIO(manifest_json))
