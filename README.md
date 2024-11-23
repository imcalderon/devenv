# Advanced Development Environment Setup System

## Overview
This system provides an automated, modular setup for a complete development environment on Linux systems, focusing on Red Hat-based distributions. It includes comprehensive configurations for C++, Python, and ML development, with robust shell customization, local package management, and containerized workflows.

## 🌟 Core Features

### System Components
- 🛠️ Automated system configuration and package management
- 🐳 Docker configuration with production-ready defaults
- 📝 VS Code setup with curated extensions
- 🐍 Conda environment management with multiple presets
- 🔧 ZSH configuration with Powerlevel10k and custom plugins
- 📦 Local package development infrastructure
- 🔄 Backup and restore capabilities
- 🏥 System health monitoring and self-healing
- 📊 Comprehensive system reporting

### Development Environments

#### C++ Development
```bash
conda activate cpp
```
- Complete build toolchain (GCC, CMake, Ninja)
- Debug tools (GDB, ccache)
- Key libraries (Boost, Eigen, fmt, spdlog)
- Testing frameworks (Catch2, benchmark)
- Documentation tools (Doxygen)

#### Python Development
```bash
conda activate python
```
- Core Python 3.11 environment
- Data science stack (NumPy, Pandas, SciPy)
- Visualization tools (Matplotlib, Seaborn)
- Development tools (pytest, black, flake8, mypy)
- Documentation (Sphinx)

#### Machine Learning
```bash
conda activate ml
```
- Deep learning frameworks (TensorFlow, PyTorch)
- CUDA support (cudatoolkit, cupy)
- Visualization and monitoring (Tensorboard)
- Data processing tools

### ZSH Environment
- Powerlevel10k theme with optimal configuration
- Custom plugins for development workflows
- Intelligent command suggestions
- Syntax highlighting
- Git integration
- Development shortcuts and aliases

## 📥 Installation

### Prerequisites
```bash
# Red Hat-based Linux distribution
# Sudo privileges required
sudo dnf groupinstall "Development Tools"
```

### Quick Start
```bash
# Clone repository
git clone https://github.com/yourusername/devenv.git
cd devenv

# Make scripts executable
chmod +x devenv.sh
chmod +x lib/*.sh

# Run installation
./devenv.sh install
```

### Command Reference
```bash
./devenv.sh install  # Full environment setup
./devenv.sh health  # System health check
./devenv.sh heal    # Auto-fix issues
./devenv.sh revert  # Revert changes
```

## 📁 Directory Structure
```
devenv/
├── devenv.sh              # Main script
├── README.md             # Documentation
└── lib/
    ├── logging.sh       # Logging system
    ├── backup.sh        # Backup/restore
    ├── health.sh        # Health monitoring
    ├── vscode.sh        # VS Code setup
    ├── docker.sh        # Docker config
    ├── conda.sh         # Conda management
    ├── zsh.sh           # ZSH configuration
    └── report.sh        # System reporting
```

## 💻 Development Workflow

### ZSH Shortcuts

#### Project Navigation
```bash
cddev     # Development directory
cdproj    # Projects directory
cddock    # Docker directory
cdpkg     # Packages directory
```

#### Git Operations
```bash
gs        # git status
ga        # git add
gc        # git commit
gp        # git push
gl        # git pull
gd        # git diff
gco       # git checkout
```

#### Development Tools
```bash
dc        # docker-compose
k         # kubectl
py        # python
jupynb    # jupyter notebook
jupylab   # jupyter lab
```

### Project Creation
```bash
# Create new project
create_project myproject python
create_project mycpplib cpp

# Project structure created automatically
myproject/
├── src/
├── tests/
├── docs/
└── README.md
```

## 📦 Package Development

### Local Package Management
```bash
# Create new package
$HOME/Development/packages/create_package.sh cpp math-lib 0.1.0
$HOME/Development/packages/create_package.sh python data-tools 0.1.0

# Build package
build_local_package "$LOCAL_PKG_DIR/src/math-lib" cpp

# Install in environment
install_local_package math-lib 0.1.0 cpp
```

### Package Structure
```
packages/
├── src/                  # Source code
├── dist/                # Built packages
├── build/              # Build artifacts
├── docs/              # Documentation
└── templates/        # Package templates
    ├── cpp/
    └── python/
```

## 🐍 Conda Management

### Environment Operations
```bash
# Create environment
conda create -n myenv -y

# Activate environment
conda activate myenv

# Update all environments
update_environments
```

### Available Templates
- `cpp`: C++ development
- `python`: Python data science
- `ml`: Machine learning

## ⚙️ Configuration Files

### ZSH Configuration
Location: `$HOME/.zshrc`
```bash
# Custom aliases
alias dc='docker-compose'
alias k='kubectl'
alias py='python'

# Development functions
mkcd() { mkdir -p "$1" && cd "$1"; }
extract() { # Universal extraction }
create_project() { # Project scaffolding }
```

### Conda Configuration
Location: `$HOME/.condarc`
```yaml
channels:
  - conda-forge
  - defaults
channel_priority: strict
```

### Docker Configuration
Location: `/etc/docker/daemon.json`
```json
{
    "default-memory-swap": "1G",
    "memory": "8G",
    "cpu-shares": 1024
}
```

## 🏥 Health Monitoring

### System Checks
```bash
# Run health check
./devenv.sh health

# Auto-heal issues
./devenv.sh heal
```

Monitored Components:
- System packages
- Development tools
- Docker service
- Conda environments
- VS Code extensions
- Development directories
- ZSH configuration

## 🔄 Backup and Recovery

### Automatic Backups
- Configuration files
- VS Code settings
- Git configuration
- ZSH configuration
- Shell customizations

### Recovery Operations
```bash
# Revert to last good state
./devenv.sh revert
```

## 📊 Logging and Reporting

### Log Files
```bash
$HOME/.devenv/logs/devenv_YYYYMMDD_HHMMSS.log
```

### System Reports
```bash
$HOME/.devenv/logs/system_report_YYYYMMDD_HHMMSS.txt
$HOME/.devenv/logs/system_report_YYYYMMDD_HHMMSS.html
```

## 🔧 Troubleshooting

### Common Issues

#### ZSH Theme Issues
```bash
# Rebuild font cache
fc-cache -f -v

# Verify Powerlevel10k installation
ls ~/.oh-my-zsh/custom/themes/powerlevel10k
```

#### Conda Environment Issues
```bash
conda clean --all
conda update --all
```

#### Docker Service Issues
```bash
sudo systemctl status docker
sudo journalctl -xu docker
```

## 🤝 Contributing
1. Fork repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

## 📄 License
MIT License - see LICENSE file

## 🙏 Acknowledgments
- Oh My ZSH community
- Powerlevel10k developers
- Conda team
- Docker team
- VS Code team
- All open-source contributors

## 📝 Version History
- 1.1.0: Added ZSH configuration
  - Powerlevel10k integration
  - Custom plugins and themes
  - Development shortcuts
- 1.0.0: Initial release
  - Basic environment setup
  - Conda integration
  - Docker support
  - VS Code configuration

---

For module-specific documentation, see the corresponding files in the `lib/` directory.