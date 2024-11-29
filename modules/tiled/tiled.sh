#!/bin/bash
# modules/tiled/tiled.sh - Tiled map editor module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "tiled" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/tiled.state"

# Define module components
COMPONENTS=(
    "core"          # Base Tiled installation
    "docker"        # Docker container setup
    "templates"     # Map templates
    "config"        # Editor configuration
)

# Display module information
show_module_info() {
    cat << 'EOF'

🗺️ Tiled Map Editor
=================

Description:
-----------
Tiled map editor with Docker support and Phaser game integration.

Components:
----------
1. Core Installation
   - Native Tiled editor
   - Default configurations
   - Custom templates

2. Docker Support
   - Containerized environment
   - X11 forwarding
   - Volume mapping

Quick Start:
-----------
1. Launch native:
   $ tiled

2. Launch Docker:
   $ tiledc

3. Launch Docker with X11:
   $ tiledx

Configuration:
-------------
Location: ~/.config/tiled
Templates: ~/.devenv/templates/tiled

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v tiled &>/dev/null; then
                        echo "  Version: $(tiled --version 2>&1 | head -n1)"
                    fi
                    ;;
                "docker")
                    local templates_dir=$(get_module_config "tiled" ".shell.paths.templates_dir")
                    templates_dir=$(eval echo "$templates_dir")
                    if [[ -f "$templates_dir/Dockerfile.tiled" ]]; then
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

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            command -v tiled &>/dev/null
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

# Verify Docker setup
verify_docker_setup() {
    local templates_dir=$(get_module_config "tiled" ".shell.paths.templates_dir")
    templates_dir=$(eval echo "$templates_dir")
    
    [[ -f "$templates_dir/Dockerfile.tiled" ]] && \
    [[ -f "$templates_dir/docker-compose.yml" ]]
}

# Verify templates
verify_templates() {
    local templates_dir=$(get_module_config "tiled" ".shell.paths.templates_dir")
    templates_dir=$(eval echo "$templates_dir")
    
    [[ -d "$templates_dir/maps" ]] && \
    [[ -f "$templates_dir/maps/phaser-template.json" ]]
}

# Verify configuration
verify_config() {
    local config_dir=$(get_module_config "tiled" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    [[ -f "$config_dir/tiled.conf" ]]
}

# Install core Tiled
install_core() {
    log "INFO" "Installing Tiled..." "tiled"
    
    if ! command -v flatpak &>/dev/null; then
        if command -v dnf &>/dev/null; then
            sudo dnf install -y flatpak
        elif command -v apt-get &>/dev/null; then
            sudo apt-get install -y flatpak
        else
            log "ERROR" "Unsupported package manager" "tiled"
            return 1
        fi
    fi

    # Add Flathub repository if not already added
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    # Install Tiled
    flatpak install -y flathub org.mapeditor.Tiled

    # Create wrapper script for command line access
    sudo tee /usr/local/bin/tiled > /dev/null << 'EOF'
#!/bin/bash
flatpak run org.mapeditor.Tiled "$@"
EOF
    sudo chmod +x /usr/local/bin/tiled

    return 0
}

# Setup Docker environment
setup_docker() {
    log "INFO" "Setting up Docker environment..." "tiled"
    
    local templates_dir=$(get_module_config "tiled" ".shell.paths.templates_dir")
    templates_dir=$(eval echo "$templates_dir")
    
    mkdir -p "$templates_dir"
    
    # Create Dockerfile
    cat > "$templates_dir/Dockerfile.tiled" << 'EOF'
FROM ubuntu:22.04

# Install Tiled and dependencies
RUN apt-get update && apt-get install -y \
    tiled \
    qtbase5-dev  \
    libqt5x11extras5 \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Setup working directory
VOLUME /maps
WORKDIR /maps

# Set display for X11
ENV DISPLAY=:0

ENTRYPOINT ["tiled"]
EOF

    # Create docker-compose.yml
    cat > "$templates_dir/docker-compose.yml" << EOF
version: '3.8'
services:
  tiled:
    build:
      context: .
      dockerfile: Dockerfile.tiled
    volumes:
      - ./maps:/maps
      - $HOME/.config/tiled:/root/.config/tiled
      - /tmp/.X11-unix:/tmp/.X11-unix
    environment:
      - DISPLAY=\${DISPLAY}
    network_mode: host
EOF

    return 0
}

# Setup map templates
setup_templates() {
    log "INFO" "Setting up map templates..." "tiled"
    
    local templates_dir=$(get_module_config "tiled" ".shell.paths.templates_dir")
    templates_dir=$(eval echo "$templates_dir")
    
    mkdir -p "$templates_dir/maps"
    
    # Create Phaser template
    local template=$(get_module_config "tiled" ".tiled.templates.phaser.orthogonal")
    echo "$template" > "$templates_dir/maps/phaser-template.json"
    
    return 0
}

# Configure Tiled
configure_tiled() {
    log "INFO" "Configuring Tiled..." "tiled"
    
    local config_dir=$(get_module_config "tiled" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    mkdir -p "$config_dir"
    
    # Get preferences from config
    local preferences=$(get_module_config "tiled" ".tiled.config.preferences")
    echo "$preferences" > "$config_dir/tiled.conf"
    
    # Configure shortcuts
    local shortcuts=$(get_module_config "tiled" ".tiled.config.shortcuts")
    echo "$shortcuts" > "$config_dir/shortcuts.conf"
    
    return 0
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "tiled"
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
            if configure_tiled; then
                save_state "config" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Grovel checks existence and basic functionality
grovel_tiled() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "tiled"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_tiled() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_tiled &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "tiled"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "tiled"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "tiled"
        fi
    done
    
    # Add Tiled aliases
    add_module_aliases "tiled" "map" || return 1
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Remove Tiled configuration
remove_tiled() {
    log "INFO" "Removing Tiled configuration..." "tiled"

    # Backup existing configurations
    local config_dir=$(get_module_config "tiled" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    [[ -d "$config_dir" ]] && backup_file "$config_dir" "tiled"
    
    # Remove configurations
    rm -rf "$config_dir"
    
    # Remove Docker files
    local templates_dir=$(get_module_config "tiled" ".shell.paths.templates_dir")
    templates_dir=$(eval echo "$templates_dir")
    rm -f "$templates_dir/Dockerfile.tiled" "$templates_dir/docker-compose.yml"
    rm -rf "$templates_dir/maps"

    # Remove aliases
    remove_module_aliases "tiled" "map"

    # Remove state file
    rm -f "$STATE_FILE"

    log "WARN" "Tiled package not removed. Use package manager to remove if desired." "tiled"

    return 0
}

# Verify entire installation
verify_tiled() {
    log "INFO" "Verifying Tiled installation..." "tiled"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "tiled"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "Tiled verification completed successfully" "tiled"
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_tiled
        ;;
    install)
        install_tiled "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_tiled
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_tiled
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "tiled"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac