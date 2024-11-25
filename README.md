# Development Environment Setup

An automated system for configuring and managing development environments across Linux distributions. The system uses a modular approach for installing, configuring, and maintaining common development tools.

## Core Features

- Modular architecture with independent components
- YAML-based configuration
- Automated backup/restore
- Distribution-agnostic (Debian/Ubuntu, RHEL/CentOS/Fedora)
- Comprehensive logging
- Version control friendly

## Prerequisites

- Linux with Bash 4.0+
- sudo privileges
- Internet connection
- Package manager (apt/dnf)

## Modules

| Module  | Description | Key Features |
|---------|-------------|--------------|
| ZSH     | Shell configuration | Oh My ZSH, Powerlevel10k, Custom plugins |
| VSCode  | Editor setup | Extensions, Settings sync, Keybindings |
| Docker  | Container runtime | Daemon config, Helper functions, Compose templates |
| Conda   | Python environments | Pre-configured envs, Package management |
| Backup  | State management | Automated backups, Retention policies |

## Quick Start

```bash
# Install all modules
./devenv.sh install

# Install single module
./devenv.sh install zsh

# Verify setup
./devenv.sh verify

# Create/restore backups
./devenv.sh backup
./devenv.sh restore
```

## Configuration

The system is configured through `config.yaml`:

```yaml
modules:
  _order:
    - zsh
    - vscode
    - docker
    - conda
    - backup

  zsh:
    enabled: true
    theme: "powerlevel10k/powerlevel10k"
    plugins:
      - git
      - docker

  vscode:
    enabled: true
    extensions:
      development:
        - id: "ms-python.python"
          required: true
```

## Module Lifecycle

Each module implements standard operations:
- `grovel`: Dependency checking
- `install`: Setup and configuration
- `remove`: Configuration removal
- `verify`: Installation verification
- `update`: Component updates

## Extending

To add a new module:

1. Create module directory in `lib/`
2. Implement lifecycle functions
3. Add configuration to `config.yaml`
4. Test with `grovel`, `install`, `verify`

## Troubleshooting

Common fixes:

```bash
# Fix permissions
sudo chmod +x devenv.sh
sudo chmod +x lib/**/*.sh

# Enable debug logging
export LOG_LEVEL=DEBUG
./devenv.sh install

# View logs
tail -f $HOME/.devenv/logs/latest.log
```

## Project Structure

```
.
├── config.yaml           # Configuration
├── devenv.sh            # Entry point
└── lib/                 # Modules
    ├── logging.sh
    ├── yaml_parser.sh
    ├── module_base.sh
    ├── backup/
    ├── conda/
    ├── docker/
    ├── vscode/
    └── zsh/
```

## License

MIT License

## Support

- Check logs in `$HOME/.devenv/logs`
- File issues on GitHub
- Review module documentation
