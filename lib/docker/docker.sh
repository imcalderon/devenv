#!/bin/bash
# lib/docker/docker.sh - Docker module implementation

# Use environment variables set by devenv.sh, with fallback if running standalone
if [ -z "${ROOT_DIR:-}" ]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Source dependencies using SCRIPT_DIR
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/module_base.sh"

grovel_docker() {
    log "INFO" "Checking Docker dependencies..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Check for main docker package
    if ! command -v docker &> /dev/null; then
        log "INFO" "Docker not found"
        return 1
    fi
    
    # Check user groups
    if ! groups | grep -q "docker"; then
        log "INFO" "User not in docker group"
        return 1
    fi
    
    # Check Docker daemon
    if ! systemctl is-active --quiet docker; then
        log "INFO" "Docker daemon not running"
        return 1
    fi
}

install_docker() {
    log "INFO" "Setting up Docker environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        install_docker_packages
    fi
    
    # Enable and configure Docker service
    if ! configure_docker_service; then
        return 1
    fi
    
    # Configure user groups
    if ! configure_user_groups; then
        return 1
    fi
    
    # Configure daemon
    if ! configure_docker_daemon; then
        return 1
    fi
    
    # Add helper functions to shell
    if ! configure_helper_functions; then
        return 1
    fi
    
    return 0
}

install_docker_packages() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    if command -v dnf &> /dev/null; then
        # RPM-based installation
        sudo dnf config-manager --add-repo "${config_modules_docker_repositories_rpm_repo_url}"
        sudo dnf install -y "${config_modules_docker_package_components[@]}"
    elif command -v apt-get &> /dev/null; then
        # DEB-based installation
        curl -fsSL "${config_modules_docker_repositories_deb_key_url}" | \
            sudo gpg --dearmor -o "${config_modules_docker_repositories_deb_key_path}"
        
        # Replace {release} placeholder with actual release
        repo_config="${config_modules_docker_repositories_deb_repo_config/\{release\}/$(lsb_release -cs)}"
        echo "$repo_config" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt-get update
        sudo apt-get install -y "${config_modules_docker_package_components[@]}"
    else
        log "ERROR" "Unsupported package manager"
        return 1
    fi
}

configure_docker_service() {
    log "INFO" "Configuring Docker service..."
    
    # Enable Docker service
    sudo systemctl enable docker
    
    # Start Docker service with retries
    local max_attempts=3
    local attempt=1
    
    while ! systemctl is-active --quiet docker; do
        if [ $attempt -gt $max_attempts ]; then
            log "ERROR" "Failed to start Docker service after $max_attempts attempts"
            return 1
        fi
        
        log "INFO" "Starting Docker service (attempt $attempt/$max_attempts)..."
        sudo systemctl start docker
        sleep 2
        ((attempt++))
    done
    
    log "INFO" "Docker service started successfully"
    return 0
}

configure_user_groups() {
    log "INFO" "Configuring user groups..."
    
    if ! groups | grep -q "docker"; then
        sudo usermod -aG docker "$USER"
        log "INFO" "Added user to docker group"
        log "WARN" "You may need to log out and back in for group changes to take effect"
    fi
    
    return 0
}

configure_docker_daemon() {
    log "INFO" "Configuring Docker daemon..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Create daemon configuration directory
    sudo mkdir -p "$(dirname ${config_modules_docker_paths_daemon_config})"
    
    # Backup existing config
    backup_file "${config_modules_docker_paths_daemon_config}"
    
    # Create daemon configuration
    local daemon_config='{
        "log-driver": "'"${config_modules_docker_daemon_config_logging_driver}"'",
        "log-opts": {
            "max-size": "'"${config_modules_docker_daemon_config_logging_options_max_size}"'",
            "max-file": "'"${config_modules_docker_daemon_config_logging_options_max_files}"'"
        }
    }'
    
    echo "$daemon_config" | sudo tee "${config_modules_docker_paths_daemon_config}" > /dev/null
    
    # Validate configuration
    if ! sudo dockerd --config-file="${config_modules_docker_paths_daemon_config}" --validate; then
        log "ERROR" "Invalid Docker daemon configuration"
        return 1
    fi
    
    # Restart Docker service to apply changes
    if ! restart_docker_service; then
        return 1
    fi
    
    return 0
}

restart_docker_service() {
    log "INFO" "Restarting Docker service..."
    
    if ! sudo systemctl restart docker; then
        log "ERROR" "Failed to restart Docker service"
        log "INFO" "Docker service logs:"
        sudo journalctl -u docker.service -n 50 --no-pager
        return 1
    fi
    
    # Wait for service to be fully available
    local timeout=30
    local elapsed=0
    while ! docker info &>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            log "ERROR" "Docker service failed to become available"
            return 1
        fi
        sleep 1
        ((elapsed++))
    done
    
    return 0
}

configure_helper_functions() {
    log "INFO" "Configuring Docker helper functions..."
    local zshrc="$HOME/.zshrc"
    local helper_block="# Docker helper functions - managed by devenv"
    
    # Remove existing helper block if it exists
    sed -i "/# Docker helper functions - managed by devenv/,/# End Docker helper functions/d" "$zshrc"
    
    # Add helper functions
    cat >> "$zshrc" << 'EOF'
# Docker helper functions - managed by devenv
dexec() {
    # Execute command in container, or open shell if no command provided
    local container=$1
    shift
    if [ $# -eq 0 ]; then
        docker exec -it $container bash
    else
        docker exec -it $container "$@"
    fi
}

dlog() {
    # View logs of container with optional tail
    local container=$1
    local lines=${2:-100}
    docker logs --tail $lines -f $container
}

dbash() {
    # Quick access to container bash shell
    docker exec -it $1 bash
}

dcex() {
    # Execute command in docker-compose service
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

remove_docker() {
    log "INFO" "Removing Docker configuration..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Restore daemon config from backup
    restore_backup "${config_modules_docker_paths_daemon_config}"
    
    # Remove user from docker group
    if groups | grep -q "docker"; then
        sudo gpasswd -d "$USER" docker
    fi
    
    # Remove helper functions
    sed -i "/# Docker helper functions - managed by devenv/,/# End Docker helper functions/d" "$HOME/.zshrc"
    
    log "INFO" "Docker configuration removed"
    return 0
}

verify_docker() {
    log "INFO" "Verifying Docker installation..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local verification_failed=false
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed"
        verification_failed=true
    fi
    
    # Check Docker service status
    if ! systemctl is-active --quiet docker; then
        log "ERROR" "Docker service is not running"
        verification_failed=true
    fi
    
    # Check Docker daemon responsiveness
    if ! docker info &>/dev/null; then
        log "ERROR" "Docker daemon is not responding"
        verification_failed=true
    fi
    
    # Check user groups
    if ! groups | grep -q "docker"; then
        log "ERROR" "User not in docker group"
        verification_failed=true
    fi
    
    # Check daemon configuration
    if [ ! -f "${config_modules_docker_paths_daemon_config}" ]; then
        log "ERROR" "Docker daemon configuration file not found"
        verification_failed=true
    fi
    
    # Check helper functions
    if ! grep -q "# Docker helper functions - managed by devenv" "$HOME/.zshrc"; then
        log "ERROR" "Docker helper functions not found in .zshrc"
        verification_failed=true
    fi
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "Docker verification complete"
    return 0
}

update_docker() {
    log "INFO" "Updating Docker environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Update Docker packages
    if command -v dnf &> /dev/null; then
        sudo dnf update -y "${config_modules_docker_package_components[@]}"
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get upgrade -y "${config_modules_docker_package_components[@]}"
    fi
    
    # Reconfigure daemon with latest settings
    configure_docker_daemon
    
    # Reconfigure helper functions
    configure_helper_functions
    
    return 0
}

generate_compose_template() {
    source "${SCRIPT_DIR}/compose_generator.sh"
    generate_compose_template "$@"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update|generate-compose <template>}"
        exit 1
    fi
    
    if [[ "$1" == "generate-compose" ]]; then
        shift
        generate_compose_template "$@"
    else
        module_base "$1" "docker"
    fi
fi