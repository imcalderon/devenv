# Development Environment Setup System

A modular system for automating the setup and maintenance of development environments across Linux systems. The system provides automated installation, configuration, and management of common development tools and environments.

## Overview

This system follows a modular approach where each component (like ZSH, Docker, VS Code, etc.) is managed independently but follows a consistent pattern. Each module can be enabled/disabled via configuration and handles its own installation, removal, and verification.

### Key Features

- 🔧 Modular design with consistent patterns
- ⚙️ YAML-based configuration
- 🔄 Automated backup and restore
- ✅ Built-in verification
- 📝 Comprehensive logging
- 🚀 Support for multiple Linux distributions

## System Requirements

- Bash 4.0+
- Linux (Debian/Ubuntu or RHEL/CentOS/Fedora)
- Internet connection for package downloads
- sudo privileges

## Directory Structure

```
.
├── config.yaml           # Main configuration file
├── devenv.sh            # Main entry script
├── lib/                 # Library modules
│   ├── logging.sh       # Logging utilities
│   ├── yaml_parser.sh   # YAML parsing utilities
│   ├── module_base.sh   # Base module functionality
│   ├── backup/         # Backup module
│   ├── conda/          # Conda module
│   ├── docker/         # Docker module
│   ├── vscode/         # VS Code module
│   └── zsh/            # ZSH module
└── setup.log           # System log file
```

## Modules

### Currently Supported

- **ZSH**: Shell environment with Oh My ZSH and Powerlevel10k
- **VS Code**: Editor setup with extensions and settings
- **Docker**: Container runtime with daemon configuration
- **Conda**: Python environment management with predefined environments
- **Backup**: System configuration backup and restore

Each module follows a standard lifecycle:
- `grovel`: Check prerequisites and dependencies
- `install`: Install and configure the component
- `remove`: Remove configurations (optionally the software)
- `verify`: Verify the installation and configuration
- `update`: Update the component (where applicable)

## Configuration

All configuration is managed through `config.yaml`. Example configuration:

```yaml
modules:
  zsh:
    enabled: true
    theme: "powerlevel10k/powerlevel10k"
    plugins:
      - git
      - docker
      # ... more plugins
  
  vscode:
    enabled: true
    settings:
      editor:
        - key: "workbench.colorTheme"
          value: "Default High Contrast"
    # ... more settings

  # ... other module configurations
```

See `config.yaml` for complete configuration options.

## Usage

### Basic Usage

```bash
# Install all enabled modules
./devenv.sh install

# Verify all enabled modules
./devenv.sh verify

# Remove configurations
./devenv.sh remove
```

### Backup Management

```bash
# Create a backup
./devenv.sh backup

# Restore from latest backup
./devenv.sh restore

# Restore from specific backup
./devenv.sh restore /path/to/backup
```

### Individual Module Management

```bash
# Install specific module
./lib/docker/docker.sh install

# Verify specific module
./lib/vscode/vscode.sh verify
```

## Logging

The system maintains detailed logs at `setup.log`. All operations are logged with timestamps and severity levels:
- INFO: Normal operations
- WARN: Non-critical issues
- ERROR: Critical issues that need attention

## Extending the System

### Adding a New Module

1. Create a new directory under `lib/` for your module
2. Create the main module script following the existing pattern:
   ```bash
   #!/bin/bash
   source "${SCRIPT_DIR}/../module_base.sh"
   
   grovel_mymodule() {
     # Check dependencies
   }
   
   install_mymodule() {
     # Install and configure
   }
   
   # ... other required functions
   ```
3. Add configuration section to `config.yaml`
4. Test the module with `grovel`, `install`, and `verify` operations

### Configuration Guidelines

- All configurable values should be in `config.yaml`
- Use environment variable expansion in paths
- Group related settings logically
- Include documentation for non-obvious settings

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo chmod +x devenv.sh
   sudo chmod +x lib/**/*.sh
   ```

2. **Module Not Found**
   - Check module is enabled in `config.yaml`
   - Verify module directory exists
   - Check execute permissions

3. **Configuration Errors**
   - Validate `config.yaml` syntax
   - Check logs in `setup.log`
   - Run verify operation

### Debug Mode

Enable detailed logging:
```bash
export LOG_LEVEL=DEBUG
./devenv.sh install
```

## Best Practices

1. Always run `verify` after `install`
2. Create backups before major changes
3. Review logs for errors
4. Keep `config.yaml` in version control
5. Test changes in isolated environment first

## Contributing

1. Fork the repository
2. Create feature branch
3. Follow existing patterns and coding style
4. Add tests and documentation
5. Submit pull request

## License

MIT License - See LICENSE file for details

## Credits

- YAML parser based on https://github.com/jasperes/bash-yaml
- Inspiration from various development environment management tools

## Support

- File issues on GitHub
- Check setup.log for detailed errors
- Consult module-specific documentation

For more details on each module, consult the individual module documentation in their respective directories.