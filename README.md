# DevEnv - Development Environment Manager 🛠️

A comprehensive, modular development environment manager that automates the setup and configuration of development tools and services.

## Features 🌟

- **Modular Architecture**: Each tool/service is a self-contained module
- **State Management**: Tracks installation state and ensures idempotent operations
- **Backup Support**: Automatic backup of existing configurations
- **Shell Integration**: ZSH configuration with custom aliases and functions
- **Logging**: Detailed logging with different verbosity levels
- **JSON Configuration**: Flexible, extensible configuration system

## Included Modules 📦

- **Python** 🐍
  - Complete Python development environment
  - IPython, Jupyter, and development tools
  - Code quality tools (Black, Pylint, Flake8)
  - Common data science packages

- **ZSH** 💻
  - Oh My ZSH framework
  - Powerlevel10k theme
  - Curated plugin selection
  - Custom aliases and functions

- **Git** 🔄
  - SSH key management
  - GitHub integration
  - Custom aliases
  - Best practice configurations

- **VSCode** 📝
  - Extension management
  - Optimized settings
  - Language-specific configurations
  - Debugging profiles

- **Docker** 🐳
  - Docker Engine CE
  - Docker Compose
  - Resource management
  - Helper functions

- **Conda** 🐍
  - Miniconda installation
  - Environment management
  - Channel configuration
  - IDE integration

## Requirements 📋

- Linux-based operating system (Ubuntu/Debian or RHEL/CentOS/AlmaLinux)
- Bash shell
- Internet connection for package downloads
- sudo privileges

## Installation 🚀

1. Clone the repository:
```bash
git clone https://github.com/yourusername/devenv.git
cd devenv
```

2. Install all modules:
```bash
./devenv.sh install
```

Or install specific modules:
```bash
./devenv.sh install python
./devenv.sh install zsh
```

## Usage 💡

### Basic Commands

```bash
# Install modules
./devenv.sh install [module]        # Install all or specific module
./devenv.sh install [module] --force # Force reinstallation

# Remove modules
./devenv.sh remove [module]         # Remove module configuration

# Verify installation
./devenv.sh verify [module]         # Verify module installation

# Show module information
./devenv.sh info [module]           # Display module details
```

### Module Management

```bash
# Create new module
./generate.sh mymodule             # Generate new module template

# Backup configurations
./devenv.sh backup [module]        # Create backup of module configs

# Restore configurations
./devenv.sh restore [module]       # Restore from latest backup
```

## Configuration 📝

### Global Configuration

Located at `config.json`:
```json
{
    "version": "1.0.0",
    "paths": {
        "root": "$HOME/.devenv",
        "logs": "$HOME/.devenv/logs",
        "backups": "$HOME/.devenv/backups",
        "state": "$HOME/.devenv/state",
        "modules": "$HOME/.devenv/modules"
    }
}
```

### Module Configuration

Each module has its own `config.json` in its directory:
```json
{
    "enabled": true,
    "runlevel": 1,
    "backup": {
        "paths": []
    },
    "shell": {
        "paths": {},
        "aliases": {}
    }
}
```

## Directory Structure 📁

```
devenv/
├── config.json           # Global configuration
├── devenv.sh            # Main script
├── generate.sh          # Module generator
├── lib/                 # Core utilities
│   ├── logging.sh
│   ├── json.sh
│   ├── module.sh
│   ├── backup.sh
│   └── alias.sh
└── modules/             # Module implementations
    ├── python/
    ├── zsh/
    ├── git/
    ├── vscode/
    ├── docker/
    └── conda/
```

## Creating New Modules 🔧

1. Generate module template:
```bash
./generate.sh mymodule
```

2. Edit module configuration:
```bash
vim modules/mymodule/config.json
```

3. Implement module functionality:
```bash
vim modules/mymodule/mymodule.sh
```

## Best Practices 🎯

1. **Always Backup**: Use the backup system before making changes
2. **State Management**: Track component states properly
3. **Idempotency**: Ensure operations can be repeated safely
4. **Error Handling**: Use the logging system effectively
5. **Configuration**: Keep sensitive data out of configs

## Troubleshooting 🔍

### Common Issues

1. **Permission Errors**
   - Ensure proper sudo privileges
   - Check file permissions in ~/.devenv

2. **Module Dependencies**
   - Verify all required packages are available
   - Check network connectivity

3. **State Inconsistencies**
   - Clear state with `rm ~/.devenv/state/*`
   - Reinstall module with --force

### Logging

- Check logs in `~/.devenv/logs/`
- Use `LOG_LEVEL=DEBUG` for verbose output

## Contributing 🤝

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

## License 📄

This project is licensed under the MIT License - see the LICENSE file for details.

## Credits 👏

- Original implementation by Ivan Calderon
- Inspired by various dotfile managers and development environment tools

## Support 💪

For support, please:
1. Check the documentation
2. Review closed issues
3. Open new issue with detailed information

Remember to include logs and system information when reporting issues.