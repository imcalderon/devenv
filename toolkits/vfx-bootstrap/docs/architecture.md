# vfx-bootstrap Architecture

## System Overview

vfx-bootstrap consists of four main components that work together to take a clean machine to packaged VFX software:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Bootstrap  │───▶│   Builder   │───▶│  Packager   │───▶│  Registry   │
│  (stage0)   │    │   (conda)   │    │  (agnostic) │    │  (catalog)  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

## Component Details

### 1. Bootstrap System (`bootstrap/`)

The bootstrap system prepares a clean machine for building. It's designed to be curl-able and require no pre-installed dependencies.

#### Entry Point: `bootstrap.sh`

```bash
curl -fsSL https://raw.githubusercontent.com/imcalderon/vfx-bootstrap/main/bootstrap/bootstrap.sh | bash
```

**Responsibilities**:
1. Detect the current platform (Ubuntu, Rocky, macOS, etc.)
2. Delegate to platform-specific script
3. Install base dependencies (git, curl)
4. Install Miniforge/conda
5. Clone the vfx-bootstrap repository
6. Set up the initial conda environment

#### Platform Scripts (`bootstrap/platforms/`)

Each platform has specific package names and installation methods:

| Platform | Script | Package Manager |
|----------|--------|-----------------|
| Ubuntu/Debian | `ubuntu.sh` | apt |
| RHEL/Rocky | `rocky.sh` | dnf/yum |
| macOS | `macos.sh` | Homebrew |

#### Modules (`bootstrap/modules/`)

Reusable functions for common setup tasks:

- `conda.sh`: Install and configure Miniforge
- `git.sh`: Install and configure git
- `docker.sh`: Install Docker/Podman for containerized builds

### 2. Builder System (`builder/`)

The builder orchestrates conda-build to compile packages according to VFX Platform specifications.

#### Core Components

**`core.py`** - Build orchestration
```python
class Builder:
    def build(self, recipe: str, platform: str = "vfx2024") -> BuildResult:
        """Build a single recipe."""

    def build_all(self, platform: str = "vfx2024") -> List[BuildResult]:
        """Build all recipes in dependency order."""

    def resolve_dependencies(self, recipe: str) -> List[str]:
        """Determine build order for a recipe and its dependencies."""
```

**`cache.py`** - Build caching
```python
class BuildCache:
    def get(self, recipe: str, config_hash: str) -> Optional[Path]:
        """Retrieve a cached build if available."""

    def put(self, recipe: str, config_hash: str, artifact: Path) -> None:
        """Store a build artifact in the cache."""

    def config_hash(self, recipe: str) -> str:
        """Compute hash of recipe + dependencies + compiler."""
```

**`container.py`** - Container support
```python
class ContainerBuilder:
    def build_in_container(self, recipe: str, image: str) -> BuildResult:
        """Execute build inside a container for isolation."""
```

**`cli.py`** - Command-line interface
```bash
vfx-bootstrap build usd --platform vfx2024
vfx-bootstrap build --all --platform vfx2024
vfx-bootstrap cache status
vfx-bootstrap cache clear
```

#### Build Configuration

VFX Platform versions are defined in `recipes/conda_build_config.yaml`:

```yaml
# VFX Platform 2024
python:
  - "3.11"
boost:
  - "1.82"
tbb:
  - "2020.3"
openexr:
  - "3.2"
# ... etc
```

### 3. Recipe System (`recipes/`)

Cross-platform conda recipes for VFX software.

#### Recipe Structure

Each recipe follows conda-build conventions:

```
recipes/
├── conda_build_config.yaml     # VFX Platform version pins
├── boost/
│   ├── meta.yaml               # Package metadata
│   ├── build.sh                # Unix build script
│   ├── bld.bat                 # Windows build script (future)
│   └── patches/                # Source patches if needed
├── openexr/
│   └── ...
└── usd/
    └── ...
```

#### Cross-Platform Patterns

**Compiler abstraction**:
```yaml
requirements:
  build:
    - {{ compiler('c') }}
    - {{ compiler('cxx') }}
```

**Platform selectors**:
```yaml
requirements:
  build:
    - ninja  # [unix]
    - cmake
  run:
    - __glibc >=2.17  # [linux]
```

**Build script conditionals** (`build.sh`):
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS-specific flags
    CMAKE_ARGS+=(-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15)
fi
```

### 4. Packager System (`packager/`)

Format-agnostic packaging that can export to multiple distribution formats.

#### Package Schema

Inspired by MSI's component model but format-neutral:

```yaml
# packager/schema/package.schema.yaml
name: usd-tools
version: 24.03
description: "USD utilities and plugins"

components:
  - name: core
    files:
      - src: bin/usdview
        dst: bin/
      - src: lib/*.so
        dst: lib/
    dependencies:
      - boost >= 1.76
      - tbb >= 2020.3

  - name: python
    optional: true
    files:
      - src: python/*
        dst: python/
    dependencies:
      - python >= 3.10
```

#### Exporters (`packager/exporters/`)

**`conda.py`** - Conda package format
- Native conda .conda/.tar.bz2 packages
- Metadata in standard conda format
- Integrates with conda channels

**`tarball.py`** - Simple tarball with manifest
- .tar.gz archive
- JSON manifest for version tracking
- Platform-independent

**`archive.py`** - ZIP archives
- For Windows distribution
- Self-extracting option (future)

### 5. Registry System (`registry/`) - Future

Package catalog and distribution server.

#### Planned Features

- Package metadata database
- Version history
- Dependency graph
- Download statistics
- REST API for client queries
- Web UI for browsing

## Data Flow

### Build Flow

```
Recipe (meta.yaml)
    │
    ▼
Builder.resolve_dependencies()
    │
    ▼
For each dependency:
    ├── Check BuildCache
    │   ├── Hit: Use cached artifact
    │   └── Miss: Build with conda-build
    │           │
    │           ▼
    │       Store in BuildCache
    │
    ▼
Final package artifact
```

### Package Flow

```
Build Artifact (conda package)
    │
    ▼
Packager.load_schema()
    │
    ▼
Exporter.export()
    │
    ├── CondaExporter: .conda file
    ├── TarballExporter: .tar.gz + manifest.json
    └── ArchiveExporter: .zip
```

## Configuration Files

| File | Purpose |
|------|---------|
| `recipes/conda_build_config.yaml` | VFX Platform version pins |
| `builder/config.yaml` | Builder settings (cache location, etc.) |
| `packager/schema/package.schema.yaml` | Package manifest schema |

## Extension Points

### Adding a New Platform

1. Create `bootstrap/platforms/newplatform.sh`
2. Update platform detection in `bootstrap/bootstrap.sh`
3. Test bootstrap on the new platform
4. Verify recipes build correctly

### Adding a New Recipe

1. Create `recipes/packagename/meta.yaml`
2. Create `recipes/packagename/build.sh`
3. Test with `vfx-bootstrap build packagename`
4. Document any platform-specific notes

### Adding a New Export Format

1. Create `packager/exporters/newformat.py`
2. Implement the `Exporter` interface
3. Register in CLI
4. Document the format

## Error Handling

### Bootstrap Failures

- Platform detection failures provide manual override instructions
- Network failures retry with exponential backoff
- Partial installations can be resumed

### Build Failures

- Full build logs preserved
- Dependency failures identified clearly
- Suggestions for common issues

### Package Failures

- Validation before export
- Manifest verification
- Rollback on partial failures
