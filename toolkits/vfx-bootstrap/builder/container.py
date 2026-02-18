"""
Container support for vfx-bootstrap builds.

Provides Docker/Podman integration for isolated, reproducible builds.
"""

import os
import subprocess
from pathlib import Path
from typing import List, Optional, Union


class ContainerBuilder:
    """
    Build packages inside containers for isolation and reproducibility.

    Supports Docker and Podman runtimes.
    """

    # Pre-configured build images
    IMAGES = {
        "ubuntu22": "ubuntu:22.04",
        "rocky8": "rockylinux:8",
        "rocky9": "rockylinux:9",
    }

    def __init__(self, runtime: str = "auto", default_image: str = "ubuntu22"):
        """
        Initialize container builder.

        Args:
            runtime: Container runtime ("docker", "podman", or "auto").
            default_image: Default build image key or full image name.
        """
        self.runtime = self._detect_runtime(runtime)
        self.default_image = self._resolve_image(default_image)

    def _detect_runtime(self, runtime: str) -> str:
        """Detect available container runtime."""
        if runtime != "auto":
            return runtime

        # Prefer podman if available (rootless)
        for cmd in ["podman", "docker"]:
            try:
                subprocess.run([cmd, "--version"], capture_output=True, check=True)
                return cmd
            except (subprocess.CalledProcessError, FileNotFoundError):
                continue

        raise RuntimeError("No container runtime found (docker or podman)")

    def _resolve_image(self, image: str) -> str:
        """Resolve image key to full image name."""
        return self.IMAGES.get(image, image)

    def is_available(self) -> bool:
        """Check if container runtime is available."""
        try:
            subprocess.run([self.runtime, "info"], capture_output=True, check=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    def pull_image(self, image: Optional[str] = None) -> bool:
        """
        Pull a container image.

        Args:
            image: Image to pull (default: default_image).

        Returns:
            True if successful.
        """
        image = self._resolve_image(image) if image else self.default_image

        print(f"Pulling image: {image}")
        try:
            subprocess.run([self.runtime, "pull", image], check=True)
            return True
        except subprocess.CalledProcessError:
            return False

    def build_in_container(
        self,
        recipe_dir: Union[str, Path],
        output_dir: Union[str, Path],
        image: Optional[str] = None,
        volumes: Optional[List[str]] = None,
        environment: Optional[dict] = None,
        user: Optional[str] = None,
    ) -> subprocess.CompletedProcess:
        """
        Run a build inside a container.

        Args:
            recipe_dir: Recipe directory to mount.
            output_dir: Output directory for packages.
            image: Container image to use.
            volumes: Additional volume mounts.
            environment: Environment variables.
            user: User to run as inside container.

        Returns:
            CompletedProcess result.
        """
        recipe_dir = Path(recipe_dir).resolve()
        output_dir = Path(output_dir).resolve()
        image = self._resolve_image(image) if image else self.default_image

        # Ensure output directory exists
        output_dir.mkdir(parents=True, exist_ok=True)

        # Build command
        cmd = [
            self.runtime,
            "run",
            "--rm",
            "-v",
            f"{recipe_dir}:/recipe:ro",
            "-v",
            f"{output_dir}:/output:rw",
        ]

        # Add additional volumes
        if volumes:
            for vol in volumes:
                cmd.extend(["-v", vol])

        # Add environment variables
        if environment:
            for key, value in environment.items():
                cmd.extend(["-e", f"{key}={value}"])

        # Set user if specified
        if user:
            cmd.extend(["--user", user])
        else:
            # Run as current user to avoid permission issues
            cmd.extend(["--user", f"{os.getuid()}:{os.getgid()}"])

        # Image and command
        cmd.append(image)
        cmd.extend(
            [
                "conda",
                "build",
                "/recipe",
                "--output-folder",
                "/output",
                "-c",
                "conda-forge",
                "--override-channels",
            ]
        )

        print(f"Running build in container: {image}")
        return subprocess.run(cmd)

    def run_shell(
        self,
        image: Optional[str] = None,
        volumes: Optional[List[str]] = None,
        workdir: Optional[str] = None,
    ) -> None:
        """
        Start an interactive shell in a container.

        Args:
            image: Container image to use.
            volumes: Volume mounts.
            workdir: Working directory inside container.
        """
        image = self._resolve_image(image) if image else self.default_image

        cmd = [
            self.runtime,
            "run",
            "--rm",
            "-it",
        ]

        if volumes:
            for vol in volumes:
                cmd.extend(["-v", vol])

        if workdir:
            cmd.extend(["-w", workdir])

        cmd.extend([image, "/bin/bash"])

        subprocess.run(cmd)

    def create_build_image(
        self,
        name: str,
        base_image: str = "ubuntu:22.04",
        packages: Optional[List[str]] = None,
    ) -> bool:
        """
        Create a custom build image with conda pre-installed.

        Args:
            name: Name for the new image.
            base_image: Base image to build from.
            packages: Additional packages to install.

        Returns:
            True if successful.
        """
        packages = packages or []

        # Create Dockerfile content
        dockerfile_content = f"""
FROM {base_image}

# Install base dependencies
RUN apt-get update && apt-get install -y \\
    curl \\
    wget \\
    git \\
    build-essential \\
    && rm -rf /var/lib/apt/lists/*

# Install Miniforge
RUN curl -fsSL https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -o /tmp/miniforge.sh && \\
    bash /tmp/miniforge.sh -b -p /opt/conda && \\
    rm /tmp/miniforge.sh

# Set up conda
ENV PATH=/opt/conda/bin:$PATH
RUN conda config --set auto_activate_base false && \\
    conda config --add channels conda-forge && \\
    conda config --set channel_priority strict

# Install build tools
RUN conda install -y conda-build conda-verify

# Install additional packages
{f'RUN conda install -y {" ".join(packages)}' if packages else ''}

WORKDIR /build
"""

        # Write temporary Dockerfile
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            dockerfile_path = Path(tmpdir) / "Dockerfile"
            dockerfile_path.write_text(dockerfile_content)

            try:
                subprocess.run(
                    [self.runtime, "build", "-t", name, "-f", str(dockerfile_path), tmpdir],
                    check=True,
                )
                print(f"Created build image: {name}")
                return True
            except subprocess.CalledProcessError:
                print(f"Failed to create image: {name}")
                return False

    def status(self) -> dict:
        """
        Get container runtime status.

        Returns:
            Dictionary with status information.
        """
        info = {
            "runtime": self.runtime,
            "available": self.is_available(),
            "default_image": self.default_image,
        }

        if info["available"]:
            # Get runtime version
            try:
                result = subprocess.run([self.runtime, "--version"], capture_output=True, text=True)
                info["version"] = result.stdout.strip()
            except Exception:
                info["version"] = "unknown"

        return info
