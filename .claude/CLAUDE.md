# DevEnv - Claude Code Instructions

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

## Project Conventions

### Shell Scripts
- Use `set -euo pipefail` (bash) or `set -eu` (POSIX sh)
- Source library files from `lib/`: `compat.sh`, `logging.sh`, `json.sh`, `module.sh`, `backup.sh`, `alias.sh`
- Use `log "LEVEL" "message" "module"` for logging (levels: INFO, WARN, ERROR, DEBUG)
- Use `sed_inplace` from `compat.sh` instead of raw `sed -i`
- Use `expand_vars` for variable expansion, never `eval echo`

### PowerShell Scripts
- Use `Set-StrictMode -Version Latest`
- Use `$ErrorActionPreference = 'Stop'`
- Windows-specific modules go in `lib/windows/`

### Module Structure
Each module in `modules/<name>/` must have:
- `config.json` - Module configuration (runlevel, deps, paths, aliases)
- `<name>.sh` - Bash implementation with actions: install, remove, verify, info
- `<name>.ps1` - PowerShell implementation (Windows modules)

### Testing
- Bash tests: `bats-core` in `tests/`
- PowerShell tests: `Pester` (planned)
- Run: `make test` or `make lint`

## Available Tools in DevEnv

When this devenv is active, these tools are available:

| Tool | Command | Purpose |
|------|---------|---------|
| Python | `py`, `py-pip`, `py-fmt`, `py-lint` | Python development |
| Node.js | `node`, `npm`, `nvm` | JavaScript development |
| Conda | `conda`, `ca`, `ci` | Environment management |
| Git | `git` | Version control |
| Docker | `docker` (via WSL integration) | Containerization |
| VSCode | `code` | Editor (Windows integration in WSL) |

## Common Tasks

```bash
# Install all modules
./devenv install

# Install specific module
./devenv install python

# Verify installation
./devenv verify

# Run linting
make lint

# Run tests
make test
```

## GitHub Integration

- Project board: https://github.com/users/imcalderon/projects/4
- Create issues with: `gh issue create --repo imcalderon/devenv`
- Use labels: `bug`, `enhancement`, `platform`, `docs`
