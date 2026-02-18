# VFX Bootstrap Recipes

Cross-platform conda recipes for VFX Platform packages.

## Directory Structure

```
recipes/
├── conda_build_config.yaml    # VFX Platform version pins
├── python/                    # Python (foundation)
├── boost/                     # Boost C++ libraries
├── tbb/                       # Threading Building Blocks
├── imath/                     # Math library
├── openexr/                   # OpenEXR image format
├── opensubdiv/                # Subdivision surfaces
├── openvdb/                   # Volumetric data
├── alembic/                   # Geometry caching
├── materialx/                 # Material definitions
└── usd/                       # Universal Scene Description
```

## VFX Platform 2024 Target Versions

| Package | Version |
|---------|---------|
| Python | 3.11.x |
| Boost | 1.82 |
| TBB | 2020.3 |
| OpenEXR | 3.2.x |
| Imath | 3.1.x |
| OpenVDB | 11.x |
| OpenSubdiv | 3.6.x |
| Alembic | 1.8.x |
| MaterialX | 1.38.x |
| USD | 24.x |

## Recipe Structure

Each recipe follows conda-build conventions:

```
packagename/
├── meta.yaml       # Package metadata and dependencies
├── build.sh        # Unix build script
├── bld.bat         # Windows build script (optional)
└── patches/        # Source patches (optional)
```

## Building Recipes

Build a single recipe:

```bash
vfx-bootstrap build boost --platform vfx2024
```

Build all recipes in dependency order:

```bash
vfx-bootstrap build --all --platform vfx2024
```

## Cross-Platform Guidelines

1. **Use conda compiler packages**: `{{ compiler('c') }}`, `{{ compiler('cxx') }}`
2. **Use platform selectors**: `# [linux]`, `# [osx]`, `# [unix]`, `# [win]`
3. **Avoid hardcoded paths**: Use `$PREFIX`, `$SRC_DIR`, etc.
4. **Use CMake**: Provides consistent cross-platform builds

See [Recipe Porting Guide](../docs/recipe-porting.md) for details.
