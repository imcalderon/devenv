#!/bin/bash
# modules/docker/docker.sh - Docker module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "docker" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/docker.state"

# Define module components
COMPONENTS=(
    "core"          # Base Docker installation
    "daemon"        # Docker daemon configuration
    "service"       # Docker service setup
    "groups"        # User group configuration
    "helpers"       # Helper functions and aliases
)

# Display module information
show_module_info() {
    cat << 'EOF'

🐳 Docker Development Environment
=============================

Description:
-----------
Professional Docker environment with optimized daemon settings,
helper functions, and shell integration for container development.

Benefits:
--------
✓ Production-Ready Setup - Optimized daemon configuration
✓ Enhanced Productivity - Custom aliases and helper functions
✓ Security - Proper user group management
✓ Resource Management - Container limits and logging configuration

Components:
----------
1. Core Docker
   - Docker Engine CE
   - Docker Compose
   - Container runtime

2. Configuration
   - Optimized daemon settings
   - Log rotation
   - Resource limits
   - Network settings

3. Helper Functions
   - Container management
   - Log viewing
   - Compose operations
   - Cleanup utilities

Quick Start:
-----------
1. Run container:
   $ d run -it ubuntu bash

2. Manage services:
   $ dc up -d     # Start services
   $ dcl          # View logs
   $ dcd          # Stop services

3. Container operations:
   $ dex web bash # Execute in container
   $ dlog web     # View container logs

Helper Functions:
----------------
dexec <container> [cmd]  : Execute command in container
dlog <container> [lines] : View container logs
dbash <container>        : Quick access to container shell
dcex <service> [cmd]     : Execute in compose service

Aliases:
-------
Basic:
d    : docker
dc   : docker compose
dcu  : docker compose up
dcub : docker compose up --build
dcd  : docker compose down
dcl  : docker compose logs -f

Container:
dps    : docker ps
dpsa   : docker ps -a
dex    : docker exec -it
dtop   : docker top
dstats : docker stats

Cleanup:
dprune  : docker system prune -f
dvprune : docker volume prune -f
dclean  : docker system prune -af --volumes

Configuration:
-------------
Location: /etc/docker/
Key files:
- daemon.json     : Daemon configuration
- config.json     : CLI configuration

Tips:
----
• Use dbash for quick container access
• Monitor resources with dstats
• Regular cleanup with dprune
• Use dcl for service debugging

For more information:
-------------------
Documentation: https://docs.docker.com
Support: https://www.docker.com/support

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v docker &>/dev/null; then
                        echo "  Version: $(docker --version)"
                    fi
                    ;;
                "service")
                    if systemctl is-active --quiet docker; then
                        echo "  Service: Running"
                    else
                        echo "  Service: Stopped"
                    fi
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
    echo
}
install_docker_package() {
    log "INFO" "Installing Docker..." "docker"

    if command -v dnf &>/dev/null; then
        # RPM-based installation (AlmaLinux/RHEL/CentOS)
        local repo_url=$(get_module_config "docker" ".docker.package.repositories.rpm.repo_url")
        
        # First, install required utilities
        sudo dnf install -y dnf-plugins-core
        
        # Add Docker repository
        sudo dnf config-manager --add-repo "$repo_url"
        
        # Install Docker packages
        local components=($(get_module_config "docker" ".docker.package.components[]"))
        if ! sudo dnf install -y "${components[@]}"; then
            log "ERROR" "Failed to install Docker via DNF" "docker"
            return 1
        fi
    elif command -v apt-get &>/dev/null; then
        # DEB-based installation
        local key_url=$(get_module_config "docker" ".docker.package.repositories.deb.key_url")
        local key_path=$(get_module_config "docker" ".docker.package.repositories.deb.key_path")
        local repo_file=$(get_module_config "docker" ".docker.package.repositories.deb.repo_file")
        local repo_config=$(get_module_config "docker" ".docker.package.repositories.deb.repo_config")
        
        # Add Docker's official GPG key
        curl -fsSL "$key_url" | sudo gpg --dearmor -o "$key_path"
        
        # Replace {release} placeholder with actual release
        repo_config="${repo_config/\{release\}/$(lsb_release -cs)}"
        echo "$repo_config" | sudo tee "$repo_file" > /dev/null
        
        sudo apt-get update
        local components=($(get_module_config "docker" ".docker.package.components[]"))
        if ! sudo apt-get install -y "${components[@]}"; then
            log "ERROR" "Failed to install Docker via APT" "docker"
            return 1
        fi
    else
        log "ERROR" "Unsupported package manager" "docker"
        return 1
    fi
    log "INFO" "Installing Docker Compose..." "docker"
    if ! command -v docker compose &>/dev/null; then
        if command -v dnf &>/dev/null; then
            sudo dnf install -y docker-compose-plugin
        elif command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y docker-compose-plugin
        fi
    fi
    return 0
}

# Configure Docker daemon
configure_docker_daemon() {
    log "INFO" "Configuring Docker daemon..." "docker"

    local config_dir=$(get_module_config "docker" ".shell.paths.config_dir")
    local daemon_config=$(get_module_config "docker" ".shell.paths.daemon_config")

    # Create configuration directory with sudo
    sudo mkdir -p "$config_dir"

    # Backup existing configuration
    [[ -f "$daemon_config" ]] && backup_file "$daemon_config" "docker"

    # Create temp file and write configuration
    local temp_config=$(mktemp)
    
    if get_module_config "docker" ".docker.daemon" > "$temp_config"; then
        # Use sudo to move the temp file
        if sudo cp "$temp_config" "$daemon_config"; then
            sudo chown root:root "$daemon_config"
            sudo chmod 644 "$daemon_config"
        else
            log "ERROR" "Failed to copy configuration to $daemon_config" "docker"
            rm -f "$temp_config"
            return 1
        fi
    else
        log "ERROR" "Failed to write daemon configuration" "docker"
        rm -f "$temp_config"
        return 1
    fi

    # Cleanup
    rm -f "$temp_config"

    # Restart Docker service to apply changes
    if ! restart_docker_service; then
        return 1
    fi

    return 0
}

# Configure Docker service
configure_docker_service() {
    log "INFO" "Configuring Docker service..." "docker"

    # Check if we're in WSL
    if grep -q "microsoft" /proc/version 2>/dev/null; then
        log "INFO" "WSL environment detected, using Docker Desktop integration instead..." "docker"
        
        # For WSL, we'll use Docker Desktop for Windows instead of systemd service
        # Create a placeholder script to check Docker Desktop connectivity
        local script_dir="$HOME/.local/bin"
        mkdir -p "$script_dir"
        
        cat > "$script_dir/docker-check.sh" << 'EOF'
#!/bin/bash
# Check Docker Desktop connectivity from WSL
if docker info &>/dev/null; then
    echo "Docker Desktop is connected"
    exit 0
else
    echo "Docker Desktop is not running or not connected"
    echo "Please ensure Docker Desktop is running on Windows"
    exit 1
fi
EOF
        chmod +x "$script_dir/docker-check.sh"
        
        log "INFO" "Docker service configured for WSL" "docker"
        return 0
    fi

    # Standard systemd approach for native Linux
    sudo systemctl enable docker
    
    if ! restart_docker_service; then
        return 1
    fi

    return 0
}

# Restart Docker service
restart_docker_service() {
    log "INFO" "Restarting Docker service..." "docker"
    
    sudo systemctl restart docker
    
    # Wait for service to be ready
    local timeout=30
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if sudo docker info &>/dev/null; then
            log "INFO" "Docker service successfully restarted" "docker"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    
    log "ERROR" "Docker service failed to restart" "docker"
    return 1
}

# Configure user groups
configure_user_groups() {
    log "INFO" "Configuring user groups..." "docker"

    if ! groups | grep -q "docker"; then
        sudo usermod -aG docker "$USER"
        
        # Refresh group membership
        if ! newgrp docker; then
            log "ERROR" "Failed to initialize docker group membership" "docker"
            return 1
        fi
    fi

    return 0
}

# Configure helper functions
configure_helper_functions() {
    log "INFO" "Configuring Docker helper functions..." "docker"

    local modules_dir=$(get_aliases_dir)
    mkdir -p "$modules_dir"
    local functions_file="$modules_dir/functions.zsh"
    local completions_dir="$HOME/.oh-my-zsh/plugins/docker"

    # Set up Docker completions
    mkdir -p "$completions_dir"
    curl -fLo "$completions_dir/_docker" https://raw.githubusercontent.com/docker/cli/master/contrib/completion/zsh/_docker

    # Add helper functions
    cat >> "$functions_file" << 'EOF'
# Docker helper functions - managed by devenv
dexec() {
    local container=$1
    shift
    if [ $# -eq 0 ]; then
        docker exec -it $container bash
    else
        docker exec -it $container "$@"
    fi
}

dlog() {
    local container=$1
    local lines=${2:-100}
    docker logs --tail $lines -f $container
}

dbash() {
    docker exec -it $1 bash
}

dcex() {
    local service=$1
    shift
    if [ $# -eq 0 ]; then
        docker compose exec $service bash
    else
        docker compose exec $service "$@"
    fi
}
# End Docker helper functions
EOF

    # Add docker to plugins array in zshrc if not already present
    if ! grep -q "plugins=.*docker" "$HOME/.zshrc"; then
        sed -i '/^plugins=/ s/)/\ docker)/' "$HOME/.zshrc"
    fi

    return 0
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
            command -v docker &>/dev/null
            ;;
        "daemon")
            [[ -f "/etc/docker/daemon.json" ]] && validate_json "/etc/docker/daemon.json"
            ;;
        "service")
            # Check if we're in WSL
            if grep -q "microsoft" /proc/version 2>/dev/null; then
                # For WSL, we just need Docker command to be available
                command -v docker &>/dev/null
            else
                # For native Linux, check systemd service
                systemctl is-active --quiet docker
            fi
            ;;
        "groups")
            groups | grep -q "docker"
            ;;
        "helpers")
            verify_helpers
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verify helper functions and aliases
verify_helpers() {
    local modules_dir=$(get_aliases_dir)
    local completions_dir=$(get_module_config "zsh" ".shell.paths.plugins")
    completions_dir=$(eval echo "$completions_dir")

    [[ -f "$modules_dir/functions.zsh" ]] && \
    [[ -f "$completions_dir/_docker" ]] && \
    grep -q "Docker helper functions" "$modules_dir/functions.zsh" && \
    list_module_aliases "docker" "basic" &>/dev/null && \
    list_module_aliases "docker" "container" &>/dev/null && \
    list_module_aliases "docker" "cleanup" &>/dev/null
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "docker"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_docker_package; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "daemon")
            if configure_docker_daemon; then
                save_state "daemon" "installed"
                return 0
            fi
            ;;
        "service")
            if configure_docker_service; then
                save_state "service" "installed"
                return 0
            fi
            ;;
        "groups")
            if configure_user_groups; then
                save_state "groups" "installed"
                return 0
            fi
            ;;
        "helpers")
            if configure_helper_functions && \
               add_module_aliases "docker" "basic" && \
               add_module_aliases "docker" "container" && \
               add_module_aliases "docker" "cleanup"; then
                save_state "helpers" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Grovel checks existence and basic functionality
grovel_docker() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "docker"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_docker() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_docker &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "docker"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "docker"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "docker"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Remove Docker configuration
remove_docker() {
    log "INFO" "Removing Docker configuration..." "docker"

    # Backup existing configurations
    local daemon_config=$(get_module_config "docker" ".shell.paths.daemon_config")
    [[ -f "$daemon_config" ]] && backup_file "$daemon_config" "docker"

    # Remove user from docker group
    if groups | grep -q "docker"; then
        sudo gpasswd -d "$USER" docker
    fi

    # Remove helper functions and aliases
    remove_module_aliases "docker" "basic"
    remove_module_aliases "docker" "container"
    remove_module_aliases "docker" "cleanup"

    local modules_dir=$(get_aliases_dir)
    sed -i '/# Docker helper functions - managed by devenv/,/# End Docker helper functions/d' "$modules_dir/functions.zsh"

    # Remove state file
    rm -f "$STATE_FILE"

    return 0
}

# Verify entire installation
verify_docker() {
    log "INFO" "Verifying Docker installation..." "docker"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "docker"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "Docker verification completed successfully" "docker"
        # Show installation details
        docker --version
        docker compose version
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_docker
        ;;
    install)
        install_docker "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_docker
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_docker
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "docker"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac