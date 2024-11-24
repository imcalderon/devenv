#!/bin/bash
# lib/docker.sh - Docker module implementation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../logging.sh"
source "${SCRIPT_DIR}/../yaml_parser.sh"
source "${SCRIPT_DIR}/../module_base.sh"

grovel_docker() {
    log "INFO" "Checking Docker dependencies..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Check for main docker package
    if ! command -v docker &> /dev/null; then
        log "INFO" "Docker not found"
        return 1
    fi
    
    # Check user groups
    for group in "${config_modules_docker_user_groups[@]}"; do
        if ! groups | grep -q "$group"; then
            log "INFO" "User not in required group: $group"
            return 1
        fi
    done
}

install_docker() {
    log "INFO" "Setting up Docker environment..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        install_docker_packages
    fi
    
    # Configure Docker daemon
    configure_docker_daemon
    
    # Enable and start service
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # Configure user groups
    configure_user_groups
}

install_docker_packages() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    if command -v dnf &> /dev/null; then
        # RPM-based installation
        sudo dnf config-manager --add-repo "${config_modules_docker_repositories_rpm_repo_url}"
        sudo dnf install -y "${config_modules_docker_package_components[@]}"
    elif command -v apt-get &> /dev/null; then
        # DEB-based installation
        curl -fsSL "${config_modules_docker_repositories_deb_key_url}" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
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

configure_docker_daemon() {
    log "INFO" "Configuring Docker daemon..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    sudo mkdir -p /etc/docker
    
    # Backup existing config
    backup_file "/etc/docker/daemon.json"
    
    # Build daemon.json from config
    local daemon_config='{
        "default-memory-swap": "'"${config_modules_docker_daemon_config_resources_memory_swap}"'",
        "memory": "'"${config_modules_docker_daemon_config_resources_memory_limit}"'",
        "cpu-shares": '"${config_modules_docker_daemon_config_resources_cpu_shares}"',
        "log-driver": "'"${config_modules_docker_daemon_config_logging_driver}"'",
        "log-opts": {
            "max-size": "'"${config_modules_docker_daemon_config_logging_options_max_size}"'",
            "max-file": "'"${config_modules_docker_daemon_config_logging_options_max_files}"'"
        }
    }'
    
    echo "$daemon_config" | sudo tee /etc/docker/daemon.json > /dev/null
    
    # Restart Docker to apply new configuration
    sudo systemctl restart docker
}

configure_user_groups() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    for group in "${config_modules_docker_user_groups[@]}"; do
        if ! groups | grep -q "$group"; then
            log "INFO" "Adding user to group: $group"
            sudo usermod -aG "$group" "$USER"
        fi
    done
}

remove_docker() {
    log "INFO" "Removing Docker configuration..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Restore daemon config from backup
    restore_backup "/etc/docker/daemon.json"
    
    # Remove user from groups
    for group in "${config_modules_docker_user_groups[@]}"; do
        sudo gpasswd -d "$USER" "$group"
    done
}

verify_docker() {
    log "INFO" "Verifying Docker installation..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    local verification_failed=false
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed"
        verification_failed=true
    fi
    
    # Check Docker service
    if ! sudo systemctl is-active docker >/dev/null 2>&1; then
        log "ERROR" "Docker service is not running"
        verification_failed=true
    fi
    
    # Check user groups
    for group in "${config_modules_docker_user_groups[@]}"; do
        if ! groups | grep -q "$group"; then
            log "ERROR" "User not in required group: $group"
            verification_failed=true
        fi
    done
    
    # Check daemon configuration
    if [ ! -f "/etc/docker/daemon.json" ]; then
        log "ERROR" "Docker daemon configuration file not found"
        verification_failed=true
    fi
    
    # Verify Docker functionality
    if ! docker info >/dev/null 2>&1; then
        log "ERROR" "Unable to connect to Docker daemon"
        verification_failed=true
    fi
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "Docker verification complete"
    return 0
}

update_docker() {
    log "INFO" "Updating Docker environment..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Update Docker packages
    if command -v dnf &> /dev/null; then
        sudo dnf update -y "${config_modules_docker_package_components[@]}"
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get upgrade -y "${config_modules_docker_package_components[@]}"
    fi
    
    # Reconfigure daemon with latest settings
    configure_docker_daemon
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update}"
        exit 1
    fi
    module_base "$1" "docker"
fi