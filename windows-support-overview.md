# DevEnv Windows Support

## Overview

This document outlines the Windows support for the DevEnv project, which leverages Windows Subsystem for Linux (WSL) to provide a consistent development environment across Windows and Linux systems.

## Architecture

The Windows support follows these key principles:

1. **WSL as the Primary Runtime** - All DevEnv modules run within WSL
2. **Hermetic Environment** - Minimal impact on Windows native configuration
3. **Windows Integration** - Seamless access to Windows tools when needed
4. **Docker Desktop Support** - Optimized Docker integration via Docker Desktop
5. **VS Code Remote Development** - Leveraging VS Code's Remote-WSL extension

## Key Components

### 1. WSL Module

The WSL module (`modules/wsl`) manages the integration between Windows and WSL:

- **Configuration Management** - Optimizes WSL settings for development
- **Windows Terminal Integration** - Creates custom profile for DevEnv
- **Path Translation** - Handles path differences between Windows and Linux
- **Mount Optimization** - Improves performance of file system access
- **Network Configuration** - Manages port forwarding and networking

### 2. Docker Windows Integration

The Docker module has been extended to support Windows:

- **Docker Desktop Detection** - Identifies Docker Desktop installation
- **WSL Integration** - Configures WSL to use Docker Desktop
- **CLI-only Installation** - Installs only Docker CLI inside WSL
- **Windows-specific Aliases** - Commands to control Docker Desktop

### 3. VS Code Integration

The VS Code module has been enhanced for Windows support:

- **Remote-WSL Extension** - Automatic installation and configuration
- **Server Components** - Installation of VS Code server in WSL
- **Settings Optimization** - Configured for best performance in WSL
- **Cross-Platform Commands** - Aliases for both WSL and Windows VS Code

### 4. Windows Installer

A Windows-specific installer (`install.bat` and `install.ps1`) that:

- **Detects WSL** - Checks and installs WSL if not present
- **Configures WSL 2** - Ensures WSL 2 is set as default
- **Installs Linux Distribution** - Sets up the chosen Linux distribution
- **Deploys DevEnv** - Clones and installs DevEnv inside WSL
- **Integrates with Windows** - Creates shortcuts and Windows Terminal profile

## Installation Guide

See the [Windows Installation Guide](WINDOWS_INSTALL.md) for detailed instructions.

## Configuration Files

The Windows support includes the following configuration files:

1. **WSL Module Config** (`modules/wsl/config.json`)
   - WSL-specific settings
   - Windows path translation
   - Mount optimization

2. **Docker Windows Config** (`modules/docker/config_windows.json`)
   - Docker Desktop integration
   - CLI-only installation for WSL

3. **VS Code WSL Config** (`modules/vscode/config_windows.json`)
   - Remote-WSL extension settings
   - Polling settings for file watching
   - Path adjustments for WSL environment

## Helper Scripts

Several helper scripts are provided to manage Windows integration:

1. **Docker WSL Helper** (`docker_wsl.sh`)
   - Manages Docker Desktop from WSL
   - Configures Docker CLI in WSL

2. **VS Code WSL Helper** (`vscode_wsl.sh`)
   - Installs VS Code server components
   - Configures VS Code Remote-WSL extension

3. **Windows Installer** (`install.ps1`)
   - PowerShell script for Windows-side installation
   - WSL setup and configuration

## Usage Examples

### Using Docker with Windows Integration

```bash
# Start Docker Desktop from WSL
dstart

# Check Docker status
dcheck

# Run a container
docker run -it ubuntu bash

# Stop Docker Desktop
dstop
```

### Using VS Code with Windows Integration

```bash
# Open current directory in VS Code (WSL)
code .

# Open current directory in Windows VS Code
code-win .

# Open projects directory
code-proj
```

### Working with Windows Files

```bash
# Go to Windows home directory
cdwin

# Open Windows Explorer in current directory
explorer

# Open a file with Windows default application
open myfile.pdf
```

## Best Practices

1. **Keep Projects in Linux File System** - For best performance, store projects in the Linux file system (`/home/username/Projects`) rather than in mounted Windows drives.

2. **Use WSL Remoting** - When using VS Code, always use the Remote-WSL extension rather than working directly with files in the Windows file system.

3. **Use Windows Terminal** - Windows Terminal provides the best experience for working with WSL.

4. **Docker Volume Mounts** - When using Docker, mount volumes from the Linux file system rather than Windows paths.

5. **System Resources** - Adjust WSL resource allocation in `.wslconfig` based on your system capabilities.

## Troubleshooting

See the [Windows Troubleshooting Guide](WINDOWS_TROUBLESHOOTING.md) for common issues and solutions.

## Contributing

When contributing to Windows support:

1. Test changes in both Windows and Linux environments
2. Use conditional logic for Windows-specific code
3. Keep Windows-specific configuration separate
4. Document Windows-specific behavior
