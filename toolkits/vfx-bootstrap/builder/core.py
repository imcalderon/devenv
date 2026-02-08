"""
Core build orchestration for vfx-bootstrap.

Manages the build process for VFX Platform packages using conda-build.
"""

import datetime
import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Set, Union

import yaml

from .cache import BuildCache


class BuildResult:
    """Result of a package build."""

    def __init__(
        self,
        recipe: str,
        success: bool,
        outputs: List[Path] = None,
        log_file: Optional[Path] = None,
        cached: bool = False,
        error: Optional[str] = None,
    ):
        self.recipe = recipe
        self.success = success
        self.outputs = outputs or []
        self.log_file = log_file
        self.cached = cached
        self.error = error

    def __repr__(self):
        status = "cached" if self.cached else ("success" if self.success else "failed")
        return f"BuildResult({self.recipe}, {status})"


class VFXBuilder:
    """
    Build orchestration for VFX Platform packages.

    Manages the build process including dependency resolution, caching,
    and conda-build invocation.
    """

    def __init__(
        self,
        recipes_dir: Union[str, Path],
        output_dir: Union[str, Path],
        cache_dir: Optional[Union[str, Path]] = None,
        log_dir: Optional[Union[str, Path]] = None,
        platform: str = "vfx2024",
        channels: Optional[List[str]] = None,
    ):
        """
        Initialize the builder.

        Args:
            recipes_dir: Directory containing recipe folders.
            output_dir: Directory for built packages.
            cache_dir: Directory for build cache (optional).
            log_dir: Directory for build logs (optional).
            platform: VFX Platform target (e.g., "vfx2024").
            channels: Additional conda channels.
        """
        self.recipes_dir = Path(recipes_dir).resolve()
        self.output_dir = Path(output_dir).resolve()
        self.platform = platform

        # Set up cache
        if cache_dir:
            self.cache_dir = Path(cache_dir).resolve()
            self.cache = BuildCache(self.cache_dir)
        else:
            self.cache_dir = None
            self.cache = None

        # Set up logging
        if log_dir:
            self.log_dir = Path(log_dir).resolve()
        else:
            self.log_dir = self.output_dir / "logs"
        self.log_dir.mkdir(parents=True, exist_ok=True)

        # Channels for dependency resolution
        self.channels = channels or ["conda-forge"]

        # Load VFX Platform configuration
        self.config = self._load_platform_config()

        # Discover available recipes
        self.recipes = self._discover_recipes()

        # Build dependency graph
        self.dependencies = self._build_dependency_graph()

    def _load_platform_config(self) -> dict:
        """Load VFX Platform version configuration."""
        config_file = self.recipes_dir / "conda_build_config.yaml"
        if config_file.exists():
            with open(config_file) as f:
                return yaml.safe_load(f)
        return {}

    def _discover_recipes(self) -> Dict[str, Path]:
        """Discover all available recipes."""
        recipes = {}
        for item in self.recipes_dir.iterdir():
            if item.is_dir():
                meta_yaml = item / "meta.yaml"
                if meta_yaml.exists():
                    recipes[item.name] = item
        return recipes

    def _build_dependency_graph(self) -> Dict[str, Set[str]]:
        """Build dependency graph from recipes."""
        dependencies = {}
        for name, recipe_dir in self.recipes.items():
            deps = self._parse_recipe_dependencies(recipe_dir)
            dependencies[name] = deps
        return dependencies

    def _parse_recipe_dependencies(self, recipe_dir: Path) -> Set[str]:
        """Parse dependencies from a recipe's meta.yaml."""
        meta_yaml = recipe_dir / "meta.yaml"
        if not meta_yaml.exists():
            return set()

        # Simple parsing - in production would use conda-build's render
        deps = set()
        try:
            with open(meta_yaml) as f:
                content = f.read()
                # Look for common dependency patterns
                for line in content.split("\n"):
                    line = line.strip()
                    if line.startswith("- ") and not line.startswith("- {{"):
                        # Extract package name (before version specifier)
                        pkg = line[2:].split()[0].split(">")[0].split("<")[0].split("=")[0]
                        if pkg in self.recipes:
                            deps.add(pkg)
        except Exception:
            pass
        return deps

    def resolve_build_order(self, targets: Optional[List[str]] = None) -> List[str]:
        """
        Resolve build order respecting dependencies.

        Args:
            targets: Specific recipes to build (None = all).

        Returns:
            List of recipe names in build order.
        """
        if targets is None:
            targets = list(self.recipes.keys())

        # Topological sort
        visited = set()
        order = []

        def visit(recipe: str):
            if recipe in visited:
                return
            visited.add(recipe)
            for dep in self.dependencies.get(recipe, set()):
                if dep in targets or dep in self.recipes:
                    visit(dep)
            order.append(recipe)

        for target in targets:
            visit(target)

        return order

    def build(
        self,
        recipe: str,
        use_cache: bool = True,
        verbose: bool = True,
    ) -> BuildResult:
        """
        Build a single recipe.

        Args:
            recipe: Recipe name to build.
            use_cache: Whether to check build cache.
            verbose: Whether to show build output.

        Returns:
            BuildResult with build status.
        """
        if recipe not in self.recipes:
            return BuildResult(recipe=recipe, success=False, error=f"Recipe '{recipe}' not found")

        recipe_dir = self.recipes[recipe]
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        log_file = self.log_dir / f"{recipe}-{timestamp}.log"

        # Check cache first
        if use_cache and self.cache:
            cache_key = self._compute_cache_key(recipe)
            cached_result = self.cache.get(cache_key)
            if cached_result:
                print(f"[CACHED] {recipe}")
                return BuildResult(recipe=recipe, success=True, outputs=cached_result, cached=True)

        print(f"[BUILD] {recipe}")

        # Build channels argument
        channel_args = []
        for channel in self.channels:
            channel_args.extend(["-c", channel])

        # Include output directory as channel for dependencies
        channel_args.extend(["-c", str(self.output_dir)])

        # Build command
        cmd = [
            "conda",
            "build",
            str(recipe_dir),
            *channel_args,
            "--override-channels",
            "--output-folder",
            str(self.output_dir),
        ]

        # Add variant config if exists
        variant_file = self.recipes_dir / "conda_build_config.yaml"
        if variant_file.exists():
            cmd.extend(["--variant-config-files", str(variant_file)])

        if verbose:
            print(f"[CMD] {' '.join(cmd)}")

        try:
            with open(log_file, "w") as log:
                process = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE if not verbose else None,
                    stderr=subprocess.STDOUT if not verbose else None,
                    text=True,
                    env=self._build_env(),
                )

                if not verbose and process.stdout:
                    log.write(process.stdout)

            if process.returncode == 0:
                outputs = self._find_build_outputs(recipe)

                # Store in cache
                if self.cache:
                    cache_key = self._compute_cache_key(recipe)
                    self.cache.put(cache_key, outputs)

                return BuildResult(recipe=recipe, success=True, outputs=outputs, log_file=log_file)
            else:
                return BuildResult(
                    recipe=recipe,
                    success=False,
                    log_file=log_file,
                    error=f"Build failed with exit code {process.returncode}",
                )

        except Exception as e:
            return BuildResult(recipe=recipe, success=False, log_file=log_file, error=str(e))

    def build_all(
        self,
        targets: Optional[List[str]] = None,
        use_cache: bool = True,
        verbose: bool = True,
        continue_on_error: bool = False,
    ) -> List[BuildResult]:
        """
        Build all specified packages in dependency order.

        Args:
            targets: Specific recipes to build (None = all).
            use_cache: Whether to check build cache.
            verbose: Whether to show build output.
            continue_on_error: Continue building after failures.

        Returns:
            List of BuildResults for all builds.
        """
        build_order = self.resolve_build_order(targets)

        print(f"\nBuild plan ({len(build_order)} packages):")
        for i, recipe in enumerate(build_order, 1):
            print(f"  {i}. {recipe}")
        print()

        results = []
        for recipe in build_order:
            result = self.build(recipe, use_cache=use_cache, verbose=verbose)
            results.append(result)

            if not result.success and not continue_on_error:
                print(f"\nBuild failed for {recipe}. Stopping.")
                break

        # Print summary
        print("\n" + "=" * 50)
        print("Build Summary")
        print("=" * 50)
        success_count = sum(1 for r in results if r.success)
        cached_count = sum(1 for r in results if r.cached)
        failed_count = sum(1 for r in results if not r.success)

        print(f"  Success: {success_count} (cached: {cached_count})")
        print(f"  Failed:  {failed_count}")

        if failed_count > 0:
            print("\nFailed packages:")
            for r in results:
                if not r.success:
                    print(f"  - {r.recipe}: {r.error}")

        return results

    def _build_env(self) -> dict:
        """Create environment for build subprocess."""
        env = os.environ.copy()
        # Add any VFX-specific environment variables
        return env

    def _compute_cache_key(self, recipe: str) -> str:
        """Compute cache key for a recipe."""
        # Simple key based on recipe name and config
        # In production, would include source hash, dependency hashes, etc.
        import hashlib

        key_data = f"{recipe}:{self.platform}:{yaml.dump(self.config)}"
        return hashlib.md5(key_data.encode()).hexdigest()

    def _find_build_outputs(self, recipe: str) -> List[Path]:
        """Find output packages for a recipe."""
        outputs = []
        for subdir in ["linux-64", "osx-64", "osx-arm64", "noarch"]:
            pkg_dir = self.output_dir / subdir
            if pkg_dir.exists():
                for pkg in pkg_dir.glob(f"{recipe}*.conda"):
                    outputs.append(pkg)
                for pkg in pkg_dir.glob(f"{recipe}*.tar.bz2"):
                    outputs.append(pkg)
        return outputs

    def list_recipes(self) -> List[str]:
        """List all available recipes."""
        return sorted(self.recipes.keys())

    def get_recipe_info(self, recipe: str) -> dict:
        """Get information about a recipe."""
        if recipe not in self.recipes:
            return {"error": f"Recipe '{recipe}' not found"}

        recipe_dir = self.recipes[recipe]
        meta_yaml = recipe_dir / "meta.yaml"

        info = {
            "name": recipe,
            "path": str(recipe_dir),
            "dependencies": list(self.dependencies.get(recipe, set())),
        }

        if meta_yaml.exists():
            info["has_meta_yaml"] = True
        else:
            info["has_meta_yaml"] = False

        return info
