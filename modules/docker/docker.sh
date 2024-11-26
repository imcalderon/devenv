#!/bin/bash
# modules/docker/docker.sh - Docker module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/alias.sh"    # For shell alias support

# Initialize module
init_module "docker" || exit 1

# Check for Docker installation and configuration
grovel_docker() {
    if ! command -v docker &>/dev/null; then
        log "INFO" "Docker not found" "docker"
        return 1
    fi
    
    # Check user groups
    if ! groups | grep -q "docker"; then
        log "INFO" "User not in docker group" "docker"
        return 1
    fi
    
    # Check Docker daemon
    if ! systemctl is-active --quiet docker; then
        log "INFO" "Docker daemon not running" "docker"
        return 1
    fi
    
    return 0
}

# Install and configure Docker
install_docker() {
    log "INFO" "Setting up Docker environment..." "docker"

    # Install Docker if needed
    if ! command -v docker &>/dev/null; then
        if ! install_docker_package; then
            return 1
        fi
    fi

    # Configure Docker daemon first
    if ! configure_docker_daemon; then
        return 1
    fi
    # Then configure and start the service
    if ! configure_docker_service; then
        return 1
    fi

    # Configure user groups
    if ! configure_user_groups; then
        return 1
    fi

    # Configure helper functions and aliases
    configure_helper_functions || return 1
    add_module_aliases "docker" "basic" || return 1
    add_module_aliases "docker" "container" || return 1
    add_module_aliases "docker" "cleanup" || return 1
    # Show summary on success
    if [ $? -eq 0 ]; then
        show_docker_summary
    fi
    return 0
}

# Install Docker packages based on system package manager
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

    return 0
}

# Configure Docker daemon
configure_docker_daemon() {
    log "INFO" "Configuring Docker daemon..." "docker"

    local config_dir=$(get_module_config "docker" ".shell.paths.config_dir")
    local daemon_config=$(get_module_config "docker" ".shell.paths.daemon_config")

    # Debug logging
    log "DEBUG" "Config dir: $config_dir" "docker"
    log "DEBUG" "Daemon config path: $daemon_config" "docker"

    # Create configuration directory with sudo
    sudo mkdir -p "$config_dir"

    # Backup existing configuration
    [[ -f "$daemon_config" ]] && backup_file "$daemon_config" "docker"

    # Debug: Show the configuration we're trying to write
    log "DEBUG" "Attempting to write daemon configuration:" "docker"
    get_module_config "docker" ".docker.daemon" | tee /dev/stderr

    # Create temp file and write configuration
    local temp_config=$(mktemp)
    log "DEBUG" "Created temp file: $temp_config" "docker"
    
    if get_module_config "docker" ".docker.daemon" > "$temp_config"; then
        log "DEBUG" "Successfully wrote to temp file" "docker"
        cat "$temp_config" | tee /dev/stderr
    else
        log "ERROR" "Failed to write daemon configuration to temp file" "docker"
        rm -f "$temp_config"
        return 1
    fi

    # Use sudo to move the temp file
    if sudo cp "$temp_config" "$daemon_config"; then
        log "DEBUG" "Successfully copied config to $daemon_config" "docker"
        sudo chown root:root "$daemon_config"
        sudo chmod 644 "$daemon_config"
        # Verify the file contents
        log "DEBUG" "Final daemon configuration:" "docker"
        sudo cat "$daemon_config" | tee /dev/stderr
    else
        log "ERROR" "Failed to copy configuration to $daemon_config" "docker"
        rm -f "$temp_config"
        return 1
    fi

    # Cleanup
    rm -f "$temp_config"

    # Restart Docker service to apply changes
    log "INFO" "Restarting Docker service..." "docker"
    if ! restart_docker_service; then
        return 1
    fi

    return 0
}

# Configure Docker service
configure_docker_service() {
    log "INFO" "Configuring Docker service..." "docker"

    # Enable and start Docker service
    sudo systemctl enable docker
    
    if ! restart_docker_service; then
        return 1
    fi

    return 0
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

    return 0
}

# Verify Docker installation and configuration
verify_docker() {
    log "INFO" "Verifying Docker installation..." "docker"
    local status=0

    # Check Docker installation
    if ! command -v docker &>/dev/null; then
        log "ERROR" "Docker is not installed" "docker"
        status=1
    fi

    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log "ERROR" "Docker service is not running" "docker"
        status=1
    fi

    # Check group membership
    if ! groups | grep -q "docker"; then
        log "ERROR" "User not in docker group" "docker"
        status=1
    fi

    # Check Docker daemon
    if ! docker info &>/dev/null; then
        log "ERROR" "Docker daemon is not responding" "docker"
        status=1
    fi

    # Check helper functions
    local modules_dir=$(get_aliases_dir)
    if ! grep -q "# Docker helper functions" "$modules_dir/functions.zsh"; then
        log "ERROR" "Docker helper functions not configured" "docker"
        status=1
    fi

    # Check aliases
    if ! list_module_aliases "docker" "basic" &>/dev/null || \
       ! list_module_aliases "docker" "container" &>/dev/null || \
       ! list_module_aliases "docker" "cleanup" &>/dev/null; then
        log "ERROR" "Docker aliases not configured" "docker"
        status=1
    fi

    return $status
}

show_docker_summary() {
    cat << 'EOF'

🐳 Docker Setup Complete - Quick Reference
========================================

Helper Functions:
----------------
dexec <container> [cmd]  : Execute command in container (or open shell)
dlog <container> [lines] : View container logs (default 100 lines)
dbash <container>        : Quick access to container bash shell
dcex <service> [cmd]     : Execute command in docker-compose service

Basic Aliases:
-------------
d    : docker
dc   : docker compose
dcu  : docker compose up
dcub : docker compose up --build
dcd  : docker compose down
dcl  : docker compose logs -f

Container Aliases:
----------------
dps    : docker ps
dpsa   : docker ps -a
dex    : docker exec -it
dtop   : docker top
dstats : docker stats

Cleanup Aliases:
--------------
dprune  : docker system prune -f
dvprune : docker volume prune -f
dclean  : docker system prune -af --volumes

Start using Docker with:
- List containers: dps
- Create and start services: dcu
- View logs: dlog <container>
- Execute commands: dexec <container> <cmd>

EOF
}
# Execute requested action
case "${1:-}" in
    grovel)
        grovel_docker
        ;;
    install)
        install_docker
        ;;
    remove)
        remove_docker
        ;;
    verify)
        verify_docker
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "docker"
        exit 1
        ;;
esac