"""
Build cache implementation for vfx-bootstrap.

Provides caching of built packages to avoid redundant builds.
"""

import hashlib
import json
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Union


class BuildCache:
    """
    Cache of built conda packages.

    Stores built packages keyed by a hash of the build inputs
    (recipe, config, dependencies).
    """

    def __init__(self, cache_dir: Union[str, Path]):
        """
        Initialize the cache.

        Args:
            cache_dir: Root directory for the cache.
        """
        self.root = Path(cache_dir).resolve()
        self.cache = self.root / "packages"
        self.metadata = self.root / "metadata"
        self.tmp = self.root / "tmp"

        # Create directories
        self.cache.mkdir(parents=True, exist_ok=True)
        self.metadata.mkdir(parents=True, exist_ok=True)
        self.tmp.mkdir(parents=True, exist_ok=True)

    def get(self, key: str) -> Optional[List[Path]]:
        """
        Get cached packages for a key.

        Args:
            key: Cache key (hash string).

        Returns:
            List of cached package paths, or None if not cached.
        """
        cache_entry = self.cache / key
        if not cache_entry.exists():
            return None

        # Read metadata
        meta_file = self.metadata / f"{key}.json"
        if not meta_file.exists():
            return None

        try:
            with open(meta_file) as f:
                meta = json.load(f)

            # Verify all packages exist
            packages = []
            for pkg_info in meta.get("packages", []):
                pkg_path = cache_entry / pkg_info["filename"]
                if pkg_path.exists():
                    packages.append(pkg_path)
                else:
                    # Cache entry is incomplete
                    return None

            return packages if packages else None

        except (json.JSONDecodeError, KeyError):
            return None

    def put(self, key: str, packages: List[Path], metadata: Optional[dict] = None) -> None:
        """
        Store packages in the cache.

        Args:
            key: Cache key (hash string).
            packages: List of package paths to cache.
            metadata: Optional additional metadata.
        """
        cache_entry = self.cache / key
        cache_entry.mkdir(parents=True, exist_ok=True)

        # Copy packages to cache
        pkg_info = []
        for pkg_path in packages:
            if pkg_path.exists():
                dest = cache_entry / pkg_path.name
                shutil.copy2(pkg_path, dest)
                pkg_info.append(
                    {
                        "filename": pkg_path.name,
                        "size": pkg_path.stat().st_size,
                        "md5": self._compute_md5(pkg_path),
                    }
                )

        # Write metadata
        meta = {"key": key, "packages": pkg_info, **(metadata or {})}
        meta_file = self.metadata / f"{key}.json"
        with open(meta_file, "w") as f:
            json.dump(meta, f, indent=2)

    def delete(self, key: str) -> bool:
        """
        Delete a cache entry.

        Args:
            key: Cache key to delete.

        Returns:
            True if entry was deleted, False if not found.
        """
        cache_entry = self.cache / key
        meta_file = self.metadata / f"{key}.json"

        deleted = False
        if cache_entry.exists():
            shutil.rmtree(cache_entry)
            deleted = True
        if meta_file.exists():
            meta_file.unlink()
            deleted = True

        return deleted

    def clear(self) -> int:
        """
        Clear all cache entries.

        Returns:
            Number of entries cleared.
        """
        count = 0
        for entry in self.cache.iterdir():
            if entry.is_dir():
                shutil.rmtree(entry)
                count += 1
        for meta_file in self.metadata.glob("*.json"):
            meta_file.unlink()

        return count

    def status(self) -> dict:
        """
        Get cache status information.

        Returns:
            Dictionary with cache statistics.
        """
        entries = list(self.cache.iterdir())
        total_size = sum(
            f.stat().st_size for entry in entries for f in entry.glob("**/*") if f.is_file()
        )

        return {
            "cache_dir": str(self.root),
            "num_entries": len(entries),
            "total_size_bytes": total_size,
            "total_size_mb": total_size / (1024 * 1024),
        }

    def list_entries(self) -> List[dict]:
        """
        List all cache entries.

        Returns:
            List of entry metadata dictionaries.
        """
        entries = []
        for meta_file in self.metadata.glob("*.json"):
            try:
                with open(meta_file) as f:
                    meta = json.load(f)
                entries.append(meta)
            except (json.JSONDecodeError, OSError):
                continue
        return entries

    @staticmethod
    def _compute_md5(file_path: Path) -> str:
        """Compute MD5 hash of a file."""
        hasher = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hasher.update(chunk)
        return hasher.hexdigest()


def compute_config_hash(
    recipe_dir: Path, config: dict, dependencies: Optional[Dict[str, str]] = None
) -> str:
    """
    Compute a cache key hash for a build configuration.

    Args:
        recipe_dir: Path to the recipe directory.
        config: Build configuration dictionary.
        dependencies: Dictionary of dependency package hashes.

    Returns:
        MD5 hash string.
    """
    hasher = hashlib.md5()

    # Hash recipe files
    for file_path in sorted(recipe_dir.glob("**/*")):
        if file_path.is_file():
            hasher.update(file_path.name.encode())
            hasher.update(file_path.read_bytes())

    # Hash config
    hasher.update(json.dumps(config, sort_keys=True).encode())

    # Hash dependencies
    if dependencies:
        for dep_name, dep_hash in sorted(dependencies.items()):
            hasher.update(f"{dep_name}:{dep_hash}".encode())

    return hasher.hexdigest()
