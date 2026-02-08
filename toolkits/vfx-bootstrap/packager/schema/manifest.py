"""
Package manifest schema definitions.

Provides a format-agnostic representation of packages that can be
exported to multiple distribution formats.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Union

import yaml


@dataclass
class FileMapping:
    """Mapping of source file to destination in package."""

    src: str
    dst: str
    executable: bool = False
    optional: bool = False

    def to_dict(self) -> dict:
        d = {"src": self.src, "dst": self.dst}
        if self.executable:
            d["executable"] = True
        if self.optional:
            d["optional"] = True
        return d

    @classmethod
    def from_dict(cls, data: dict) -> "FileMapping":
        return cls(
            src=data["src"],
            dst=data["dst"],
            executable=data.get("executable", False),
            optional=data.get("optional", False),
        )


@dataclass
class Component:
    """A component within a package."""

    name: str
    files: List[FileMapping] = field(default_factory=list)
    dependencies: List[str] = field(default_factory=list)
    optional: bool = False
    description: str = ""

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "files": [f.to_dict() for f in self.files],
            "dependencies": self.dependencies,
            "optional": self.optional,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Component":
        return cls(
            name=data["name"],
            files=[FileMapping.from_dict(f) for f in data.get("files", [])],
            dependencies=data.get("dependencies", []),
            optional=data.get("optional", False),
            description=data.get("description", ""),
        )


@dataclass
class PackageManifest:
    """
    Package manifest defining contents and metadata.

    This is a format-agnostic representation that can be exported
    to various distribution formats (conda, tarball, MSI, etc.).
    """

    name: str
    version: str
    description: str = ""
    license: str = ""
    homepage: str = ""
    components: List[Component] = field(default_factory=list)
    metadata: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "version": self.version,
            "description": self.description,
            "license": self.license,
            "homepage": self.homepage,
            "components": [c.to_dict() for c in self.components],
            "metadata": self.metadata,
        }

    def to_yaml(self) -> str:
        return yaml.dump(self.to_dict(), default_flow_style=False, sort_keys=False)

    def save(self, path: Union[str, Path]) -> None:
        path = Path(path)
        path.write_text(self.to_yaml())

    @classmethod
    def from_dict(cls, data: dict) -> "PackageManifest":
        return cls(
            name=data["name"],
            version=data["version"],
            description=data.get("description", ""),
            license=data.get("license", ""),
            homepage=data.get("homepage", ""),
            components=[Component.from_dict(c) for c in data.get("components", [])],
            metadata=data.get("metadata", {}),
        )

    @classmethod
    def from_yaml(cls, yaml_str: str) -> "PackageManifest":
        data = yaml.safe_load(yaml_str)
        return cls.from_dict(data)

    @classmethod
    def load(cls, path: Union[str, Path]) -> "PackageManifest":
        path = Path(path)
        return cls.from_yaml(path.read_text())

    def get_all_dependencies(self, component_names: Optional[List[str]] = None) -> List[str]:
        """Get all unique dependencies for specified components."""
        if component_names is None:
            # All non-optional components
            components = [c for c in self.components if not c.optional]
        else:
            components = [c for c in self.components if c.name in component_names]

        deps = set()
        for comp in components:
            deps.update(comp.dependencies)
        return sorted(deps)

    def get_all_files(self, component_names: Optional[List[str]] = None) -> List[FileMapping]:
        """Get all file mappings for specified components."""
        if component_names is None:
            components = [c for c in self.components if not c.optional]
        else:
            components = [c for c in self.components if c.name in component_names]

        files = []
        for comp in components:
            files.extend(comp.files)
        return files


# Example manifest schema for documentation
EXAMPLE_MANIFEST = """
# Package manifest example
name: usd-tools
version: "24.03"
description: "USD utilities and plugins"
license: Apache-2.0
homepage: https://openusd.org/

components:
  - name: core
    description: Core USD libraries and tools
    files:
      - src: bin/usdcat
        dst: bin/
        executable: true
      - src: bin/usdview
        dst: bin/
        executable: true
      - src: lib/*.so
        dst: lib/
    dependencies:
      - boost >= 1.76
      - tbb >= 2020.3
      - openexr >= 3.0

  - name: python
    description: Python bindings for USD
    optional: true
    files:
      - src: python/pxr/*
        dst: python/pxr/
    dependencies:
      - python >= 3.10

  - name: imaging
    description: Hydra imaging framework
    optional: true
    files:
      - src: lib/libhdx*.so
        dst: lib/
    dependencies:
      - opengl

metadata:
  vfx_platform: "2024"
  build_date: "2024-01-15"
"""
