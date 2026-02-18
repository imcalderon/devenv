"""
Tests for the vfx-bootstrap packager module.
"""

import tempfile
from pathlib import Path

import pytest


class TestPackageManifest:
    """Tests for PackageManifest class."""

    def test_import(self):
        """Test that packager module can be imported."""
        from packager.schema import PackageManifest

        assert PackageManifest is not None

    def test_create_manifest(self):
        """Test creating a manifest."""
        from packager.schema import Component, FileMapping, PackageManifest

        manifest = PackageManifest(
            name="test-package",
            version="1.0.0",
            description="Test package",
            license="Apache-2.0",
        )

        assert manifest.name == "test-package"
        assert manifest.version == "1.0.0"

    def test_to_yaml(self):
        """Test YAML serialization."""
        from packager.schema import PackageManifest

        manifest = PackageManifest(name="test", version="1.0", description="Test")

        yaml_str = manifest.to_yaml()
        assert "name: test" in yaml_str
        assert "version: '1.0'" in yaml_str or "version: 1.0" in yaml_str

    def test_from_yaml(self):
        """Test YAML deserialization."""
        from packager.schema import PackageManifest

        yaml_str = """
name: test-package
version: "2.0.0"
description: Test package
license: MIT
"""
        manifest = PackageManifest.from_yaml(yaml_str)
        assert manifest.name == "test-package"
        assert manifest.version == "2.0.0"
        assert manifest.license == "MIT"

    def test_save_and_load(self, tmp_path):
        """Test saving and loading manifest."""
        from packager.schema import PackageManifest

        manifest = PackageManifest(name="test", version="1.0.0", description="Test")

        file_path = tmp_path / "manifest.yaml"
        manifest.save(file_path)

        loaded = PackageManifest.load(file_path)
        assert loaded.name == manifest.name
        assert loaded.version == manifest.version

    def test_components(self):
        """Test manifest with components."""
        from packager.schema import Component, FileMapping, PackageManifest

        manifest = PackageManifest(
            name="test",
            version="1.0",
            components=[
                Component(
                    name="core",
                    files=[
                        FileMapping(src="bin/test", dst="bin/"),
                    ],
                    dependencies=["dep1", "dep2"],
                ),
                Component(name="optional", optional=True, dependencies=["dep3"]),
            ],
        )

        # Test get_all_dependencies
        all_deps = manifest.get_all_dependencies()
        assert "dep1" in all_deps
        assert "dep2" in all_deps
        assert "dep3" not in all_deps  # optional component excluded by default

        # Test with specific components
        deps_with_optional = manifest.get_all_dependencies(["core", "optional"])
        assert "dep3" in deps_with_optional


class TestExporters:
    """Tests for package exporters."""

    def test_tarball_exporter(self, tmp_path):
        """Test tarball exporter."""
        from packager.exporters import TarballExporter
        from packager.schema import Component, FileMapping, PackageManifest

        # Create source files
        source_dir = tmp_path / "source"
        source_dir.mkdir()
        (source_dir / "bin").mkdir()
        (source_dir / "bin" / "test").write_text("#!/bin/bash\necho test")

        # Create manifest
        manifest = PackageManifest(
            name="test-pkg",
            version="1.0.0",
            components=[
                Component(
                    name="core",
                    files=[
                        FileMapping(src="bin/test", dst="bin/", executable=True),
                    ],
                )
            ],
        )

        # Export
        output_dir = tmp_path / "output"
        exporter = TarballExporter(manifest)
        result = exporter.export(source_dir, output_dir)

        assert result.exists()
        assert result.suffix == ".gz"

    def test_archive_exporter(self, tmp_path):
        """Test ZIP archive exporter."""
        from packager.exporters import ArchiveExporter
        from packager.schema import Component, FileMapping, PackageManifest

        # Create source files
        source_dir = tmp_path / "source"
        source_dir.mkdir()
        (source_dir / "lib").mkdir()
        (source_dir / "lib" / "test.txt").write_text("test content")

        # Create manifest
        manifest = PackageManifest(
            name="test-pkg",
            version="1.0.0",
            components=[
                Component(
                    name="core",
                    files=[
                        FileMapping(src="lib/test.txt", dst="lib/"),
                    ],
                )
            ],
        )

        # Export
        output_dir = tmp_path / "output"
        exporter = ArchiveExporter(manifest)
        result = exporter.export(source_dir, output_dir)

        assert result.exists()
        assert result.suffix == ".zip"

    def test_validate_source(self, tmp_path):
        """Test source validation."""
        from packager.exporters import TarballExporter
        from packager.schema import Component, FileMapping, PackageManifest

        # Create manifest requiring files that don't exist
        manifest = PackageManifest(
            name="test",
            version="1.0",
            components=[
                Component(
                    name="core",
                    files=[
                        FileMapping(src="missing/file.txt", dst="data/"),
                    ],
                )
            ],
        )

        source_dir = tmp_path / "empty"
        source_dir.mkdir()

        exporter = TarballExporter(manifest)
        missing = exporter.validate_source(source_dir)

        assert len(missing) > 0
        assert "missing/file.txt" in missing
