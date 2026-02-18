#!/bin/bash
# modules/vfx/vfx.sh - VFX Platform module implementation

# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "vfx" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/vfx.state"

# Define module components
COMPONENTS=(
    "build_deps"        # System-level build dependencies (cmake, ninja, compilers)
    "conda_env"         # Conda environment for VFX build tools
    "vfx_bootstrap"     # Install vfx-bootstrap package into conda env
    "channels"          # Configure conda channels and local channel
    "shell"             # Shell aliases for VFX commands
    "platform_version"  # Write VFX Platform version specs
)

# Display module information
show_module_info() {
    cat << 'EOF'

VFX Platform Development Environment
=====================================

Description:
-----------
Complete VFX Platform build and development environment powered by
vfx-bootstrap. Provides tooling for building USD and dependencies
against specific VFX Reference Platform versions.

Components:
----------
1. Build Dependencies
   - cmake, ninja, compilers (gcc/g++ or Xcode)
   - Platform-specific via apt/dnf/brew

2. Conda Environment (vfx-build)
   - conda-build, boa, conda-verify
   - Isolated build environment

3. VFX Bootstrap
   - builder: Python build orchestration for VFX packages
   - packager: Format-agnostic package creation
   - recipes: Conda build recipes for VFX dependencies

4. Local Channel
   - Conda channel for built VFX packages
   - Automatic channel configuration

Aliases:
-------
VFX Commands:
vfx-build   : Build a VFX package
vfx-package : Package built artifacts
vfx-clean   : Clean build artifacts
vfx-list    : List available recipes
vfx-info    : Show package information

Recipe Commands:
vfx-recipe  : Manage build recipes
vfx-deps    : Show dependency tree

Quick Start:
-----------
1. List available recipes:
   $ vfx-list

2. Build a package:
   $ vfx-build openexr

3. Package the result:
   $ vfx-package openexr

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "  [ok] $component: Installed"
        else
            echo "  [--] $component: Not installed"
        fi
    done

    # Show platform version if available
    local platform_file="$HOME/.vfx-devenv/platform.json"
    if [[ -f "$platform_file" ]]; then
        echo
        echo "VFX Platform Version:"
        echo "--------------------"
        local version
        version=$(get_json_value "$platform_file" ".active_version" "unknown")
        echo "  Active: VFX Platform $version"
    fi
    echo
}

# Save component state
save_state() {
    local component=$1
    local status=$2
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$component:$status:$(date +%s)" >> "$STATE_FILE"
}

# Check component state
check_state() {
    local component=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep -q "^$component:installed:" "$STATE_FILE"
        return $?
    fi
    return 1
}

# Ensure conda is loaded
ensure_conda_loaded() {
    if command -v conda &>/dev/null; then
        return 0
    fi
    local conda_root="${HOME}/miniconda3"
    local config_root
    config_root=$(get_module_config "conda" ".shell.paths.conda_root" 2>/dev/null) || true
    if [[ -n "$config_root" && "$config_root" != "null" ]]; then
        conda_root=$(echo "$config_root" | expand_vars)
    fi
    if [[ -s "$conda_root/etc/profile.d/conda.sh" ]]; then
        \. "$conda_root/etc/profile.d/conda.sh"
        return 0
    elif [[ -d "$conda_root/bin" ]]; then
        export PATH="$conda_root/bin:$PATH"
        return 0
    fi
    return 1
}

# Detect platform package manager
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "build_deps")
            command -v cmake &>/dev/null && command -v ninja &>/dev/null
            ;;
        "conda_env")
            ensure_conda_loaded
            conda env list 2>/dev/null | grep -q "vfx-build"
            ;;
        "vfx_bootstrap")
            ensure_conda_loaded
            conda run -n vfx-build python -c "import builder" &>/dev/null
            ;;
        "channels")
            local channel_dir
            channel_dir=$(get_module_config "vfx" ".shell.paths.channel_dir")
            channel_dir=$(echo "$channel_dir" | expand_vars)
            [[ -d "$channel_dir" ]] && [[ -f "$channel_dir/channeldata.json" ]]
            ;;
        "shell")
            list_module_aliases "vfx" "vfx" &>/dev/null && \
            list_module_aliases "vfx" "recipes" &>/dev/null
            ;;
        "platform_version")
            [[ -f "$HOME/.vfx-devenv/platform.json" ]]
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "vfx"
        return 0
    fi

    case "$component" in
        "build_deps")
            if install_build_deps; then
                save_state "build_deps" "installed"
                return 0
            fi
            ;;
        "conda_env")
            if install_conda_env; then
                save_state "conda_env" "installed"
                return 0
            fi
            ;;
        "vfx_bootstrap")
            if install_vfx_bootstrap; then
                save_state "vfx_bootstrap" "installed"
                return 0
            fi
            ;;
        "channels")
            if configure_channels; then
                save_state "channels" "installed"
                return 0
            fi
            ;;
        "shell")
            if configure_shell; then
                save_state "shell" "installed"
                return 0
            fi
            ;;
        "platform_version")
            if configure_platform_version; then
                save_state "platform_version" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Component: build_deps
install_build_deps() {
    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    log "INFO" "Installing build dependencies via $pkg_manager" "vfx"

    case "$pkg_manager" in
        "apt")
            local packages
            packages=$(get_module_config "vfx" ".build_deps.linux.apt[]")
            sudo apt-get update -qq || return 1
            sudo apt-get install -y -qq $packages || return 1
            ;;
        "dnf")
            local packages
            packages=$(get_module_config "vfx" ".build_deps.linux.dnf[]")
            sudo dnf install -y -q $packages || return 1
            ;;
        "brew")
            local packages
            packages=$(get_module_config "vfx" ".build_deps.darwin.brew[]")
            brew install $packages || return 1
            ;;
        *)
            log "ERROR" "Unsupported package manager" "vfx"
            return 1
            ;;
    esac

    return 0
}

# Component: conda_env
install_conda_env() {
    ensure_conda_loaded || {
        log "ERROR" "Conda not available. Install conda module first." "vfx"
        return 1
    }

    local env_name
    env_name=$(get_module_config "vfx" ".conda.env_name" "vfx-build")

    # Accept conda channel TOS non-interactively (required by conda 25.x+)
    if conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null; then
        log "INFO" "Accepted conda TOS for default channels" "vfx"
    fi
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

    # Check if env already exists
    if conda env list 2>/dev/null | grep -q "$env_name"; then
        log "INFO" "Conda environment '$env_name' already exists, updating" "vfx"
        local packages
        packages=$(get_module_config "vfx" ".conda.packages[]")
        if ! conda install -n "$env_name" -y $packages; then
            log "ERROR" "Failed to update conda environment '$env_name'" "vfx"
            return 1
        fi
        return 0
    fi

    log "INFO" "Creating conda environment: $env_name" "vfx"
    local packages
    packages=$(get_module_config "vfx" ".conda.packages[]")
    if ! conda create -n "$env_name" -y $packages; then
        log "ERROR" "Failed to create conda environment '$env_name'" "vfx"
        return 1
    fi

    return 0
}

# Component: vfx_bootstrap
install_vfx_bootstrap() {
    ensure_conda_loaded || return 1

    local env_name
    env_name=$(get_module_config "vfx" ".conda.env_name" "vfx-build")

    # In consolidated repo, vfx-bootstrap lives under toolkits/
    local bootstrap_dir="${VFX_BOOTSTRAP_DIR:-}"
    if [[ -z "$bootstrap_dir" ]]; then
        bootstrap_dir="${DEVENV_ROOT:-$(cd "$MODULE_DIR/../.." && pwd)}/toolkits/vfx-bootstrap"
    fi

    if [[ ! -f "$bootstrap_dir/setup.py" ]]; then
        log "ERROR" "vfx-bootstrap not found at $bootstrap_dir" "vfx"
        return 1
    fi

    log "INFO" "Installing vfx-bootstrap into $env_name from $bootstrap_dir" "vfx"
    if ! conda run -n "$env_name" pip install -e "$bootstrap_dir"; then
        log "ERROR" "Failed to install vfx-bootstrap into '$env_name'" "vfx"
        return 1
    fi

    return 0
}

# Component: channels
configure_channels() {
    local channel_dir
    channel_dir=$(get_module_config "vfx" ".shell.paths.channel_dir")
    channel_dir=$(echo "$channel_dir" | expand_vars)

    log "INFO" "Configuring VFX local channel at $channel_dir" "vfx"
    mkdir -p "$channel_dir"/{linux-64,osx-64,noarch}

    # Initialize channel metadata for each subdir
    for subdir in linux-64 osx-64 noarch; do
        cat > "$channel_dir/$subdir/repodata.json" << EOF
{
    "info": {
        "subdir": "$subdir"
    },
    "packages": {},
    "packages.conda": {},
    "removed": [],
    "repodata_version": 1
}
EOF
    done

    # Create channeldata.json
    cat > "$channel_dir/channeldata.json" << EOF
{
    "channeldata_version": 1,
    "packages": {},
    "subdirs": ["linux-64", "osx-64", "noarch"]
}
EOF

    # Add local channel to conda config if not already present
    ensure_conda_loaded
    if ! conda config --show channels 2>/dev/null | grep -q "$channel_dir"; then
        conda config --append channels "file://$channel_dir"
        log "INFO" "Added local VFX channel to conda config" "vfx"
    fi

    # Create output directories
    local build_output
    build_output=$(get_module_config "vfx" ".shell.paths.build_output")
    build_output=$(echo "$build_output" | expand_vars)
    mkdir -p "$build_output"

    local package_output
    package_output=$(get_module_config "vfx" ".shell.paths.package_output")
    package_output=$(echo "$package_output" | expand_vars)
    mkdir -p "$package_output"

    return 0
}

# Component: shell
configure_shell() {
    log "INFO" "Configuring VFX shell aliases" "vfx"
    add_module_aliases "vfx" "vfx" || return 1
    add_module_aliases "vfx" "recipes" || return 1
    return 0
}

# Component: platform_version
configure_platform_version() {
    local vfx_home="$HOME/.vfx-devenv"
    mkdir -p "$vfx_home"

    local platform_file="$vfx_home/platform.json"
    log "INFO" "Writing VFX Platform version specs to $platform_file" "vfx"

    # Read version specs from module config
    local vfx_2024
    vfx_2024=$(get_module_config "vfx" ".vfx_platform.\"2024\"")
    local vfx_2025
    vfx_2025=$(get_module_config "vfx" ".vfx_platform.\"2025\"")

    cat > "$platform_file" << EOF
{
    "active_version": "2025",
    "versions": {
        "2024": $vfx_2024,
        "2025": $vfx_2025
    },
    "installed_at": "$(date -Iseconds)",
    "devenv_root": "${DEVENV_ROOT:-}"
}
EOF

    return 0
}

# Grovel: check if all components need installation
grovel_vfx() {
    local status=0
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "vfx"
            status=1
        fi
    done
    return $status
}

# Install with state awareness
install_vfx() {
    local force=${1:-false}

    if [[ "$force" == "true" ]] || ! grovel_vfx &>/dev/null; then
        create_backup
    fi

    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "vfx"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "vfx"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "vfx"
        fi
    done

    show_module_info
    return 0
}

# Remove VFX module configuration
remove_vfx() {
    log "INFO" "Removing VFX module configuration..." "vfx"

    # Backup existing configurations
    [[ -f "$HOME/.vfx-devenv/platform.json" ]] && backup_file "$HOME/.vfx-devenv/platform.json" "vfx"

    # Remove shell aliases
    remove_module_aliases "vfx" "vfx"
    remove_module_aliases "vfx" "recipes"

    # Remove VFX directories
    local channel_dir
    channel_dir=$(get_module_config "vfx" ".shell.paths.channel_dir")
    channel_dir=$(echo "$channel_dir" | expand_vars)
    [[ -d "$channel_dir" ]] && rm -rf "$channel_dir"

    # Remove local channel from conda config
    ensure_conda_loaded
    conda config --remove channels "file://$channel_dir" 2>/dev/null || true

    # Remove state file
    rm -f "$STATE_FILE"

    log "WARN" "Conda environment 'vfx-build' preserved. Run 'conda env remove -n vfx-build' to remove." "vfx"
    log "WARN" "VFX home directory preserved at ~/.vfx-devenv. Remove manually if desired." "vfx"

    return 0
}

# Verify entire installation
verify_vfx() {
    log "INFO" "Verifying VFX module installation..." "vfx"
    local status=0

    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "vfx"
            status=1
        else
            log "INFO" "Component verified: $component" "vfx"
        fi
    done

    if [ $status -eq 0 ]; then
        log "INFO" "VFX module verification completed successfully" "vfx"
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_vfx
        ;;
    install)
        install_vfx "${2:-false}"
        ;;
    verify)
        verify_vfx
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_vfx
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "vfx"
        exit 1
        ;;
esac
