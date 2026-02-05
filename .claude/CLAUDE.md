# DevEnv - Claude Code Instructions

## Project Overview

DevEnv is a cross-platform, hermetic development environment manager. It provides modular, containerized development tool installation and configuration across Windows (native + WSL), Linux, and macOS.

## Architecture

```
devenv                  # Entry point: detects platform, routes to .sh or .ps1
devenv.sh               # Linux/macOS orchestrator (sources lib/*.sh)
devenv.ps1              # Windows orchestrator
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
wsl/                    # WSL provisioning scripts
```

## Platform Detection

This project runs on multiple platforms. Detect and use the correct package manager:

| Distribution | Package Manager | Detection |
|-------------|-----------------|-----------|
| AlmaLinux, RHEL, Fedora, CentOS | `dnf` (or `yum`) | `command -v dnf` |
| Ubuntu, Debian | `apt-get` | `command -v apt-get` |
| macOS | `brew` | `command -v brew` |
| Windows | `winget` or `choco` | PowerShell environment |

**WSL Detection**: Check `/proc/version` for "microsoft" to detect WSL environments.

```bash
# Example platform detection
if grep -qi microsoft /proc/version 2>/dev/null; then
    # WSL environment - may use Windows tools
elif command -v dnf &>/dev/null; then
    # RHEL-based (AlmaLinux, Fedora, CentOS)
elif command -v apt-get &>/dev/null; then
    # Debian-based (Ubuntu, Debian)
fi
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

### Shell Scripts
- Use `set -euo pipefail` (bash) or `set -eu` (POSIX sh)
- Source library files from `lib/`
- Use `log "LEVEL" "message" "module"` for logging (levels: INFO, WARN, ERROR, DEBUG)

### PowerShell Scripts
- Use `Set-StrictMode -Version Latest`
- Use `$ErrorActionPreference = 'Stop'`
- Windows-specific modules go in `lib/windows/`

## Module Interface

Every module script handles these actions via a case statement:
- `install` - Install and configure the tool
- `remove` - Uninstall and clean up
- `verify` - Health check all components
- `info` - Display status and version info

### Module Structure
Each module in `modules/<name>/` must have:
- `config.json` - Module configuration (runlevel, deps, paths, aliases)
- `<name>.sh` - Bash implementation with actions: install, remove, verify, info
- `<name>.ps1` - PowerShell implementation (Windows modules)

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

## Available Tools

When devenv is active, these tools are available:

| Tool | Command | Purpose |
|------|---------|---------|
| Python | `py`, `py-pip`, `py-fmt`, `py-lint` | Python development |
| Node.js | `node`, `npm`, `nvm` | JavaScript development |
| Conda | `conda`, `ca`, `ci` | Environment management |
| Git | `git` | Version control |
| Docker | `docker` (via WSL integration) | Containerization |
| VSCode | `code` | Editor (Windows integration in WSL) |

## Modules

- **All modules**: git, docker, vscode, python, nodejs, conda, zsh, powershell, terminal, winget, phaser, tiled, ldtk, react, registry
- **Windows-only**: terminal, powershell, winget, registry
- **Cross-platform**: git, docker, vscode, python, nodejs

## Testing

- Bash tests: `bats-core` in `tests/`
- PowerShell tests: `Pester` (planned)
- Run: `make test` or `make lint`
- Line endings: `.sh` = LF, `.ps1` = CRLF (enforced by `.gitattributes`)

## Known Issues / Technical Debt

- `devenv.ps1` needs refactoring into `lib/windows/` modules
- CI only runs on ubuntu-latest (needs Windows and macOS runners)
- macOS platform support is less complete than Linux/Windows
- Environment templates defined in `config.json` but `devenv init <template>` not yet implemented
- No JSON Schema validation for config files

## GitHub Integration

- Project board: https://github.com/users/imcalderon/projects/4
- Create issues with: `gh issue create --repo imcalderon/devenv`
- Use labels: `bug`, `enhancement`, `platform`, `docs`
