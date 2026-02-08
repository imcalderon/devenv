# vfx-bootstrap Vision

## Background

This project is informed by experience building internal CI infrastructure at Pixar Animation Studios. At Pixar, the `pxr/` directory in the monorepo contains the core shared code (including what becomes USD) that feeds into larger systems like Presto. The internal bridge system involved:

- Setting up Jenkins build machines for each supported platform
- Creating Perforce mappings from internal `pxr/` files to match the OpenUSD repository structure
- Configuring Perforce triggers to automatically kick off Jenkins builds whenever internal code changed
- Continuously testing that the open source variant would build successfully

This internal CI ensured that changes to `pxr/` wouldn't break the open source build before periodic releases were pushed to the public OpenUSD repository (which uses separate Azure-backed CI on GitHub).

This experience revealed how complex VFX build infrastructure can be - and how valuable it would be to make that infrastructure accessible to everyone.

## The Problem

Building VFX software, particularly Pixar's USD (Universal Scene Description), is notoriously difficult:

1. **Complex dependency chains**: USD depends on dozens of libraries (Boost, TBB, OpenEXR, OpenVDB, etc.)
2. **Version sensitivity**: VFX Platform specifies exact versions that must work together
3. **Platform fragmentation**: Studios use different Linux distributions, macOS versions, and occasionally Windows
4. **Tribal knowledge**: Build procedures are often documented in scattered READMEs or exist only as institutional knowledge
5. **High barrier to entry**: New developers spend days or weeks just setting up their environment

## The Solution

vfx-bootstrap provides a complete, reproducible path from a clean machine to a working USD build:

```
Clean Machine → Bootstrap → Build Dependencies → Build USD → Package
```

Each step is:
- **Automated**: Single commands, no manual intervention
- **Documented**: Every decision explained
- **Reproducible**: Same inputs produce same outputs
- **Cross-platform**: Works on major Linux distributions and macOS

## Design Principles

### 1. Clean Machine Start

The project assumes you have nothing but a fresh OS install. No pre-installed compilers, no conda, no development tools. The bootstrap script handles everything.

```bash
# This should be all you need
curl -fsSL https://raw.githubusercontent.com/imcalderon/vfx-bootstrap/main/bootstrap/bootstrap.sh | bash
```

### 2. VFX Platform Compliance

Every build targets a specific VFX Reference Platform year. This ensures:
- Library versions are compatible
- Builds can be used with commercial VFX software
- Studios can adopt the toolchain with confidence

### 3. Conda-Based Building

Conda provides:
- Consistent compiler toolchains across platforms
- Hermetic builds isolated from system libraries
- Reproducible environments
- Easy distribution of built packages

### 4. Format-Agnostic Packaging

Built software can be exported to multiple formats:
- **Conda packages**: For conda-based workflows
- **Tarballs**: Simple, universal format with manifest
- **Archives**: ZIP/7z for easy distribution
- **Future**: MSI (Windows), DMG (macOS), RPM/DEB (Linux)

### 5. Caching and Efficiency

Building USD from scratch takes hours. The system provides:
- Local build caching
- Optional shared cache server for teams
- Incremental rebuilds when sources change

## Target Users

### Individual Developers
- Learn USD development without infrastructure hassle
- Quickly set up environments for experimentation
- Contribute to USD without deep build system knowledge

### Small Studios
- Bootstrap a VFX pipeline without dedicated build engineers
- Maintain compliance with VFX Platform
- Distribute tools to artists reliably

### Build Engineers
- Reference implementation for VFX builds
- Starting point for studio-specific customizations
- Cross-platform recipes as foundation

### Educators and Students
- Teaching USD and VFX development
- Classroom-ready environments
- Reproducible setups for assignments

## What This Is NOT

- **Not a package manager**: We use conda for that
- **Not a replacement for Rez**: This builds packages; Rez manages runtime environments
- **Not studio-specific**: Generic foundation others can customize
- **Not Windows-first**: Linux is primary; Windows support is secondary

## Success Metrics

1. **Bootstrap time**: Fresh machine to ready-to-build in < 5 minutes (excluding downloads)
2. **Build success rate**: > 95% on supported platforms without intervention
3. **Rebuild time**: Cached rebuild completes in seconds
4. **Platform coverage**: Same recipes work on Ubuntu, Rocky Linux, macOS
5. **Documentation completeness**: Any step can be understood by reading docs

## Roadmap

### Phase 1: Foundation (Current)
- Project structure and documentation
- Bootstrap scripts for Linux/WSL
- Core dependency recipes (Boost, TBB, OpenEXR)

### Phase 2: USD Build
- Complete dependency chain
- USD recipe with all features
- Build caching system

### Phase 3: Packaging
- Format-agnostic package schema
- Multiple export formats
- Distribution workflow

### Phase 4: Registry (Future)
- Package catalog
- Client for browsing/installing
- Team/studio sharing

## Philosophy

> "Make the simple things easy and the complex things possible."

Building USD should be:
- **Easy** for new developers who just want to learn
- **Flexible** for studios with specific requirements
- **Transparent** for build engineers who need to understand every detail

We achieve this by providing sensible defaults while documenting every assumption and making every component replaceable.
