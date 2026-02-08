"""
Archive exporter for vfx-bootstrap (ZIP format).
"""

import json
import zipfile
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Union

from ..schema import PackageManifest
from .base import Exporter


class ArchiveExporter(Exporter):
    """
    Export packages to ZIP archive format.

    Creates a .zip archive suitable for Windows distribution
    and easy manual extraction on any platform.
    """

    @property
    def format_name(self) -> str:
        return "archive"

    @property
    def file_extension(self) -> str:
        return ".zip"

    def export(
        self,
        source_dir: Union[str, Path],
        output_dir: Union[str, Path],
        components: Optional[List[str]] = None,
    ) -> Path:
        """
        Export to ZIP archive format.

        Args:
            source_dir: Directory containing built files.
            output_dir: Directory for output package.
            components: Specific components to include.

        Returns:
            Path to the exported .zip archive.
        """
        source_dir = Path(source_dir)
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Validate source
        missing = self.validate_source(source_dir, components)
        if missing:
            raise FileNotFoundError(f"Missing files: {missing}")

        output_file = output_dir / self.get_output_filename()

        # Create ZIP archive
        with zipfile.ZipFile(output_file, "w", zipfile.ZIP_DEFLATED) as zf:
            # Add a top-level directory with package name
            root_dir = f"{self.manifest.name}-{self.manifest.version}"

            # Add files
            files = self.manifest.get_all_files(components)
            file_list = []

            for file_mapping in files:
                added = self._add_files_to_zip(zf, source_dir, file_mapping, root_dir)
                file_list.extend(added)

            # Add manifest
            self._add_manifest(zf, root_dir, file_list)

            # Add README
            self._add_readme(zf, root_dir)

        return output_file

    def _add_files_to_zip(
        self, zf: zipfile.ZipFile, source_dir: Path, file_mapping, root_dir: str
    ) -> List[str]:
        """Add files matching a mapping to the ZIP archive."""
        added_files = []

        if "*" in file_mapping.src:
            for src_path in source_dir.glob(file_mapping.src):
                if src_path.is_file():
                    dst = f"{root_dir}/{file_mapping.dst.rstrip('/')}/{src_path.name}"
                    zf.write(src_path, dst)
                    added_files.append(dst)
        else:
            src_path = source_dir / file_mapping.src
            if src_path.exists():
                if src_path.is_file():
                    dst = f"{root_dir}/{file_mapping.dst.rstrip('/')}/{src_path.name}"
                    zf.write(src_path, dst)
                    added_files.append(dst)
                elif src_path.is_dir():
                    for item in src_path.rglob("*"):
                        if item.is_file():
                            rel = item.relative_to(src_path)
                            dst = f"{root_dir}/{file_mapping.dst.rstrip('/')}/{rel}"
                            zf.write(item, dst)
                            added_files.append(dst)

        return added_files

    def _add_manifest(self, zf: zipfile.ZipFile, root_dir: str, file_list: List[str]):
        """Add manifest.json to the archive."""
        manifest = {
            "name": self.manifest.name,
            "version": self.manifest.version,
            "description": self.manifest.description,
            "license": self.manifest.license,
            "homepage": self.manifest.homepage,
            "dependencies": self.manifest.get_all_dependencies(),
            "files": file_list,
            "created": datetime.utcnow().isoformat() + "Z",
            "format": "vfx-bootstrap-archive-v1",
        }

        manifest_json = json.dumps(manifest, indent=2)
        zf.writestr(f"{root_dir}/manifest.json", manifest_json)

    def _add_readme(self, zf: zipfile.ZipFile, root_dir: str):
        """Add a README file to the archive."""
        readme = f"""# {self.manifest.name} {self.manifest.version}

{self.manifest.description}

## Installation

Extract this archive to your desired installation location.

## Dependencies

This package requires the following dependencies:
{chr(10).join(f"- {dep}" for dep in self.manifest.get_all_dependencies())}

## License

{self.manifest.license}

## More Information

Homepage: {self.manifest.homepage}

---
Packaged with vfx-bootstrap
"""
        zf.writestr(f"{root_dir}/README.txt", readme)
