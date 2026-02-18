# Recipe Porting Guide

This guide explains how to create and port recipes for cross-platform compatibility.

## Recipe Structure

Each recipe lives in its own directory under `recipes/`:

```
recipes/
├── conda_build_config.yaml   # Shared version pins
└── packagename/
    ├── meta.yaml             # Package metadata and dependencies
    ├── build.sh              # Unix build script
    ├── bld.bat               # Windows build script (optional)
    └── patches/              # Source patches (optional)
        └── fix-something.patch
```

## meta.yaml Template

```yaml
{% set name = "packagename" %}
{% set version = "1.2.3" %}

package:
  name: {{ name }}
  version: {{ version }}

source:
  url: https://github.com/org/{{ name }}/archive/v{{ version }}.tar.gz
  sha256: abc123...
  patches:
    - patches/fix-something.patch  # [linux]

build:
  number: 0
  skip: true  # [win]  # Skip Windows until supported
  run_exports:
    - {{ pin_subpackage(name, max_pin='x.x') }}

requirements:
  build:
    - {{ compiler('c') }}
    - {{ compiler('cxx') }}
    - cmake
    - ninja  # [unix]
    - make   # [unix]
  host:
    - python
    - boost
  run:
    - python
    - {{ pin_compatible('boost', max_pin='x.x') }}

test:
  commands:
    - test -f $PREFIX/lib/lib{{ name }}.so       # [linux]
    - test -f $PREFIX/lib/lib{{ name }}.dylib    # [osx]
  imports:
    - {{ name }}  # If Python module

about:
  home: https://github.com/org/{{ name }}
  license: Apache-2.0
  license_file: LICENSE
  summary: Brief description of the package
```

## Platform Selectors

Conda provides selectors for platform-specific configuration:

| Selector | Meaning |
|----------|---------|
| `# [unix]` | Linux and macOS |
| `# [linux]` | Linux only |
| `# [osx]` | macOS only |
| `# [win]` | Windows only |
| `# [x86_64]` | 64-bit x86 |
| `# [arm64]` | ARM64 (Apple Silicon) |

### Examples

```yaml
requirements:
  build:
    - ninja  # [unix]
    - make   # [unix]
    - {{ compiler('c') }}
  host:
    - pthread-stubs  # [linux]

build:
  skip: true  # [win and py<38]
```

## Build Scripts

### build.sh (Unix)

```bash
#!/bin/bash
set -euxo pipefail

# Common variables provided by conda-build:
# $PREFIX - Installation prefix
# $SRC_DIR - Source directory
# $CPU_COUNT - Available CPU cores
# $RECIPE_DIR - Recipe directory

mkdir -p build
cd build

# Platform-specific configuration
CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="$PREFIX"
    -DBUILD_SHARED_LIBS=ON
)

# macOS-specific
if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
        -DCMAKE_INSTALL_RPATH="@loader_path/../lib"
    )
fi

# Linux-specific
if [[ "$OSTYPE" == "linux"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_INSTALL_RPATH="\$ORIGIN/../lib"
    )
fi

cmake "${CMAKE_ARGS[@]}" "$SRC_DIR"
cmake --build . --parallel "$CPU_COUNT"
cmake --install .
```

### bld.bat (Windows)

```batch
@echo off
setlocal enabledelayedexpansion

mkdir build
cd build

cmake -G "Visual Studio 17 2022" -A x64 ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_SHARED_LIBS=ON ^
    "%SRC_DIR%"

cmake --build . --config Release --parallel %CPU_COUNT%
cmake --install . --config Release
```

## Cross-Platform Patterns

### 1. Compiler Abstraction

Always use conda's compiler packages:

```yaml
requirements:
  build:
    - {{ compiler('c') }}
    - {{ compiler('cxx') }}
```

This ensures:
- Correct compiler for each platform
- Consistent ABI
- Proper sysroot on Linux

### 2. Library Paths

Use platform-agnostic path variables:

```yaml
test:
  commands:
    - test -f $PREFIX/lib/libfoo${SHLIB_EXT}  # Works on Linux and macOS
```

| Variable | Linux | macOS | Windows |
|----------|-------|-------|---------|
| `$PREFIX` | Install prefix | Install prefix | N/A |
| `%LIBRARY_PREFIX%` | N/A | N/A | Install prefix |
| `$SHLIB_EXT` | `.so` | `.dylib` | N/A |

### 3. CMake Configuration

Use CMake for consistent cross-platform builds:

```bash
# In build.sh
cmake -DCMAKE_PREFIX_PATH="$PREFIX" \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      "$SRC_DIR"
```

### 4. RPATH Handling

Set proper RPATH for each platform:

```bash
# Linux
-DCMAKE_INSTALL_RPATH="\$ORIGIN/../lib"

# macOS
-DCMAKE_INSTALL_RPATH="@loader_path/../lib"
```

### 5. Dependency Variants

Handle different dependency configurations:

```yaml
requirements:
  host:
    - boost
    - python
    # OpenGL options
    - libgl-devel  # [linux]
    - xorg-libx11  # [linux]
```

## Common Issues and Solutions

### Issue: Package not found on different distro

**Cause**: Different package names across distributions.

**Solution**: Use conda packages, not system packages.

```yaml
# Bad - relies on system
requirements:
  build:
    - libgl1-mesa-dev  # Ubuntu name

# Good - conda package
requirements:
  build:
    - mesa-libgl-devel  # Conda-forge package
```

### Issue: Undefined symbols at runtime

**Cause**: Linking against system libraries instead of conda packages.

**Solution**: Ensure `CMAKE_PREFIX_PATH` includes `$PREFIX`:

```bash
cmake -DCMAKE_PREFIX_PATH="$PREFIX" ...
```

### Issue: Python module import fails

**Cause**: Python path not set correctly.

**Solution**: Use proper install location:

```bash
cmake -DPYTHON_SITE_PACKAGES="$SP_DIR" ...
```

### Issue: OpenGL not found on Linux

**Cause**: Mesa/OpenGL headers missing.

**Solution**: Add mesa dependencies:

```yaml
requirements:
  build:
    - {{ cdt('mesa-libgl-devel') }}  # [linux]
    - {{ cdt('mesa-libegl-devel') }}  # [linux]
```

### Issue: Build works locally but fails in CI

**Cause**: CI uses different base image.

**Solution**: Test in container matching CI environment:

```bash
vfx-bootstrap build --container vfx-build:ubuntu22.04 packagename
```

## Testing Recipes

### Local Testing

```bash
# Build and test
vfx-bootstrap build packagename --test

# Build with verbose output
vfx-bootstrap build packagename --verbose

# Build for specific platform config
vfx-bootstrap build packagename --platform vfx2024
```

### Container Testing

```bash
# Test on Ubuntu
vfx-bootstrap build --container ubuntu:22.04 packagename

# Test on Rocky Linux
vfx-bootstrap build --container rockylinux:8 packagename
```

### Test Section Best Practices

```yaml
test:
  requires:
    - pytest
  source_files:
    - tests/
  commands:
    # Check library exists
    - test -f $PREFIX/lib/libfoo${SHLIB_EXT}
    # Check executable runs
    - foo --version
    # Run tests
    - pytest tests/ -v
  imports:
    # Check Python imports
    - foo
    - foo.submodule
```

## Recipe Checklist

Before submitting a recipe:

- [ ] Builds on Ubuntu 22.04 / WSL
- [ ] Uses `{{ compiler('c') }}` and `{{ compiler('cxx') }}`
- [ ] No hardcoded paths
- [ ] Platform selectors used where needed
- [ ] Test section verifies installation
- [ ] Version pinned in `conda_build_config.yaml`
- [ ] `run_exports` specified for libraries
- [ ] License file included
- [ ] Documentation updated if needed
