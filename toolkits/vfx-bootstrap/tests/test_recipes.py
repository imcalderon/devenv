"""
Tests for recipe validation.
"""

import os
from pathlib import Path

import pytest
import yaml

RECIPES_DIR = Path(__file__).parent.parent / "recipes"


def get_recipe_dirs():
    """Get all recipe directories."""
    if not RECIPES_DIR.exists():
        return []
    return [d for d in RECIPES_DIR.iterdir() if d.is_dir() and (d / "meta.yaml").exists()]


class TestRecipeStructure:
    """Tests for recipe structure and validity."""

    @pytest.mark.parametrize("recipe_dir", get_recipe_dirs(), ids=lambda d: d.name)
    def test_recipe_has_meta_yaml(self, recipe_dir):
        """Test that each recipe has a meta.yaml file."""
        meta_yaml = recipe_dir / "meta.yaml"
        assert meta_yaml.exists(), f"Recipe {recipe_dir.name} missing meta.yaml"

    @pytest.mark.parametrize("recipe_dir", get_recipe_dirs(), ids=lambda d: d.name)
    def test_recipe_meta_yaml_valid(self, recipe_dir):
        """Test that meta.yaml is valid YAML (basic syntax check)."""
        meta_yaml = recipe_dir / "meta.yaml"
        content = meta_yaml.read_text()

        # Remove Jinja2 templating for basic YAML parsing
        # Remove entire lines with {% ... %} (set statements, conditionals)
        lines = []
        for line in content.split("\n"):
            stripped = line.strip()
            if stripped.startswith("{%") and stripped.endswith("%}"):
                continue  # Skip Jinja2 control lines entirely
            lines.append(line)
        content = "\n".join(lines)

        # Replace remaining inline Jinja2 expressions
        content = content.replace("{{", "").replace("}}", "")

        try:
            yaml.safe_load(content)
        except yaml.YAMLError as e:
            pytest.fail(f"Invalid YAML in {recipe_dir.name}/meta.yaml: {e}")

    @pytest.mark.parametrize("recipe_dir", get_recipe_dirs(), ids=lambda d: d.name)
    def test_recipe_has_build_script(self, recipe_dir):
        """Test that each recipe has at least one build script."""
        build_sh = recipe_dir / "build.sh"
        bld_bat = recipe_dir / "bld.bat"

        assert (
            build_sh.exists() or bld_bat.exists()
        ), f"Recipe {recipe_dir.name} missing build script (build.sh or bld.bat)"

    @pytest.mark.parametrize("recipe_dir", get_recipe_dirs(), ids=lambda d: d.name)
    def test_build_sh_syntax(self, recipe_dir):
        """Test that build.sh has valid bash syntax."""
        build_sh = recipe_dir / "build.sh"
        if not build_sh.exists():
            pytest.skip("No build.sh")

        import subprocess

        result = subprocess.run(["bash", "-n", str(build_sh)], capture_output=True, text=True)
        assert (
            result.returncode == 0
        ), f"Syntax error in {recipe_dir.name}/build.sh: {result.stderr}"


class TestCondaBuildConfig:
    """Tests for conda_build_config.yaml."""

    def test_config_exists(self):
        """Test that conda_build_config.yaml exists."""
        config_file = RECIPES_DIR / "conda_build_config.yaml"
        assert config_file.exists(), "Missing conda_build_config.yaml"

    def test_config_valid_yaml(self):
        """Test that config file is valid YAML."""
        config_file = RECIPES_DIR / "conda_build_config.yaml"
        if not config_file.exists():
            pytest.skip("No config file")

        content = config_file.read_text()
        # Remove platform selectors for YAML parsing
        content = "\n".join(
            line.split("#")[0] if "#" in line and "[" in line else line
            for line in content.split("\n")
        )

        try:
            config = yaml.safe_load(content)
            assert config is not None
        except yaml.YAMLError as e:
            pytest.fail(f"Invalid YAML in conda_build_config.yaml: {e}")

    def test_config_has_required_versions(self):
        """Test that config has VFX Platform 2024 versions."""
        config_file = RECIPES_DIR / "conda_build_config.yaml"
        if not config_file.exists():
            pytest.skip("No config file")

        content = config_file.read_text()
        content = "\n".join(
            line.split("#")[0] if "#" in line and "[" in line else line
            for line in content.split("\n")
        )

        config = yaml.safe_load(content)

        # Check for key VFX Platform 2024 versions
        assert "python" in config, "Missing python version"
        assert "3.11" in str(config["python"]), "Python should be 3.11 for VFX 2024"

        assert "boost" in config, "Missing boost version"
        assert "tbb" in config, "Missing tbb version"
