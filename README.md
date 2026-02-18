# DevEnv

Cross-platform development environment manager that takes a clean machine to a fully-functional build environment. Supports VFX, web, data science, and game development workflows with modular tool installation, project scaffolding, and native Windows MSVC support.

## Quick Start

```bash
# Clone
git clone https://github.com/imcalderon/devenv.git
cd devenv

# Linux/macOS
./devenv install                     # Install all modules
./devenv init vfx                    # Or initialize a specific workflow

# Windows PowerShell
.\devenv.ps1 install                 # Install all modules
.\devenv.ps1 install git python      # Install specific modules
```

## Workflows

Workflows bundle modules into purpose-built environments.

| Workflow | Modules | Description |
|----------|---------|-------------|
| `vfx` | zsh, git, docker, python, conda, vfx | VFX Platform 2024 build environment |
| `web` | zsh, git, nodejs, vscode, docker | Web development with Vite/Phaser |
| `data-science` | zsh, git, python, vscode, docker, conda | Jupyter, pandas, scikit-learn |
| `game` | zsh, git, nodejs, vscode, docker | Game development with Phaser/LDtk |

```bash
./devenv init <workflow>             # Install a workflow
./devenv workflows                   # List available workflows
```

## Modules

| Module | Linux | macOS | Windows | Description |
|--------|:-----:|:-----:|:-------:|-------------|
| zsh | x | x | | Z shell with Oh My Zsh and vi-mode |
| git | x | x | x | Git with SSH and shell integration |
| docker | x | x | x | Docker with container management |
| python | x | x | x | Python with pyenv and venv |
| nodejs | x | x | x | Node.js with nvm |
| conda | x | x | x | Miniconda environment manager |
| vscode | x | x | x | VS Code with extensions |
| vfx | x | x | x | VFX Platform build environment |
| react | x | x | | React development setup |
| tiled | x | x | | Tiled map editor |
| ldtk | x | x | | LDtk level editor |
| vault | x | x | x | OpenBao/Vault secrets management |
| powershell | | | x | PowerShell profile and modules |
| terminal | | | x | Windows Terminal configuration |
| winget | | | x | Windows Package Manager |
| registry | | | x | Windows Registry settings |

Each module implements four actions: `install`, `remove`, `verify`, `info`.

## Project Scaffolding

Generate new projects from templates with agentic metadata (Claude Code CLAUDE.md, rules, and skills).

```bash
./devenv --new-project my-tool --type vfx          # C++ with CMake, Imath/OpenEXR
./devenv --new-project my-game --type web:phaser    # Phaser 3 + TypeScript + Vite
./devenv --new-project my-app --type web:vanilla    # Vanilla TypeScript + Vite
./devenv --list-types                               # Show all project types
```

## VFX Platform Build System

Full VFX Platform 2024 stack built from source via conda-build, with native MSVC support on Windows.

**Build chain:** imath → openexr → opencolorio → tbb → boost → opensubdiv → openvdb → ptex → openimageio → materialx → alembic → usd

```bash
conda run -n vfx-build python -m builder.cli list              # List recipes
conda run -n vfx-build python -m builder.cli build imath -v    # Build a package
conda run -n vfx-build python -m builder.cli build usd -v      # Build USD (all deps)
```

Recipes live in `toolkits/vfx-bootstrap/recipes/`. Each recipe has a `meta.yaml`, `build.sh` (Linux/macOS), and `bld.bat` (Windows). Builds output to `~/Development/vfx/builds/` with logs in the `logs/` subdirectory.

## Commands

```bash
./devenv install [modules...]       # Install modules (all if none specified)
./devenv remove [modules...]        # Remove modules
./devenv verify [modules...]        # Verify installations
./devenv info [modules...]          # Show module status
./devenv list                       # List available modules
./devenv status                     # Show environment status
./devenv backup                     # Backup configurations
./devenv restore                    # Restore from backup
./devenv init <workflow>            # Initialize a workflow
./devenv workflows                  # List workflows
./devenv --new-project <n> --type <t>  # Scaffold a project
./devenv --list-types               # List project types
```

## WSL Support

Provision AlmaLinux WSL environments for Linux development on Windows.

```powershell
.\wsl\reset-wsl.ps1                 # Reset and provision AlmaLinux WSL
.\wsl\reset-wsl.ps1 -FullSetup      # Full setup with devenv + Claude Code + gh CLI
```

## Project Structure

```
devenv                       # Entry point: platform detection, routing
devenv.sh                    # Linux/macOS orchestrator
devenv.ps1                   # Windows orchestrator
config.json                  # Global configuration
lib/
  compat.sh                  # Cross-platform helpers (sed_inplace, expand_vars)
  logging.sh                 # Structured logging
  json.sh                    # jq wrapper with auto-install
  module.sh                  # Module lifecycle + Docker integration
  backup.sh                  # Backup/restore utilities
  alias.sh                   # ZSH alias management
  scaffold.sh                # Project scaffolding engine
  secrets.sh                 # Secrets management
  windows/                   # Windows PowerShell libraries
modules/<name>/
  config.json                # Module configuration
  <name>.sh                  # Bash implementation
  <name>.ps1                 # PowerShell implementation (Windows modules)
workflows/<type>/
  workflow.json              # Workflow definition
scaffolds/
  common/                    # Shared files (.gitignore, .editorconfig)
  vfx/                       # C++ VFX project template
  web/phaser/                # Phaser 3 + TypeScript template
  web/vanilla/               # Vite + TypeScript template
toolkits/vfx-bootstrap/
  builder/                   # Build system (core.py, cli.py, cache.py)
  packager/                  # Export to conda, tar, archive
  recipes/                   # 12 VFX package recipes
schemas/                     # JSON schemas for validation
tests/                       # bats (shell) + pytest (vfx-bootstrap)
wsl/                         # WSL provisioning scripts
```

## Development

```bash
make lint                    # ShellCheck + JSON validation
make test                    # bats + pytest
```

### Conventions

- Shell: `set -euo pipefail`, logging via `log "LEVEL" "msg" "module"`
- PowerShell: `Set-StrictMode -Version Latest`
- JSON: `get_module_config` / `get_json_value` wrappers, never raw jq in modules
- Variable expansion: `expand_vars`, never `eval echo`
- Portable sed: `sed_inplace`, never raw `sed -i`
- Conda: `conda run -n <env>`, never `conda activate`
- Line endings: `.sh` = LF, `.ps1` = CRLF (via .gitattributes)

## License

MIT License - see [LICENSE](LICENSE)
