#!/usr/bin/env bash
# vfx-bootstrap - Ubuntu/Debian platform support
# This script is sourced by bootstrap.sh

set -euo pipefail

#------------------------------------------------------------------------------
# Install Ubuntu/Debian specific dependencies
#------------------------------------------------------------------------------
install_platform_dependencies() {
    log_info "Installing Ubuntu/Debian dependencies..."

    # Update package lists
    sudo apt-get update

    # Core build tools
    sudo apt-get install -y \
        build-essential \
        git \
        curl \
        wget \
        ca-certificates \
        pkg-config \
        cmake \
        ninja-build

    # Development libraries commonly needed for VFX builds
    sudo apt-get install -y \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses5-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libffi-dev \
        liblzma-dev

    # OpenGL development (needed for USD viewer)
    sudo apt-get install -y \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libegl1-mesa-dev \
        libx11-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev

    # Additional tools
    sudo apt-get install -y \
        patchelf \
        file

    log_info "Ubuntu/Debian dependencies installed"
}

#------------------------------------------------------------------------------
# Check Ubuntu-specific requirements
#------------------------------------------------------------------------------
check_platform_requirements() {
    log_info "Checking Ubuntu/Debian requirements..."

    # Check Ubuntu version (recommend 22.04+)
    if [[ -n "${VFX_BOOTSTRAP_VERSION_ID:-}" ]]; then
        local major_version="${VFX_BOOTSTRAP_VERSION_ID%%.*}"
        if [[ "$major_version" -lt 20 ]]; then
            log_warn "Ubuntu $VFX_BOOTSTRAP_VERSION_ID detected."
            log_warn "Recommended: Ubuntu 22.04 or later for VFX Platform 2024"
        fi
    fi

    # Check available disk space (need at least 20GB for full build)
    local available_space
    available_space=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ "$available_space" -lt 20 ]]; then
        log_warn "Low disk space: ${available_space}GB available"
        log_warn "Recommended: At least 20GB for full USD build"
    fi

    log_info "Platform requirements check complete"
}

#------------------------------------------------------------------------------
# Get recommended GCC version for VFX Platform 2024
#------------------------------------------------------------------------------
get_recommended_gcc() {
    # VFX Platform 2024 specifies GCC 11.2.1
    echo "11"
}

#------------------------------------------------------------------------------
# Install specific GCC version if needed
#------------------------------------------------------------------------------
install_gcc_version() {
    local version="${1:-11}"

    log_info "Checking GCC version..."

    if command -v gcc-${version} &>/dev/null; then
        log_info "GCC $version already installed"
        return 0
    fi

    log_info "Installing GCC $version..."
    sudo apt-get install -y gcc-${version} g++-${version}

    # Set as default (optional)
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${version} 100
    sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${version} 100

    log_info "GCC $version installed"
}
