#!/usr/bin/env bash
# vfx-bootstrap - Rocky Linux/RHEL platform support
# This script is sourced by bootstrap.sh

set -euo pipefail

#------------------------------------------------------------------------------
# Install Rocky Linux/RHEL specific dependencies
#------------------------------------------------------------------------------
install_platform_dependencies() {
    log_info "Installing Rocky Linux/RHEL dependencies..."

    # Enable EPEL repository for additional packages
    sudo dnf install -y epel-release || true

    # Enable PowerTools/CRB for development packages
    if [[ -f /etc/rocky-release ]]; then
        sudo dnf config-manager --set-enabled crb || \
        sudo dnf config-manager --set-enabled powertools || true
    elif [[ -f /etc/redhat-release ]]; then
        sudo dnf config-manager --set-enabled codeready-builder-for-rhel-8-x86_64-rpms || \
        sudo dnf config-manager --set-enabled powertools || true
    fi

    # Core build tools
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y \
        git \
        curl \
        wget \
        ca-certificates \
        pkgconfig \
        cmake \
        ninja-build

    # Development libraries commonly needed for VFX builds
    sudo dnf install -y \
        openssl-devel \
        zlib-devel \
        bzip2-devel \
        readline-devel \
        sqlite-devel \
        ncurses-devel \
        xz-devel \
        tk-devel \
        libffi-devel

    # OpenGL development (needed for USD viewer)
    sudo dnf install -y \
        mesa-libGL-devel \
        mesa-libGLU-devel \
        mesa-libEGL-devel \
        libX11-devel \
        libXrandr-devel \
        libXinerama-devel \
        libXcursor-devel \
        libXi-devel

    # Additional tools
    sudo dnf install -y \
        patchelf \
        file

    log_info "Rocky Linux/RHEL dependencies installed"
}

#------------------------------------------------------------------------------
# Check Rocky-specific requirements
#------------------------------------------------------------------------------
check_platform_requirements() {
    log_info "Checking Rocky Linux/RHEL requirements..."

    # Check version (recommend 8+)
    if [[ -n "${VFX_BOOTSTRAP_VERSION_ID:-}" ]]; then
        local major_version="${VFX_BOOTSTRAP_VERSION_ID%%.*}"
        if [[ "$major_version" -lt 8 ]]; then
            log_warn "Rocky/RHEL $VFX_BOOTSTRAP_VERSION_ID detected."
            log_warn "Recommended: Rocky Linux 8 or later for VFX Platform 2024"
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
# Install specific GCC version via gcc-toolset
#------------------------------------------------------------------------------
install_gcc_version() {
    local version="${1:-11}"

    log_info "Checking GCC toolset version..."

    # On RHEL/Rocky, we use gcc-toolset for newer GCC versions
    local toolset="gcc-toolset-${version}"

    if rpm -q "$toolset" &>/dev/null; then
        log_info "GCC Toolset $version already installed"
        return 0
    fi

    log_info "Installing GCC Toolset $version..."
    sudo dnf install -y "$toolset"

    log_info "GCC Toolset $version installed"
    log_info "Enable with: scl enable $toolset bash"
    log_info "Or add to profile: source /opt/rh/$toolset/enable"
}

#------------------------------------------------------------------------------
# Enable GCC toolset
#------------------------------------------------------------------------------
enable_gcc_toolset() {
    local version="${1:-11}"
    local toolset="gcc-toolset-${version}"

    if [[ -f "/opt/rh/$toolset/enable" ]]; then
        # shellcheck source=/dev/null
        source "/opt/rh/$toolset/enable"
        log_info "Enabled $toolset"
    else
        log_warn "Could not find $toolset enable script"
    fi
}
