#!/usr/bin/env bash
# vfx-bootstrap - Conda setup module
# Provides functions for managing conda/miniforge installations

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
MINIFORGE_VERSION="${MINIFORGE_VERSION:-24.3.0-0}"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniforge3}"

#------------------------------------------------------------------------------
# Check if conda is installed
#------------------------------------------------------------------------------
is_conda_installed() {
    [[ -x "$CONDA_ROOT/bin/conda" ]] || command -v conda &>/dev/null
}

#------------------------------------------------------------------------------
# Get conda installation path
#------------------------------------------------------------------------------
get_conda_root() {
    if [[ -x "$CONDA_ROOT/bin/conda" ]]; then
        echo "$CONDA_ROOT"
    elif command -v conda &>/dev/null; then
        conda info --base
    else
        echo ""
    fi
}

#------------------------------------------------------------------------------
# Install Miniforge
#------------------------------------------------------------------------------
install_conda() {
    local conda_root="${1:-$CONDA_ROOT}"

    if [[ -x "$conda_root/bin/conda" ]]; then
        echo "Conda already installed at $conda_root"
        return 0
    fi

    echo "Installing Miniforge to $conda_root..."

    local arch os_name
    case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) echo "Unsupported architecture: $(uname -m)"; return 1 ;;
    esac

    case "$OSTYPE" in
        linux*)  os_name="Linux" ;;
        darwin*) os_name="MacOSX" ;;
        *) echo "Unsupported OS: $OSTYPE"; return 1 ;;
    esac

    local url="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-${os_name}-${arch}.sh"
    local installer="/tmp/miniforge-installer.sh"

    curl -fsSL "$url" -o "$installer"
    bash "$installer" -b -p "$conda_root"
    rm -f "$installer"

    # Initialize conda
    "$conda_root/bin/conda" init bash
    if command -v zsh &>/dev/null; then
        "$conda_root/bin/conda" init zsh
    fi

    echo "Miniforge installed successfully"
}

#------------------------------------------------------------------------------
# Configure conda for VFX builds
#------------------------------------------------------------------------------
configure_conda() {
    local conda_root
    conda_root=$(get_conda_root)

    if [[ -z "$conda_root" ]]; then
        echo "Conda not found. Install it first."
        return 1
    fi

    echo "Configuring conda..."

    # Set conda-forge as default channel
    "$conda_root/bin/conda" config --add channels conda-forge
    "$conda_root/bin/conda" config --set channel_priority strict

    # Disable auto-activation of base
    "$conda_root/bin/conda" config --set auto_activate_base false

    # Enable pip interop
    "$conda_root/bin/conda" config --set pip_interop_enabled true

    echo "Conda configured for VFX builds"
}

#------------------------------------------------------------------------------
# Create VFX build environment
#------------------------------------------------------------------------------
create_vfx_environment() {
    local env_name="${1:-vfx-build}"
    local python_version="${2:-3.11}"

    local conda_root
    conda_root=$(get_conda_root)

    if [[ -z "$conda_root" ]]; then
        echo "Conda not found. Install it first."
        return 1
    fi

    if "$conda_root/bin/conda" env list | grep -q "^${env_name} "; then
        echo "Environment '$env_name' already exists"
        return 0
    fi

    echo "Creating VFX build environment: $env_name (Python $python_version)"

    "$conda_root/bin/conda" create -n "$env_name" \
        python="$python_version" \
        conda-build \
        conda-verify \
        pip \
        -y

    echo "Environment '$env_name' created successfully"
}

#------------------------------------------------------------------------------
# Install conda-build tools
#------------------------------------------------------------------------------
install_build_tools() {
    local conda_root
    conda_root=$(get_conda_root)

    if [[ -z "$conda_root" ]]; then
        echo "Conda not found. Install it first."
        return 1
    fi

    echo "Installing conda build tools..."

    "$conda_root/bin/conda" install -n base \
        conda-build \
        conda-verify \
        boa \
        -y

    echo "Conda build tools installed"
}

#------------------------------------------------------------------------------
# Print conda info
#------------------------------------------------------------------------------
print_conda_info() {
    local conda_root
    conda_root=$(get_conda_root)

    if [[ -z "$conda_root" ]]; then
        echo "Conda not installed"
        return 1
    fi

    echo "Conda Installation Info:"
    echo "========================"
    echo "Location: $conda_root"
    "$conda_root/bin/conda" --version
    echo ""
    echo "Environments:"
    "$conda_root/bin/conda" env list
    echo ""
    echo "Configured channels:"
    "$conda_root/bin/conda" config --show channels
}

#------------------------------------------------------------------------------
# Main entry point
#------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-info}" in
        install)
            install_conda "${2:-}"
            ;;
        configure)
            configure_conda
            ;;
        create-env)
            create_vfx_environment "${2:-vfx-build}" "${3:-3.11}"
            ;;
        install-tools)
            install_build_tools
            ;;
        info)
            print_conda_info
            ;;
        *)
            echo "Usage: $0 {install|configure|create-env|install-tools|info}"
            exit 1
            ;;
    esac
fi
