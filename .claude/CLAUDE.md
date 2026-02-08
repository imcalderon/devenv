# DevEnv — Unified Development Environment Manager

## Overview
DevEnv is a cross-platform, modular development environment manager that takes a clean machine to a fully-functional build environment. It supports VFX (USD/OpenEXR), web (Phaser/Vite), data science, and game development workflows with project scaffolding and agentic metadata.

## Architecture

```
devenv                    # Entry point: platform detection, routing
devenv.sh                 # Linux/macOS orchestrator
devenv.ps1                # Windows orchestrator
config.json               # Global config (platforms, modules, templates)
lib/
  compat.sh               # Cross-platform helpers (sed_inplace, expand_vars)
  logging.sh              # Structured logging (INFO, WARN, ERROR, DEBUG)
  json.sh                 # jq wrapper with auto-install
  module.sh               # Module lifecycle + Docker integration
  backup.sh               # Backup/restore utilities
  alias.sh                # ZSH alias management
  scaffold.sh             # Project scaffolding engine
  secrets.sh              # Secrets management
  windows/                # Windows-specific PowerShell libraries
modules/                  # All modules (see Module Index below)
workflows/                # Workflow definitions (replace flat templates)
  vfx/workflow.json       # VFX Platform 2024 workflow
  web/workflow.json       # Web dev with phaser/vanilla sub-types
  data-science/workflow.json
  game/workflow.json
scaffolds/                # Project templates for --new-project
  common/                 # Shared files (.gitignore, .editorconfig, README)
  vfx/                    # CMake + C++ VFX project
  web/phaser/             # Phaser 3 + TypeScript game
  web/vanilla/            # Vite + TypeScript
toolkits/
  vfx-bootstrap/          # Conda-based VFX build system
    builder/              # core.py, cli.py, cache.py
    packager/             # Export to conda, tar, archive
    recipes/              # 12 VFX package recipes
schemas/                  # JSON schemas for validation
tests/                    # bats (lib/, modules/) + pytest (vfx-bootstrap)
wsl/                      # WSL provisioning scripts
```

## Module Index

Each module has its own `.claude/CLAUDE.md` with detailed documentation.

| Module | Runlevel | Platform | Purpose |
|--------|----------|----------|---------|
| [zsh](modules/zsh/.claude/CLAUDE.md) | 1 | Linux/macOS | Z shell + Oh My Zsh |
| [git](modules/git/.claude/CLAUDE.md) | 1 | Cross-platform | Git configuration |
| [docker](modules/docker/.claude/CLAUDE.md) | 1 | Cross-platform | Container runtime |
| [python](modules/python/.claude/CLAUDE.md) | 2 | Cross-platform | Python + pyenv |
| [nodejs](modules/nodejs/.claude/CLAUDE.md) | 2 | Cross-platform | Node.js + nvm |
| [conda](modules/conda/.claude/CLAUDE.md) | 3 | Linux/macOS | Miniconda |
| [vscode](modules/vscode/.claude/CLAUDE.md) | 3 | Cross-platform | VS Code + extensions |
| [vfx](modules/vfx/.claude/CLAUDE.md) | 5 | Linux/macOS | VFX Platform build env |
| [react](modules/react/.claude/CLAUDE.md) | 3 | Linux/macOS | React framework |
| [tiled](modules/tiled/.claude/CLAUDE.md) | 3 | Linux/macOS | Tiled map editor |
| [ldtk](modules/ldtk/.claude/CLAUDE.md) | 3 | Linux/macOS | LDtk level editor |
| [powershell](modules/powershell/.claude/CLAUDE.md) | 1 | Windows | PowerShell config |
| [terminal](modules/terminal/.claude/CLAUDE.md) | 1 | Windows | Windows Terminal |
| [winget](modules/winget/.claude/CLAUDE.md) | 1 | Windows | Windows Package Manager |
| [registry](modules/registry/.claude/CLAUDE.md) | 1 | Windows | Windows Registry |

## Key Commands

```bash
# Environment management
./devenv init vfx              # Initialize VFX workflow
./devenv init web              # Initialize web development
./devenv install <module>      # Install a specific module
./devenv verify                # Health check all modules
./devenv workflows             # List available workflows

# Project scaffolding
./devenv --new-project my-tool --type vfx          # C++ VFX project
./devenv --new-project my-game --type web:phaser    # Phaser game
./devenv --new-project my-app --type web:vanilla    # Vite + TS
./devenv --list-types                               # Show types

# VFX builds
conda run -n vfx-build python -m builder.cli list   # List recipes
conda run -n vfx-build python -m builder.cli build <pkg> -v

# Development
make lint                      # ShellCheck + JSON validation
make test                      # bats + pytest
```

## Conventions

- **Shell**: `set -euo pipefail`, log via `log "LEVEL" "msg" "module"`
- **JSON**: `get_module_config` / `get_json_value` wrappers (never raw jq in modules)
- **Variable expansion**: `expand_vars` (never `eval echo`)
- **Portable sed**: `sed_inplace` (never raw `sed -i`)
- **Conda commands**: `conda run -n <env>` (never `conda activate`)
- **Module interface**: install, remove, verify, info via case statement
- **State tracking**: `$HOME/.devenv/state/<module>.state`
- **Commits**: No `Co-Authored-By:` lines

## Platform Detection

| Distribution | Package Manager | Detection |
|-------------|-----------------|-----------|
| AlmaLinux, RHEL, Fedora | `dnf` | `command -v dnf` |
| Ubuntu, Debian | `apt-get` | `command -v apt-get` |
| macOS | `brew` | `command -v brew` |
| Windows | `winget` | PowerShell environment |

WSL: Check `/proc/version` for "microsoft".

## VFX Build System

Build order: imath → openexr → opencolorio → tbb → opensubdiv → boost → openvdb → ptex → openimageio → materialx → alembic → usd

- Recipes in `toolkits/vfx-bootstrap/recipes/<pkg>/`
- Output: `~/Development/vfx/builds/linux-64/`
- Logs: `~/Development/vfx/builds/logs/`
- SHA256 verify: `curl -sL <url> | sha256sum`

## Known Issues

- VFX module reports `[ok]` even on failure (#100)
- Docker listed as VFX dep but not in template (#101)
- TBB recipe has uncommitted local changes (#102)
