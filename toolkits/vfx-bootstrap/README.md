# vfx-bootstrap

**A complete, open-source toolkit that enables anyone to bootstrap a VFX Platform-compliant development environment from a clean machine and build USD and its dependencies.**

> "I built the CI bridge between Pixar's internal monorepo and OpenUSD's public releases. Here's a toolkit that brings that same build infrastructure to everyone."

## Overview

vfx-bootstrap provides everything needed to go from a fresh machine to a fully-built USD installation with all VFX Platform dependencies. It includes:

- **Bootstrap System**: Single-command setup from a clean machine
- **Build Infrastructure**: Conda-based build orchestration with caching
- **Cross-Platform Recipes**: VFX Platform-compliant build recipes
- **Format-Agnostic Packaging**: Export to multiple distribution formats

## Quick Start

### Bootstrap from a Clean Machine

```bash
# Linux/macOS/WSL
curl -fsSL https://raw.githubusercontent.com/imcalderon/vfx-bootstrap/main/bootstrap/bootstrap.sh | bash

# Windows PowerShell (future)
# irm https://raw.githubusercontent.com/imcalderon/vfx-bootstrap/main/bootstrap/bootstrap.ps1 | iex
```

### Build USD

```bash
# Build USD with all dependencies for VFX Platform 2024
vfx-bootstrap build usd --platform vfx2024

# Build a specific package
vfx-bootstrap build openexr --platform vfx2024

# Build all packages
vfx-bootstrap build --all --platform vfx2024
```

### Package for Distribution

```bash
# Export to conda package
vfx-bootstrap package usd --format conda

# Export to tarball with manifest
vfx-bootstrap package usd --format tarball

# Export to all supported formats
vfx-bootstrap package usd --format all
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     vfx-bootstrap                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ bootstrap│───▶│  builder │───▶│ packager │───▶│ registry │  │
│  │ (stage0) │    │ (conda)  │    │ (agnostic)│   │ (catalog)│  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │               │               │               │         │
│       ▼               ▼               ▼               ▼         │
│  Platform       Build Cache     Multi-format      Package       │
│  Detection      Dependency      Exporters         Registry      │
│  Tool Setup     Resolution      (conda,tar,zip)   (future)      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    recipes/ (cross-platform)                ││
│  │  VFX Platform 2024: Python 3.11, Boost 1.82, TBB 2020.3,   ││
│  │  OpenEXR 3.2, OpenVDB 11, Alembic 1.8, MaterialX 1.38, USD ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## VFX Platform 2024 Support

Initial release targets VFX Platform 2024:

| Package | Version | Status |
|---------|---------|--------|
| Python | 3.11.x | Planned |
| Boost | 1.82 | Planned |
| TBB | 2020 Update 3 | Planned |
| OpenEXR | 3.2.x | Planned |
| Imath | 3.1.x | Planned |
| OpenVDB | 11.x | Planned |
| OpenSubdiv | 3.6.x | Planned |
| Alembic | 1.8.x | Planned |
| MaterialX | 1.38.x | Planned |
| **USD** | 24.x | **Goal** |

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Ubuntu 22.04 / WSL | Primary | Development target |
| Rocky Linux 8/9 | Supported | RHEL-compatible |
| macOS | Future | Native builds only |
| Windows Native | Future | Lower priority |

## Project Structure

```
vfx-bootstrap/
├── bootstrap/          # Stage 0 - clean machine setup
│   ├── bootstrap.sh    # Main entry point
│   ├── platforms/      # Platform-specific scripts
│   └── modules/        # Reusable setup modules
├── builder/            # Build orchestration
│   ├── core.py         # Build engine
│   ├── cache.py        # Build caching
│   └── cli.py          # Command-line interface
├── recipes/            # Cross-platform conda recipes
│   ├── python/
│   ├── boost/
│   ├── tbb/
│   └── usd/            # The goal
├── packager/           # Format-agnostic packaging
│   ├── schema/         # Package manifest schema
│   └── exporters/      # Format exporters
├── docs/               # Documentation
└── tests/              # Test suite
```

## Documentation

- [Vision](docs/vision.md) - Project goals and philosophy
- [Architecture](docs/architecture.md) - Technical deep-dive
- [VFX Platform 2024](docs/vfx-platform-2024.md) - Version reference
- [Recipe Porting Guide](docs/recipe-porting.md) - Cross-platform recipe development
- [Contributing](CONTRIBUTING.md) - How to contribute

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 - See [LICENSE](LICENSE) for details.

## Background

This project is informed by experience building internal CI infrastructure at Pixar Animation Studios. The work involved creating a bridge system with Jenkins multi-platform builds, Perforce mappings from the internal `pxr/` monorepo to match the OpenUSD structure, and trigger-based automation to continuously verify the open source variant would build whenever internal code changed. These concepts directly inform this toolkit's design.

## Acknowledgments

This project builds upon concepts and code from:
- [VFX Reference Platform](https://vfxplatform.com/)
- [Pixar USD](https://openusd.org/)
- [conda-forge](https://conda-forge.org/)
