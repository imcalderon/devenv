"""
Tests for the vfx-bootstrap builder module.
"""

import tempfile
from pathlib import Path

import pytest


class TestVFXBuilder:
    """Tests for VFXBuilder class."""

    def test_import(self):
        """Test that builder module can be imported."""
        from builder import VFXBuilder

        assert VFXBuilder is not None

    def test_init_with_recipes_dir(self, tmp_path):
        """Test builder initialization with recipes directory."""
        from builder import VFXBuilder

        # Create minimal recipe structure
        recipes_dir = tmp_path / "recipes"
        recipes_dir.mkdir()

        boost_dir = recipes_dir / "boost"
        boost_dir.mkdir()
        (boost_dir / "meta.yaml").write_text("package:\n  name: boost\n  version: 1.82")

        output_dir = tmp_path / "output"

        builder = VFXBuilder(recipes_dir=recipes_dir, output_dir=output_dir, platform="vfx2024")

        assert builder.recipes_dir == recipes_dir
        assert builder.platform == "vfx2024"
        assert "boost" in builder.recipes

    def test_list_recipes(self, tmp_path):
        """Test listing available recipes."""
        from builder import VFXBuilder

        recipes_dir = tmp_path / "recipes"
        recipes_dir.mkdir()

        for name in ["boost", "tbb", "openexr"]:
            recipe_dir = recipes_dir / name
            recipe_dir.mkdir()
            (recipe_dir / "meta.yaml").write_text(f"package:\n  name: {name}")

        builder = VFXBuilder(recipes_dir=recipes_dir, output_dir=tmp_path / "output")

        recipes = builder.list_recipes()
        assert len(recipes) == 3
        assert "boost" in recipes
        assert "tbb" in recipes
        assert "openexr" in recipes

    def test_resolve_build_order(self, tmp_path):
        """Test build order resolution."""
        from builder import VFXBuilder

        recipes_dir = tmp_path / "recipes"
        recipes_dir.mkdir()

        # Create recipes with dependencies
        (recipes_dir / "base").mkdir()
        (recipes_dir / "base" / "meta.yaml").write_text("package:\n  name: base")

        (recipes_dir / "lib").mkdir()
        (recipes_dir / "lib" / "meta.yaml").write_text(
            "package:\n  name: lib\nrequirements:\n  host:\n    - base"
        )

        builder = VFXBuilder(recipes_dir=recipes_dir, output_dir=tmp_path / "output")

        order = builder.resolve_build_order(["lib", "base"])
        assert order.index("base") < order.index("lib")


class TestBuildCache:
    """Tests for BuildCache class."""

    def test_import(self):
        """Test that cache module can be imported."""
        from builder import BuildCache

        assert BuildCache is not None

    def test_init(self, tmp_path):
        """Test cache initialization."""
        from builder import BuildCache

        cache_dir = tmp_path / "cache"
        cache = BuildCache(cache_dir)

        assert cache.root == cache_dir
        assert cache.cache.exists()
        assert cache.metadata.exists()

    def test_put_and_get(self, tmp_path):
        """Test storing and retrieving from cache."""
        from builder import BuildCache

        cache_dir = tmp_path / "cache"
        cache = BuildCache(cache_dir)

        # Create a test package
        pkg_dir = tmp_path / "packages"
        pkg_dir.mkdir()
        pkg_file = pkg_dir / "test-1.0-py311_0.tar.bz2"
        pkg_file.write_bytes(b"test package content")

        # Store in cache
        cache.put("test_key_123", [pkg_file])

        # Retrieve from cache
        result = cache.get("test_key_123")
        assert result is not None
        assert len(result) == 1

    def test_status(self, tmp_path):
        """Test cache status."""
        from builder import BuildCache

        cache = BuildCache(tmp_path / "cache")
        status = cache.status()

        assert "cache_dir" in status
        assert "num_entries" in status
        assert "total_size_bytes" in status


class TestContainerBuilder:
    """Tests for ContainerBuilder class."""

    def test_import(self):
        """Test that container module can be imported."""
        from builder import ContainerBuilder

        assert ContainerBuilder is not None

    def test_status(self):
        """Test container status check."""
        from builder import ContainerBuilder

        container = ContainerBuilder()
        status = container.status()

        assert "runtime" in status
        assert "available" in status
        assert "default_image" in status
