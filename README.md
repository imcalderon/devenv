# DevEnv

Cross-platform development environment manager with modular tool installation for Windows, Linux, and macOS.

## Overview

DevEnv provides a consistent way to set up development tools across platforms. Each tool is a self-contained module that handles installation, configuration, verification, and removal.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/imcalderon/devenv.git
cd devenv

# Linux/macOS: Install all modules
./devenv install

# Windows PowerShell: Install all modules
.\devenv.ps1 install

# Install specific modules
./devenv install git python vscode
```

## Platform Support

| Module | Linux | macOS | Windows | Description |
|--------|:-----:|:-----:|:-------:|-------------|
| git | Yes | Yes | - | Git with SSH and shell integration |
| docker | Yes | Yes | - | Docker with container management |
| python | Yes | Yes | Yes | Python with venv and packages |
| vscode | Yes | Yes | Yes | VS Code with extensions |
| nodejs | Yes | Yes | - | Node.js with nvm |
| conda | Yes | Yes | - | Conda environment manager |
| zsh | Yes | Yes | - | Zsh with vi-mode |
| powershell | - | - | Yes | PowerShell with modules |
| terminal | - | - | Yes | Windows Terminal configuration |
| winget | - | - | Yes | Windows package manager |
| registry | - | - | Yes | Windows registry settings |
| react | Yes | Yes | - | React development setup |
| tiled | Yes | Yes | - | Tiled map editor |
| ldtk | Yes | Yes | - | LDtk level editor |

## Commands

```bash
./devenv install [modules...]    # Install modules (all if none specified)
./devenv remove [modules...]     # Remove modules
./devenv verify [modules...]     # Verify installation
./devenv info [modules...]       # Show module status
./devenv backup                  # Backup configurations
./devenv restore                 # Restore from backup
./devenv list                    # List available modules
./devenv status                  # Show environment status
```

## Project Structure

```
devenv/
├── devenv                  # Entry point (detects platform)
├── devenv.sh               # Linux/macOS orchestrator
├── devenv.ps1              # Windows orchestrator
├── config.json             # Global configuration
├── lib/
│   ├── compat.sh           # Cross-platform helpers
│   ├── logging.sh          # Logging utilities
│   ├── json.sh             # JSON/jq helpers
│   ├── module.sh           # Module lifecycle
│   ├── backup.sh           # Backup utilities
│   ├── alias.sh            # Shell alias management
│   └── windows/            # Windows PowerShell libraries
├── modules/
│   └── <name>/
│       ├── config.json     # Module configuration
│       ├── <name>.sh       # Bash implementation
│       └── <name>.ps1      # PowerShell implementation
├── wsl/                    # WSL provisioning scripts
└── tests/                  # Test suite (bats-core)
```

## Module Interface

Each module implements these actions:

- `install` - Install and configure the tool
- `remove` - Uninstall and clean up
- `verify` - Health check all components
- `info` - Display status and version

## WSL Support

DevEnv includes scripts for provisioning WSL environments:

```powershell
# Reset and provision AlmaLinux WSL
.\wsl\reset-wsl.ps1

# Full setup with devenv + Claude Code + gh CLI
.\wsl\reset-wsl.ps1 -FullSetup
```

## Development

```bash
# Run linting (ShellCheck + JSON validation)
make lint

# Run tests
make test
```

### Conventions

- Shell scripts: `set -euo pipefail`
- PowerShell: `Set-StrictMode -Version Latest`
- Line endings: `.sh` = LF, `.ps1` = CRLF (via .gitattributes)
- Use library functions for logging, JSON, backups

## Work in Progress

Current development is tracked on the [GitHub Project Board](https://github.com/users/imcalderon/projects/4).

### Known Issues

- Windows: Several modules have verification issues ([#39](https://github.com/imcalderon/devenv/issues/39))
- Windows: State reporting inconsistencies ([#36](https://github.com/imcalderon/devenv/issues/36))
- macOS: Platform support less complete than Linux/Windows
- CI runs on Linux only (Windows/macOS runners planned)

### Roadmap

- [ ] Fix Windows module verification
- [ ] Add Pester tests for PowerShell modules
- [ ] Multi-platform CI (Windows, macOS runners)
- [ ] Environment templates (`devenv init <template>`)
- [ ] JSON Schema validation for configs

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run `make lint` and `make test`
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE)
