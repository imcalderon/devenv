#!/bin/bash
# modules/ldtk/ldtk.sh - LDtk level editor module

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "ldtk" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/ldtk.state"

# Define module components
COMPONENTS=(
    "core"          # Base LDtk installation
    "docker"        # Docker container setup
    "templates"     # Project templates
    "config"        # Editor configuration
)

# Display module information
show_module_info() {
    cat << 'EOF'

🗺️ LDtk Level Editor
=================

Description:
-----------
LDtk is a free, open-source 2D level editor that focuses on workflow and
modularity. This module provides a complete integration with LDtk, including
Docker support and Phaser game engine templates.

Components:
----------
1. Core Installation
   - Standalone LDtk editor
   - Flexible configuration
   - Backup management

2. Docker Support
   - Containerized LDtk environment
   - X11 forwarding for native GUI
   - Persistent project storage

3. Project Templates
   - Phaser game engine integration
   - Predefined layer and entity structures

Quick Start:
-----------
1. Launch native LDtk:
   $ ldtk

2. Launch LDtk in Docker:
   $ ldtkc

3. Launch LDtk in Docker with X11:
   $ ldtkx

Configuration:
-------------
Location: ~/.config/ldtk
Templates: ~/.devenv/templates/ldtk

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v ldtk &>/dev/null; then
                        echo "  Version: $(ldtk --version 2>&1 | head -n1)"
                    fi
                    ;;
                "docker")
                    local templates_dir="$HOME/.devenv/templates/ldtk"
                    if [[ -f "$templates_dir/Dockerfile.ldtk" ]]; then
                        echo "  Docker: Configured"
                    fi
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
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

# Install core LDtk
install_core() {
    local version=$(get_module_config "ldtk" ".ldtk.version")
    local download_url=$(get_module_config "ldtk" ".ldtk.download_url")
    local bin_dir=$(get_module_config "ldtk" ".shell.paths.bin_dir")
    bin_dir=$(eval echo "$bin_dir")
    
    mkdir -p "$bin_dir"
    
    # Download the LDtk ZIP file
    log "INFO" "Downloading LDtk v$version ZIP file..." "ldtk"
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/ldtk-v$version.zip"
    if ! curl -L "$download_url" -o "$zip_file"; then
        log "ERROR" "Failed to download LDtk ZIP file" "ldtk"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract the AppImage from the ZIP
    log "INFO" "Extracting LDtk v$version AppImage..." "ldtk"
    local appimage_file="$temp_dir/LDtk 1.5.3 installer.AppImage"
    if ! unzip -p "$zip_file" "LDtk 1.5.3 installer.AppImage" > "$appimage_file"; then
        log "ERROR" "Failed to extract LDtk AppImage from ZIP" "ldtk"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Make the AppImage executable
    chmod +x "$appimage_file"
    
    # Copy the AppImage to the bin directory
    log "INFO" "Copying LDtk AppImage to $bin_dir..." "ldtk"
    cp "$appimage_file" "$bin_dir/ldtk"
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    log "INFO" "LDtk v$version installed successfully" "ldtk"
    return 0
}
# Setup Docker environment

setup_docker() {
    local templates_dir="$HOME/.devenv/templates/ldtk"
    mkdir -p "$templates_dir"
    
    # Create Dockerfile for LDtk
    cat > "$templates_dir/Dockerfile.ldtk" << 'EOF'
FROM ubuntu:22.04

# Install required dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libxtst6 \
    xdg-utils \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install LDtk
RUN curl -L "https://github.com/deepnight/ldtk/releases/download/v1.5.3/ubuntu-distribution.zip" -o /tmp/ldtk.zip \
    && cd /tmp \
    && unzip ldtk.zip \
    && mv "LDtk 1.5.3 installer.AppImage" /usr/local/bin/ldtk \
    && chmod +x /usr/local/bin/ldtk \
    && rm /tmp/ldtk.zip

WORKDIR /maps
ENV DISPLAY=:0

ENTRYPOINT ["/usr/local/bin/ldtk"]
EOF

    # Create docker-compose.yml
    cat > "$templates_dir/docker-compose.yml" << EOF
version: '3.8'
services:
  ldtk:
    build: 
      context: .
      dockerfile: Dockerfile.ldtk
    volumes:
      - ./maps:/maps
      - $HOME/.config/ldtk:/root/.config/ldtk
      - /tmp/.X11-unix:/tmp/.X11-unix
    environment:
      - DISPLAY=\${DISPLAY}
    network_mode: host
EOF

    return 0
}


# Setup project templates
setup_templates() {
    local templates_dir="$HOME/.devenv/templates/ldtk"
    mkdir -p "$templates_dir/maps"
    
    # Create Phaser template
    local template=$(get_module_config "ldtk" ".ldtk.templates.phaser.default")
    echo "$template" > "$templates_dir/maps/phaser-template.ldtk"
    
    return 0
}

# Configure LDtk
configure_ldtk() {
    local config_dir=$(get_module_config "ldtk" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    mkdir -p "$config_dir"
    
    # Configure LDtk
    local config=$(get_module_config "ldtk" ".ldtk.config")
    echo "$config" > "$config_dir/config.json"
    
    return 0
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            verify_core_installation
            ;;
        "docker")
            verify_docker_setup
            ;;
        "templates")
            verify_templates
            ;;
        "config")
            verify_config
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verification helper functions
verify_core_installation() {
    local bin_dir=$(get_module_config "ldtk" ".shell.paths.bin_dir")
    bin_dir=$(eval echo "$bin_dir")
    
    # Check binary exists and is executable
    [[ -x "$bin_dir/ldtk" ]] && \
    # Verify version matches expected
    local version=$("$bin_dir/ldtk" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+')
    [[ "$version" == "$(get_module_config "ldtk" ".ldtk.version")" ]]
}

verify_docker_setup() {
    local templates_dir="$HOME/.devenv/templates/ldtk"
    
    [[ -f "$templates_dir/Dockerfile.ldtk" ]] && \
    [[ -f "$templates_dir/docker-compose.yml" ]] && \
    docker compose -f "$templates_dir/docker-compose.yml" config -q
}

verify_templates() {
    local templates_dir="$HOME/.devenv/templates/ldtk"
    
    [[ -d "$templates_dir/maps" ]] && \
    [[ -f "$templates_dir/maps/phaser-template.ldtk" ]] && \
    validate_json "$templates_dir/maps/phaser-template.ldtk"
}

verify_config() {
    local config_dir=$(get_module_config "ldtk" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    [[ -f "$config_dir/config.json" ]] && \
    validate_json "$config_dir/config.json"
}

# Install with state awareness
install_ldtk() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_ldtk &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "ldtk"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "ldtk"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "ldtk"
        fi
    done
    
    # Add LDtk aliases
    add_module_aliases "ldtk" "ldtk" || return 1
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "ldtk"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "docker")
            if setup_docker; then
                save_state "docker" "installed"
                return 0
            fi
            ;;
        "templates")
            if setup_templates; then
                save_state "templates" "installed"
                return 0
            fi
            ;;
        "config")
            if configure_ldtk; then
                save_state "config" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Grovel checks existence and basic functionality
grovel_ldtk() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "ldtk"
            status=1
        fi
    done
    
    return $status
}

# Remove LDtk configuration
remove_ldtk() {
    log "INFO" "Removing LDtk configuration..." "ldtk"
    
    # Backup configs
    local config_dir=$(get_module_config "ldtk" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    [[ -d "$config_dir" ]] && backup_file "$config_dir" "ldtk"
    
    # Remove binary
    local bin_dir=$(get_module_config "ldtk" ".shell.paths.bin_dir")
    bin_dir=$(eval echo "$bin_dir")
    rm -f "$bin_dir/ldtk"
    
    # Remove Docker files
    rm -rf "$HOME/.devenv/templates/ldtk"
    
    # Remove config
    rm -rf "$config_dir"
    
    # Remove aliases
    remove_module_aliases "ldtk" "ldtk"
    
    # Remove state file
    rm -f "$STATE_FILE"
    
    return 0
}

# Verify entire installation
verify_ldtk() {
    log "INFO" "Verifying LDtk installation..." "ldtk"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "ldtk"
            status=1
        fi
    done
    
    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_ldtk
        ;;
    install)
        install_ldtk "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_ldtk
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_ldtk
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "ldtk"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac