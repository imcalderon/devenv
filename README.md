# Development Environment Setup

A modular, configurable system for setting up and managing a complete development environment on RHEL/CentOS-based systems. This toolset provides automated installation, configuration, health checking, and management of development tools and settings.

## 🚀 Features

- **Modular Design**: Separate scripts for each component (Docker, VS Code, Python, etc.)
- **Configuration Management**: YAML-based configuration for easy customization
- **Backup & Restore**: Automated backup and restoration of configurations
- **Health Monitoring**: System health checks and self-healing capabilities
- **Detailed Logging**: Comprehensive logging system with timestamps
- **Report Generation**: Detailed system reports in both text and HTML formats
- **MacBook Optimizations**: Special utilities and configurations for MacBook hardware

## 📋 Prerequisites

- RHEL/CentOS 8 or later
- Bash 4.0 or higher
- Internet connectivity
- Sudo privileges

## 🗂️ Project Structure

```
devenv/
├── config.yml                 # Main configuration file
├── devenv.sh                 # Main script
└── scripts/
    ├── lib/
    │   └── common.sh        # Shared functions and utilities
    ├── backup.sh            # Backup functionality
    ├── docker.sh            # Docker installation and setup
    ├── health.sh            # Health checking
    ├── node.sh              # Node.js/NVM setup
    ├── python.sh            # Python environment setup
    ├── report.sh            # System reporting
    ├── revert.sh            # Environment reversion
    ├── shell.sh             # Shell configuration
    ├── system.sh            # System package management
    ├── tools.sh             # Development tools setup
    ├── update.sh            # Update functionality
    └── vscode.sh            # VS Code setup
```

## 🛠️ Installation

1. Clone the repository:
```bash
git clone https://github.com/imcalderon/devenv/devenv.git
cd devenv
```

2. Make the main script executable:
```bash
chmod +x devenv.sh
```

3. Run the installation:
```bash
./devenv.sh install
```

## 📝 Configuration

The system is configured through `config.yml`. Here's an example configuration:

```yaml
paths:
  log_dir: "${HOME}/.devenv/logs"
  backup_dir: "${HOME}/.devenv/backups"
  vscode_config_dir: "${HOME}/.config/Code/User"
  scripts_dir: "${HOME}/Development/scripts"

versions:
  node: "lts"
  python: "3.11"
  docker: "latest"

packages:
  system:
    - git
    - curl
    - wget
    # Add more packages...
```

## 🎮 Usage

### Basic Commands

```bash
# Install development environment
./devenv.sh install

# Check system health
./devenv.sh health

# Attempt to fix issues
./devenv.sh heal

# Revert changes
./devenv.sh revert

# Update components
./devenv.sh update
```

### Logs and Reports

- Logs are stored in: `~/.devenv/logs/`
- System reports are generated in: `~/.devenv/logs/system_report_*.txt`
- HTML reports are available at: `~/.devenv/logs/system_report_*.html`

### Backup and Restore

The system automatically creates backups before making changes. Backups are stored in:
```
~/.devenv/backups/YYYYMMDD_HHMMSS/
```

## 🔧 Customization

### Adding New Packages

Edit `config.yml` to add new packages:

```yaml
packages:
  system:
    - your-new-package
  python:
    - your-new-python-package
```

### Adding New Components

1. Create a new script in the `scripts/` directory
2. Add configuration in `config.yml`
3. Update the main `devenv.sh` script to include the new component

## 🏥 Health Checks

The system performs health checks on:
- System packages
- Development tools
- Docker configuration
- VS Code extensions
- Python environment
- Node.js setup
- Shell configuration

## 🔒 Security Features

- Secure default configurations
- Backup before modifications
- Permission checks
- Package verification
- Network security settings

## 🐛 Troubleshooting

Common issues and solutions:

1. **Network Connectivity Issues**
   ```bash
   # Check network connectivity
   ./devenv.sh health
   # View logs for details
   tail -f ~/.devenv/logs/devenv_latest.log
   ```

2. **Permission Issues**
   ```bash
   # Ensure correct ownership
   sudo chown -R $USER:$USER ~/.devenv
   ```

3. **Docker Issues**
   ```bash
   # Reset Docker configuration
   ./devenv.sh revert docker
   # Reinstall Docker
   ./devenv.sh install docker
   ```

## 📊 Monitoring

Monitor your development environment:

```bash
# Generate system report
./devenv.sh report

# Check component status
./devenv.sh health

# View logs
tail -f ~/.devenv/logs/devenv_latest.log
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Please include:
- Clear description of changes
- Updated documentation
- Test results
- Any necessary configuration updates

## 📝 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Inspired by various development environment management tools
- Uses components from several open-source projects
- Community contributions and feedback

## ⚠️ Disclaimer

This tool makes significant changes to your system configuration. Always:
- Review the configuration before running
- Backup important data
- Test in a safe environment first
- Review logs for any issues

## 📞 Support

- File an issue in the GitHub repository
- Check the troubleshooting guide
- Review closed issues for solutions
- Check the logs for detailed error messages
