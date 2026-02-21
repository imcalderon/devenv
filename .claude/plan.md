# Windows VFX Platform Build Support — Full Stack to USD

## Context

The devenv project builds the complete VFX Platform stack (12 packages up to USD) on Linux/macOS via `toolkits/vfx-bootstrap/`. Windows has **zero VFX build support**: no `bld.bat` recipe files, no MSVC compiler config, no `vfx.ps1` module, and no Windows conda module. The goal is native MSVC parity so the full chain builds on Windows:

**imath → openexr → opencolorio → tbb → boost → opensubdiv → openvdb → ptex → openimageio → materialx → alembic → usd**

## Phase 1: Infrastructure (6 files modified/created)

### 1.1 Add MSVC compilers to `toolkits/vfx-bootstrap/recipes/conda_build_config.yaml`

Append `# [win]` entries to existing compiler sections:

```yaml
c_compiler:
  - gcc                        # [linux]
  - clang                      # [osx]
  - vs2022                     # [win]

cxx_compiler:
  - gxx                        # [linux]
  - clangxx                    # [osx]
  - vs2022                     # [win]

c_compiler_version:
  - "11"                       # [linux]
  - "14"                       # [osx]
  - "19.3"                     # [win]

cxx_compiler_version:
  - "11"                       # [linux]
  - "14"                       # [osx]
  - "19.3"                     # [win]
```

### 1.2 Add Windows conda support to `modules/conda/config.json`

- Add `"win-64"` installer URL to `package.installer_urls`
- Add `platforms.windows` section with `enabled: true` and Windows paths (`%USERPROFILE%\miniconda3`)

### 1.3 Create `modules/conda/conda.ps1` — Windows Miniconda module

Components: `core` (download/install Miniconda silently), `config` (channels, channel_priority), `shell` (conda init powershell), `aliases`

Follows the established pattern from `git.ps1` / `winget.ps1`: param block, dot-source `lib\windows\*`, component state tracking, 5 actions.

### 1.4 Add Windows build deps to `modules/vfx/config.json`

Add under `build_deps`:
```json
"windows": {
    "winget": [
        "Microsoft.VisualStudio.2022.BuildTools",
        "Kitware.CMake",
        "Ninja-build.Ninja",
        "NASM.NASM"
    ],
    "vs_workloads": [
        "Microsoft.VisualStudio.Workload.VCTools",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "Microsoft.VisualStudio.Component.Windows11SDK.22621"
    ]
}
```

Add Windows paths under `shell.paths` and `platforms.windows.enabled: true`.

### 1.5 Add conda and vfx to Windows module order in `config.json`

```json
"order": ["terminal","powershell","winget","git","docker","python","nodejs","vscode","conda","vfx"]
"available": [..., "conda", "vfx"]
```

### 1.6 Add `"win-64"` to `toolkits/vfx-bootstrap/builder/core.py`

In `_find_build_outputs()`, add `"win-64"` to the subdirs list alongside `"linux-64"`, `"osx-64"`, etc.

---

## Phase 2: Recipe `bld.bat` Files (12 created, 12 `meta.yaml` modified)

### Common `bld.bat` pattern

All CMake-based recipes use:
```batch
@echo off
setlocal enabledelayedexpansion

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    <recipe-specific flags>
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
```

**Key translations**: `$PREFIX` → `%LIBRARY_PREFIX%` (conda-build sets this to `%PREFIX%\Library` on Windows), remove all rpath flags, `$SRC_DIR` → `%SRC_DIR%`, `$PYTHON` → `%PYTHON%`, caret `^` for line continuation.

### Common `meta.yaml` changes

For each recipe:
- Change `- ninja  # [unix]` to `- ninja` (Ninja works with MSVC)
- Add Windows test commands: `if not exist %LIBRARY_PREFIX%\lib\Foo.lib exit 1  # [win]`
- Add Windows header tests: `if not exist %LIBRARY_PREFIX%\include\Foo\Foo.h exit 1  # [win]`

### 2.1 `recipes/imath/bld.bat` — Simplest, no VFX deps

Flags: `-DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF -DPYTHON=OFF`

### 2.2 `recipes/openexr/bld.bat` — Depends on imath

Flags: `-DBUILD_SHARED_LIBS=ON -DOPENEXR_INSTALL_TOOLS=ON -DOPENEXR_INSTALL_EXAMPLES=OFF -DBUILD_TESTING=OFF`

### 2.3 `recipes/opencolorio/bld.bat` — Python bindings

Flags: `-DOCIO_BUILD_PYTHON=ON -DPython_EXECUTABLE="%PYTHON%" -DOCIO_BUILD_APPS=ON -DOCIO_BUILD_TESTS=OFF -DOCIO_BUILD_GPU_TESTS=OFF -DOCIO_BUILD_DOCS=OFF -DOCIO_INSTALL_EXT_PACKAGES=MISSING`

### 2.4 `recipes/tbb/bld.bat` — Dual-branch (most complex translation)

Detects `CMakeLists.txt` for oneTBB 2021+ (cmake+ninja) vs classic TBB 2020.3. Classic path attempts CMake build with `-DTBB_BUILD_TESTS=OFF`; if unavailable, falls back to manual header/lib install with custom `TBBConfig.cmake` (using `.lib`/`.dll` instead of `.so`).

### 2.5 `recipes/boost/bld.bat` — Non-CMake: uses b2

```batch
call bootstrap.bat msvc
b2 -j%CPU_COUNT% --prefix="%LIBRARY_PREFIX%" variant=release link=shared ^
    runtime-link=shared threading=multi toolset=msvc-14.3 ^
    cxxflags="/std:c++17" address-model=64 ^
    python=%PY_VER% --without-mpi --without-graph_parallel install
```

### 2.6 `recipes/opensubdiv/bld.bat` — Standard CMake

Flags: Disable examples/tutorials/GPU features, enable TBB with `-DTBB_LOCATION="%LIBRARY_PREFIX%"`

### 2.7 `recipes/openvdb/bld.bat` — Memory-limited parallelism

Same CMake pattern but caps `--parallel` to max 2 jobs to prevent OOM on large template instantiations. Sets all `*_ROOT` variables to `%LIBRARY_PREFIX%`.

### 2.8 `recipes/ptex/bld.bat` — Simple CMake

Flags: `-DPTEX_BUILD_SHARED_LIBS=ON -DPTEX_BUILD_STATIC_LIBS=OFF -DPTEX_BUILD_DOCS=OFF`

### 2.9 `recipes/openimageio/bld.bat` — Many deps

Flags: Python bindings, OpenColorIO, disable Qt/tests, set `BOOST_ROOT`, `OpenEXR_ROOT`, `OpenColorIO_ROOT` etc.

### 2.10 `recipes/materialx/bld.bat` — Python bindings

Flags: `-DMATERIALX_BUILD_PYTHON=ON -DMATERIALX_BUILD_VIEWER=OFF -DMATERIALX_BUILD_TESTS=OFF -DMATERIALX_BUILD_GEN_GLSL=ON -DMATERIALX_BUILD_GEN_OSL=ON -DMATERIALX_BUILD_GEN_MDL=OFF`

### 2.11 `recipes/alembic/bld.bat` — Standard CMake

Flags: `-DALEMBIC_SHARED_LIBS=ON -DUSE_TESTS=OFF -DUSE_BINARIES=ON -DILMBASE_ROOT="%LIBRARY_PREFIX%" -DOPENEXR_ROOT="%LIBRARY_PREFIX%"`

### 2.12 `recipes/usd/bld.bat` + remove `skip: true  # [win]` from `meta.yaml`

Most complex: 30+ CMake flags integrating all packages. All `*_ROOT` variables point to `%LIBRARY_PREFIX%`. Enables Python, imaging, USD imaging, usdview, Alembic/MaterialX/OpenVDB/Ptex/OCIO/OIIO plugins.

---

## Phase 3: VFX PowerShell Module (1 new file)

### 3.1 Create `modules/vfx/vfx.ps1`

Components (matching `vfx.sh`):
1. **build_deps** — Install VS Build Tools, CMake, Ninja, NASM via winget; install VS workloads via `vs_installer.exe --add`
2. **conda_env** — Create `vfx-build` conda env with conda-build, boa, conda-verify
3. **vfx_bootstrap** — `conda run -n vfx-build pip install -e toolkits\vfx-bootstrap`
4. **channels** — Create local conda channel at `~\Development\vfx\channel\` with `win-64` and `noarch` subdirs, write `channeldata.json` and `repodata.json`
5. **shell** — Register PowerShell aliases (vfx-build, vfx-list, vfx-clean, vfx-info)
6. **platform_version** — Write `~\.vfx-devenv\platform.json` with VFX Platform 2024 specs

Follows `git.ps1` pattern: param block, `lib\windows\` imports, `Initialize-Module`, `Save-ComponentState`/`Test-ComponentState`/`Test-Component`, `Install-Module`/`Remove-Module`/`Test-ModuleVerification`/`Show-ModuleInfo`, main switch (`$Action`).

---

## Phase 4: Integration Verification

### Test sequence

1. `.\devenv.ps1 install conda` — verify Miniconda installs on Windows
2. `.\devenv.ps1 install vfx` — verify all 6 components report installed
3. Build chain in order:
   ```
   conda run -n vfx-build python -m builder.cli build imath -v
   conda run -n vfx-build python -m builder.cli build openexr -v
   ...continue through dependency order...
   conda run -n vfx-build python -m builder.cli build usd -v
   ```
4. Final validation: `conda run -n vfx-build python -c "from pxr import Usd; print(Usd.Stage.CreateInMemory())"`

### Syntax checks

- `powershell -NoProfile -Command "Get-Content <file> | Out-Null"` for each `.ps1`
- `python -c "import json; json.load(open('<file>'))"` for each modified `.json`
- `conda build --check <recipe>` for each recipe

---

## File Summary

| Action | File | Phase |
|--------|------|-------|
| Modify | `toolkits/vfx-bootstrap/recipes/conda_build_config.yaml` | 1 |
| Modify | `modules/conda/config.json` | 1 |
| Create | `modules/conda/conda.ps1` | 1 |
| Modify | `modules/vfx/config.json` | 1 |
| Modify | `config.json` (global) | 1 |
| Modify | `toolkits/vfx-bootstrap/builder/core.py` | 1 |
| Create | `recipes/imath/bld.bat` | 2 |
| Create | `recipes/openexr/bld.bat` | 2 |
| Create | `recipes/opencolorio/bld.bat` | 2 |
| Create | `recipes/tbb/bld.bat` | 2 |
| Create | `recipes/boost/bld.bat` | 2 |
| Create | `recipes/opensubdiv/bld.bat` | 2 |
| Create | `recipes/openvdb/bld.bat` | 2 |
| Create | `recipes/ptex/bld.bat` | 2 |
| Create | `recipes/openimageio/bld.bat` | 2 |
| Create | `recipes/materialx/bld.bat` | 2 |
| Create | `recipes/alembic/bld.bat` | 2 |
| Create | `recipes/usd/bld.bat` | 2 |
| Modify | All 12 `recipes/*/meta.yaml` | 2 |
| Create | `modules/vfx/vfx.ps1` | 3 |

**Totals: 15 new files, 18 modified files**

---

## Known Risks

- **TBB 2020.3**: Classic TBB lacks proper CMake support on Windows. The `bld.bat` must handle `nmake` or provide a manual install path with `.lib`/`.dll` and a Windows `TBBConfig.cmake`. VFX Platform 2025 (TBB 2021.11) solves this.
- **Boost b2 on MSVC**: Requires correct `toolset=msvc-14.3` and `address-model=64`. Historically reliable but occasionally needs VS version matching.
- **OpenVDB OOM**: 2-job cap may still be tight on 16GB machines. May need to reduce to 1 job.
- **USD complexity**: 30+ CMake variables; if any upstream package installs to unexpected paths, USD won't find it. `%LIBRARY_PREFIX%` must be consistent across all recipes.
- **DLL resolution at test time**: conda-build handles PATH setup via `activate.bat`, but custom test commands may need explicit `%LIBRARY_PREFIX%\bin` in PATH.
