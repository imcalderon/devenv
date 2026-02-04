# CLAUDE.md - DevEnv Project Context

## Project Overview

DevEnv is a cross-platform, hermetic development environment manager. It provides modular, containerized development tool installation and configuration across Windows (native + WSL), Linux, and macOS.

## Architecture

```
devenv                  # Entry point: detects platform, routes to .sh or .ps1
devenv.sh               # Linux/macOS orchestrator (sources lib/*.sh)
devenv.ps1              # Windows orchestrator (1,188 lines - needs refactoring)
de.ps1                  # Lightweight PowerShell wrapper
config.json             # Global configuration (platforms, containers, templates)
lib/
  compat.sh             # Cross-platform helpers (sed_inplace, expand_vars)
  logging.sh            # Structured logging with severity levels
  json.sh               # jq wrapper with auto-installation
  module.sh             # Module lifecycle, containerization, Docker integration
  backup.sh             # Backup/restore utilities
  alias.sh              # ZSH alias management with markers
  windows/              # Windows-specific PowerShell libraries
modules/<name>/
  config.json           # Module configuration (runlevel, deps, paths, aliases)
  <name>.sh             # Bash implementation
  <name>.ps1            # PowerShell implementation (Windows modules)
```

## Key Conventions

- **Module naming**: Directory name = script name = config key (e.g., `modules/git/git.sh`)
- **Module loading order**: Controlled by `runlevel` in each module's `config.json`
- **Library sourcing**: Every module sources `compat.sh`, `logging.sh`, `json.sh`, `module.sh`, `backup.sh`, `alias.sh`
- **Environment variable expansion**: Use `expand_vars` (from `compat.sh`), never `eval echo`
- **Portable sed**: Use `sed_inplace` (from `compat.sh`), never raw `sed -i`
- **Platform paths**: Config uses `${DEVENV_ROOT}`, `${DEVENV_DATA_DIR}`, `${HOME}` - expanded at runtime
- **State tracking**: Module installation state in `$HOME/.devenv/state/<module>.state`
- **Backup before modify**: Always call `backup_file` before overwriting user configs

## Module Interface

Every module script handles these actions via a case statement:
- `install` - Install and configure the tool
- `remove` - Uninstall and clean up
- `verify` - Health check all components
- `info` - Display status and version info

## Common Commands

```bash
./devenv install <module>     # Install a module
./devenv remove <module>      # Remove a module
./devenv verify <module>      # Verify installation
./devenv info <module>        # Show module info
./devenv backup               # Backup all configs
./devenv restore              # Restore from backup
make lint                     # Run ShellCheck + JSON validation
make test                     # Run bats tests
```

## Development Guidelines

- Shell scripts use `set -euox pipefail`
- PowerShell uses `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`
- JSON configs validated with `jq`
- Line endings: `.sh` = LF, `.ps1` = CRLF (enforced by `.gitattributes`)
- All 16 modules: git, docker, vscode, python, nodejs, conda, zsh, powershell, terminal, winget, phaser, tiled, ldtk, react, registry
- Windows-only modules: terminal, powershell, winget, registry
- Cross-platform modules: git, docker, vscode, python, nodejs

## Known Issues / Technical Debt

- `devenv.ps1` is a 1,188-line monolith that needs refactoring into `lib/windows/` modules
- No unit tests exist yet (planned: bats-core for bash, Pester for PowerShell)
- CI only runs on ubuntu-latest (needs Windows and macOS runners)
- macOS platform support is less complete than Linux/Windows
- Environment templates defined in `config.json` but `devenv init <template>` not yet implemented
- No JSON Schema validation for config files

## GitHub Project

Modernization tracked at: https://github.com/users/imcalderon/projects/4
