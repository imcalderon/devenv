#!/usr/bin/env bash
# vfx-bootstrap - Main bootstrap script
# Usage: curl -fsSL https://raw.githubusercontent.com/imcalderon/vfx-bootstrap/main/bootstrap/bootstrap.sh | bash
#
# This script prepares a clean machine for building VFX Platform software.
# It detects the platform and installs minimal dependencies.

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
readonly VFX_BOOTSTRAP_VERSION="0.1.0"
readonly VFX_BOOTSTRAP_REPO="https://github.com/imcalderon/vfx-bootstrap.git"
readonly VFX_BOOTSTRAP_DIR="${VFX_BOOTSTRAP_DIR:-$HOME/vfx-bootstrap}"
readonly MINIFORGE_VERSION="24.3.0-0"

#------------------------------------------------------------------------------
# Colors and Logging
#------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

#------------------------------------------------------------------------------
# Platform Detection
#------------------------------------------------------------------------------
detect_platform() {
    local platform=""
    local version=""

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            case "$ID" in
                ubuntu|debian|linuxmint|pop)
                    platform="ubuntu"
                    version="$VERSION_ID"
                    ;;
                rhel|centos|rocky|almalinux|fedora)
                    platform="rocky"
                    version="$VERSION_ID"
                    ;;
                *)
                    # Try to detect base distro
                    if [[ -n "${ID_LIKE:-}" ]]; then
                        case "$ID_LIKE" in
                            *debian*|*ubuntu*)
                                platform="ubuntu"
                                ;;
                            *rhel*|*fedora*|*centos*)
                                platform="rocky"
                                ;;
                        esac
                    fi
                    ;;
            esac
        fi

        # Check for WSL
        if grep -qi microsoft /proc/version 2>/dev/null; then
            export VFX_BOOTSTRAP_WSL=1
            log_info "WSL environment detected"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        platform="macos"
        version=$(sw_vers -productVersion)
    fi

    if [[ -z "$platform" ]]; then
        log_error "Unable to detect platform. Supported platforms:"
        log_error "  - Ubuntu/Debian (and derivatives)"
        log_error "  - RHEL/Rocky/CentOS/Fedora"
        log_error "  - macOS"
        exit 1
    fi

    export VFX_BOOTSTRAP_PLATFORM="$platform"
    export VFX_BOOTSTRAP_VERSION_ID="$version"
    log_info "Detected platform: $platform (version: ${version:-unknown})"
}

#------------------------------------------------------------------------------
# Check Prerequisites
#------------------------------------------------------------------------------
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check for root - we don't want to run as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root."
        log_error "Run as a regular user; sudo will be used when needed."
        exit 1
    fi

    # Check for sudo
    if ! command -v sudo &>/dev/null; then
        log_error "sudo is required but not installed."
        exit 1
    fi

    # Check sudo access
    if ! sudo -v &>/dev/null; then
        log_error "This script requires sudo access."
        exit 1
    fi

    log_info "Prerequisites check passed"
}

#------------------------------------------------------------------------------
# Install Base Dependencies
#------------------------------------------------------------------------------
install_base_dependencies() {
    log_step "Installing base dependencies..."

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Source the platform-specific script
    local platform_script="${script_dir}/platforms/${VFX_BOOTSTRAP_PLATFORM}.sh"

    if [[ -f "$platform_script" ]]; then
        # shellcheck source=/dev/null
        source "$platform_script"
        install_platform_dependencies
    else
        # Fallback for when running via curl (no local files)
        case "$VFX_BOOTSTRAP_PLATFORM" in
            ubuntu)
                sudo apt-get update
                sudo apt-get install -y \
                    git \
                    curl \
                    wget \
                    ca-certificates \
                    build-essential \
                    pkg-config
                ;;
            rocky)
                sudo dnf install -y \
                    git \
                    curl \
                    wget \
                    ca-certificates \
                    gcc \
                    gcc-c++ \
                    make \
                    pkgconfig
                ;;
            macos)
                # Check for Homebrew
                if ! command -v brew &>/dev/null; then
                    log_info "Installing Homebrew..."
                    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                fi
                brew install git curl wget
                ;;
        esac
    fi

    log_info "Base dependencies installed"
}

#------------------------------------------------------------------------------
# Install Miniforge (Conda)
#------------------------------------------------------------------------------
install_miniforge() {
    log_step "Setting up Miniforge (conda)..."

    local conda_root="${CONDA_ROOT:-$HOME/miniforge3}"

    if [[ -d "$conda_root" ]] && [[ -x "$conda_root/bin/conda" ]]; then
        log_info "Miniforge already installed at $conda_root"
        export PATH="$conda_root/bin:$PATH"
        conda update -n base conda -y || true
        return 0
    fi

    log_info "Installing Miniforge..."

    local arch
    local os_name

    case "$(uname -m)" in
        x86_64)
            arch="x86_64"
            ;;
        aarch64|arm64)
            arch="aarch64"
            ;;
        *)
            log_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac

    case "$OSTYPE" in
        linux*)
            os_name="Linux"
            ;;
        darwin*)
            os_name="MacOSX"
            ;;
        *)
            log_error "Unsupported OS: $OSTYPE"
            exit 1
            ;;
    esac

    local installer_url="https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-${os_name}-${arch}.sh"
    local installer_script="/tmp/miniforge.sh"

    log_info "Downloading Miniforge from $installer_url"
    curl -fsSL "$installer_url" -o "$installer_script"

    bash "$installer_script" -b -p "$conda_root"
    rm -f "$installer_script"

    export PATH="$conda_root/bin:$PATH"

    # Initialize conda for shell
    conda init bash
    if command -v zsh &>/dev/null; then
        conda init zsh
    fi

    # Configure conda
    conda config --set auto_activate_base false
    conda config --add channels conda-forge
    conda config --set channel_priority strict

    log_info "Miniforge installed successfully"
}

#------------------------------------------------------------------------------
# Clone Repository
#------------------------------------------------------------------------------
clone_repository() {
    log_step "Setting up vfx-bootstrap repository..."

    if [[ -d "$VFX_BOOTSTRAP_DIR/.git" ]]; then
        log_info "Repository already exists at $VFX_BOOTSTRAP_DIR"
        cd "$VFX_BOOTSTRAP_DIR"
        git pull || log_warn "Could not update repository"
        return 0
    fi

    log_info "Cloning vfx-bootstrap to $VFX_BOOTSTRAP_DIR"
    git clone "$VFX_BOOTSTRAP_REPO" "$VFX_BOOTSTRAP_DIR"

    log_info "Repository cloned successfully"
}

#------------------------------------------------------------------------------
# Setup Development Environment
#------------------------------------------------------------------------------
setup_dev_environment() {
    log_step "Setting up development environment..."

    cd "$VFX_BOOTSTRAP_DIR"

    # Create conda environment for vfx-bootstrap development
    if conda env list | grep -q "^vfx-bootstrap "; then
        log_info "vfx-bootstrap environment already exists"
    else
        log_info "Creating vfx-bootstrap conda environment..."
        conda create -n vfx-bootstrap python=3.11 -y
    fi

    # Install vfx-bootstrap in development mode
    log_info "Installing vfx-bootstrap package..."
    conda run -n vfx-bootstrap pip install -e . 2>/dev/null || true

    log_info "Development environment ready"
}

#------------------------------------------------------------------------------
# Print Next Steps
#------------------------------------------------------------------------------
print_next_steps() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}vfx-bootstrap setup complete!${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Start a new terminal or run:"
    echo -e "     ${YELLOW}source ~/.bashrc${NC}"
    echo ""
    echo "  2. Activate the vfx-bootstrap environment:"
    echo -e "     ${YELLOW}conda activate vfx-bootstrap${NC}"
    echo ""
    echo "  3. Build USD and dependencies:"
    echo -e "     ${YELLOW}cd $VFX_BOOTSTRAP_DIR${NC}"
    echo -e "     ${YELLOW}vfx-bootstrap build usd --platform vfx2024${NC}"
    echo ""
    echo "  For more information, see: $VFX_BOOTSTRAP_DIR/README.md"
    echo ""
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  vfx-bootstrap v${VFX_BOOTSTRAP_VERSION}${NC}"
    echo -e "${CYAN}  VFX Platform Development Toolkit${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    detect_platform
    check_prerequisites
    install_base_dependencies
    install_miniforge
    clone_repository
    setup_dev_environment
    print_next_steps
}

# Run main function
main "$@"
