#!/usr/bin/env bash
# vfx-bootstrap - macOS platform support
# This script is sourced by bootstrap.sh

set -euo pipefail

#------------------------------------------------------------------------------
# Install macOS specific dependencies
#------------------------------------------------------------------------------
install_platform_dependencies() {
    log_info "Installing macOS dependencies..."

    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for Apple Silicon
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi

    # Core build tools
    brew install \
        git \
        curl \
        wget \
        cmake \
        ninja \
        pkg-config

    # Development libraries
    brew install \
        openssl@3 \
        readline \
        sqlite3 \
        xz \
        zlib

    # Additional tools
    brew install \
        coreutils \
        gnu-sed

    log_info "macOS dependencies installed"
}

#------------------------------------------------------------------------------
# Check macOS-specific requirements
#------------------------------------------------------------------------------
check_platform_requirements() {
    log_info "Checking macOS requirements..."

    # Check macOS version (recommend 10.15+)
    local os_version
    os_version=$(sw_vers -productVersion)
    local major_version="${os_version%%.*}"

    if [[ "$major_version" -lt 11 ]] && [[ ! "$os_version" =~ ^10\.(15|16) ]]; then
        log_warn "macOS $os_version detected."
        log_warn "Recommended: macOS 10.15 (Catalina) or later"
    fi

    # Check for Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        log_warn "Xcode Command Line Tools not installed"
        log_info "Installing Xcode Command Line Tools..."
        xcode-select --install || true
        log_warn "Please complete the Xcode installation and re-run bootstrap"
    fi

    # Check available disk space (need at least 20GB for full build)
    local available_space
    available_space=$(df -g "$HOME" | awk 'NR==2 {print $4}')
    if [[ "$available_space" -lt 20 ]]; then
        log_warn "Low disk space: ${available_space}GB available"
        log_warn "Recommended: At least 20GB for full USD build"
    fi

    log_info "Platform requirements check complete"
}

#------------------------------------------------------------------------------
# Get macOS SDK path
#------------------------------------------------------------------------------
get_macos_sdk_path() {
    xcrun --show-sdk-path
}

#------------------------------------------------------------------------------
# Get recommended deployment target
#------------------------------------------------------------------------------
get_deployment_target() {
    # VFX Platform typically targets macOS 10.15+
    echo "10.15"
}

#------------------------------------------------------------------------------
# Check architecture and universal binary support
#------------------------------------------------------------------------------
check_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            log_info "Intel (x86_64) architecture detected"
            ;;
        arm64)
            log_info "Apple Silicon (arm64) architecture detected"
            log_info "Note: Some VFX tools may require Rosetta 2"

            # Check if Rosetta 2 is installed
            if ! /usr/bin/pgrep -q oahd; then
                log_warn "Rosetta 2 not installed. Some tools may not work."
                log_info "Install with: softwareupdate --install-rosetta"
            fi
            ;;
        *)
            log_warn "Unknown architecture: $arch"
            ;;
    esac
}
