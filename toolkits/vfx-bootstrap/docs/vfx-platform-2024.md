# VFX Platform 2024 Reference

This document specifies the exact versions required for VFX Platform 2024 compliance.

## Official VFX Platform 2024 Versions

Source: [VFX Reference Platform](https://vfxplatform.com/)

### Core Libraries

| Package | Version | Notes |
|---------|---------|-------|
| **Python** | 3.11.x | Foundation for all Python-based tools |
| **Qt** | 5.15.x | UI framework (Qt 6 adoption pending) |
| **PyQt/PySide** | 5.15.x / 6.5.x | Python Qt bindings |
| **NumPy** | 1.24.x | Numerical computing |

### C++ Core

| Package | Version | Notes |
|---------|---------|-------|
| **GCC** | 11.2.1 | Reference compiler |
| **glibc** | 2.17 | Minimum C library (RHEL 7 compatible) |
| **C++ Standard** | C++17 | Minimum required standard |

### VFX Libraries

| Package | Version | USD Dependency | Notes |
|---------|---------|----------------|-------|
| **Boost** | 1.82 | Yes | Core C++ utilities |
| **TBB** | 2020 Update 3 | Yes | Threading Building Blocks |
| **OpenEXR** | 3.2.x | Yes | HDR image format |
| **Imath** | 3.1.x | Yes | Math library (was part of OpenEXR) |
| **OpenColorIO** | 2.3.x | Optional | Color management |
| **OpenImageIO** | 2.5.x | Optional | Image I/O library |
| **OpenVDB** | 11.x | Optional | Volumetric data |
| **OpenSubdiv** | 3.6.x | Yes | Subdivision surfaces |
| **Alembic** | 1.8.x | Yes | Geometry interchange |
| **MaterialX** | 1.38.x | Yes | Material definitions |
| **OSL** | 1.13.x | Optional | Open Shading Language |
| **Ptex** | 2.4.x | Optional | Per-face texturing |
| **Blosc** | 1.21.x | Via OpenVDB | Compression library |

### USD Specific

| Package | Version | Notes |
|---------|---------|-------|
| **USD** | 24.x | Primary build target |
| **draco** | 1.5.x | Optional mesh compression |
| **embree** | 4.x | Optional ray tracing |

## Dependency Graph

```
USD 24.x
├── Python 3.11
├── Boost 1.82
├── TBB 2020.3
├── OpenSubdiv 3.6
│   ├── TBB
│   └── OpenGL
├── OpenEXR 3.2
│   └── Imath 3.1
├── Alembic 1.8
│   ├── OpenEXR
│   └── Imath
├── MaterialX 1.38
│   └── OpenEXR
└── (Optional)
    ├── OpenVDB 11
    │   ├── TBB
    │   ├── OpenEXR
    │   └── Blosc 1.21
    ├── OpenImageIO 2.5
    │   ├── OpenEXR
    │   └── OpenColorIO 2.3
    └── Draco 1.5
```

## Build Order

Recommended build order to satisfy dependencies:

1. **Foundation**
   - Python 3.11
   - Boost 1.82

2. **Threading**
   - TBB 2020.3

3. **Image Foundation**
   - Imath 3.1
   - OpenEXR 3.2

4. **Core VFX**
   - OpenSubdiv 3.6
   - Alembic 1.8
   - MaterialX 1.38

5. **Optional Components**
   - Blosc 1.21
   - OpenVDB 11
   - OpenColorIO 2.3
   - OpenImageIO 2.5

6. **USD**
   - USD 24.x

## Configuration

### `conda_build_config.yaml`

```yaml
# VFX Platform 2024 version pins
python:
  - "3.11"

boost:
  - "1.82"

tbb:
  - "2020.3"

imath:
  - "3.1"

openexr:
  - "3.2"

opensubdiv:
  - "3.6"

openvdb:
  - "11"

alembic:
  - "1.8"

materialx:
  - "1.38"

usd:
  - "24"

# Compiler settings
c_compiler:
  - gcc  # [linux]
  - clang  # [osx]

cxx_compiler:
  - gxx  # [linux]
  - clangxx  # [osx]

c_compiler_version:
  - "11"  # [linux]
  - "14"  # [osx]

cxx_compiler_version:
  - "11"  # [linux]
  - "14"  # [osx]

cxx_standard:
  - "17"
```

## Platform-Specific Notes

### Linux

- Target glibc 2.17 for maximum compatibility
- Use devtoolset/gcc-toolset on RHEL/CentOS for newer GCC
- Mesa required for software OpenGL rendering

### macOS

- Minimum deployment target: macOS 10.15 (Catalina)
- Xcode 14+ recommended
- Universal builds (arm64 + x86_64) optional

### Windows (Future)

- Visual Studio 2022 (v143 toolset)
- Windows SDK 10.0.19041.0+
- Different TBB version may be needed

## Validation

To verify your build environment is VFX Platform 2024 compliant:

```bash
vfx-bootstrap validate --platform vfx2024
```

This checks:
- Installed package versions
- Compiler version and standards support
- Library ABI compatibility
- Python module availability

## References

- [VFX Reference Platform 2024](https://vfxplatform.com/)
- [USD Documentation](https://openusd.org/docs/)
- [ASWF Projects](https://www.aswf.io/projects/)
