# VFX Module

## Purpose
Sets up a complete VFX Platform build environment with conda, vfx-bootstrap, and build dependencies.

## Key Files
| File | Purpose |
|------|---------|
| vfx.sh | Main implementation (545 lines) |
| config.json | Module config (runlevel 5, depends on conda, docker, git) |

## Interface
- `install` — Installs all 6 components in order (see below)
- `remove` — Removes conda env, shell aliases, and platform config
- `verify` — Checks each component is functional
- `info` — Shows VFX Platform version, installed packages, component status

## Dependencies
conda, docker, git.

## Component Lifecycle
Components install in strict order:
1. **build_deps** — cmake, ninja, gcc via apt/dnf/brew
2. **conda_env** — Creates `vfx-build` conda environment with conda-build, boa
3. **vfx_bootstrap** — `pip install -e` from `$DEVENV_ROOT/toolkits/vfx-bootstrap`
4. **channels** — Creates local conda channel at `~/Development/vfx/channel`
5. **shell** — Registers aliases (vfx-build, vfx-list, etc.) in ZSH
6. **platform_version** — Writes `~/.vfx-devenv/platform.json` with version specs

## Conventions
- All VFX commands use `conda run -n vfx-build` (never activate)
- Build output: `~/Development/vfx/builds/linux-64/`
- Build logs: `~/Development/vfx/builds/logs/`
- VFX Platform 2024: Python 3.11, C++17, Boost 1.82, TBB 2020.3, USD 24.03
- VFX Platform 2025: Python 3.12, C++17, Boost 1.84, TBB 2021.11, USD 25.02

## Known Issues
- Reports `[ok]` even on component failure (#100)
- Docker listed as dependency but not needed for local builds (#101)
