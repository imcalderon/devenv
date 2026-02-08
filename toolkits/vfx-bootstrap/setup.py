"""
vfx-bootstrap setup script.
"""

from pathlib import Path

from setuptools import find_packages, setup

# Read README
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

setup(
    name="vfx-bootstrap",
    version="0.1.0",
    description="VFX Platform development toolkit for building USD and dependencies",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="Ivan Calderon",
    author_email="",
    url="https://github.com/imcalderon/vfx-bootstrap",
    license="Apache-2.0",
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=">=3.10",
    install_requires=[
        "pyyaml>=6.0",
        "click>=8.0",
        "tqdm>=4.0",
        "requests>=2.28",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0",
            "pytest-cov>=4.0",
            "black>=23.0",
            "isort>=5.0",
            "mypy>=1.0",
            "flake8>=6.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "vfx-bootstrap=builder.cli:main",
            "vfx-package=packager.cli:main",
        ],
    },
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: POSIX :: Linux",
        "Operating System :: MacOS :: MacOS X",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Multimedia :: Graphics :: 3D Modeling",
        "Topic :: Software Development :: Build Tools",
    ],
    keywords="vfx usd openusd pixar pipeline build conda",
)
