# DevEnv

Cross-platform development environment manager that takes a clean machine to a fully-functional build environment. Supports VFX (USD/QML), web, data science, and game development workflows with modular tool installation, project scaffolding, and Bazel/CMake build system integration.

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
| `vfx` | zsh, git, docker, python, conda, vfx, bazel, vscode | VFX Platform build & QML/USD development |
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
| bazel | x | x | x | Bazel build system (via Bazelisk) |
| qtcreator | x | x | x | Qt Creator IDE (Standalone) |
| vfx | x | x | x | VFX Platform build environment & local channel |
| zsh | x | x | | Z shell with Oh My Zsh and vi-mode |
| git | x | x | x | Git with SSH and shell integration |
| docker | x | x | x | Docker with container management |
| python | x | x | x | Python with pyenv and venv |
| nodejs | x | x | x | Node.js with nvm |
| conda | x | x | x | Miniconda environment manager |
| vscode | x | x | x | VS Code with VFX/QML extensions |
| vault | x | x | x | OpenBao/Vault secrets management |
| powershell | | | x | PowerShell profile and modules |
| terminal | | | x | Windows Terminal configuration |
| winget | | | x | Windows Package Manager |

## Project Scaffolding

Generate new projects from workflow templates with local environment isolation and build system integration.

```powershell
# Windows
.\devenv.ps1 create-project -Name my-app -Template vfx:qml      # Qt/QML + USD + Bazel
.\devenv.ps1 create-project -Name my-tool -Template vfx:standard # C++ + CMake
```

```bash
# Linux/macOS
./devenv --new-project my-app --type vfx:qml
./devenv --new-project my-game --type web:phaser
```

### VFX:QML Features
- **Local Conda Channel:** Automatically points to your built VFX binaries.
- **Bazel-Conda Bridge:** `vfx_platform.bzl` symlinks Conda dependencies into Bazel targets.
- **USD & Qt6:** Pre-configured `CMakeLists.txt` and `BUILD.bazel` for USD/QML development.

## VFX Platform Build System

Full VFX Platform stack built from source via conda-build, with native MSVC support on Windows.

**Build chain:** imath → openexr → alembic → boost → materialx → opencolorio → ptex → tbb → openvdb → openimageio → opensubdiv → usd (24.11)

```bash
# List available recipes
.\devenv\scripts\build_vfx.ps1 -List

# Build a specific package
.\devenv\scripts\build_vfx.ps1 usd

# Build the entire pipeline
.\devenv\scripts\build_vfx.ps1 -All
```

Recipes live in `toolkits/vfx-bootstrap/recipes/`. Each recipe has a `meta.yaml`, `build.sh` (Linux/macOS), and `bld.bat` (Windows). Builds output to `~/Development/vfx/builds/` with local channel indexing in `~/Development/vfx/channel/`.

## Hermetic Environments

DevEnv supports dual-mode operation:
1. **Global Mode:** Installs shared tools to the system (e.g., Git, VS Code, Bazel).
2. **Project Mode:** When running from a project directory, DevEnv creates an isolated local environment in `.devenv/`, including project-specific Conda environments defined in `environment.yml`.

## WSL Support

Provision AlmaLinux WSL environments for Linux development on Windows.

```powershell
.\wsl\reset-wsl.ps1                 # Reset and provision AlmaLinux WSL
.\wsl\reset-wsl.ps1 -FullSetup      # Full setup with devenv + Claude Code + gh CLI
```

## License

MIT License - see [LICENSE](LICENSE)
