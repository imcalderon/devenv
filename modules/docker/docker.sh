#!/bin/bash
# modules/docker/docker.sh - Docker module implementation for containerization support

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
    "compose"       # Docker Compose installation
    "devenv"        # DevEnv container management
)

# Display module information
show_module_info() {
    cat << 'EOF'

🐳 Docker & Container Management
==============================

Description:
-----------
Docker installation and container management for DevEnv with
support for containerized development environments.

Benefits:
--------
✓ Consistent Development - Reproducible environments across machines
✓ Isolation - Separate dependencies for different tools
✓ Version Control - Specific versions of tools without conflicts
✓ WSL Integration - Proper configuration for Windows Subsystem for Linux

Components:
----------
1. Core Docker
   - Docker Engine CE
   - Docker CLI
   - Container runtime

2. Docker Compose
   - Multi-container application definition
   - Development environment orchestration
   
3. DevEnv Container Support
   - Container management for development modules
   - Cross-platform WSL integration
   - Volume mounting for configuration

Quick Start:
-----------
1. Check Docker Status:
   $ d info

2. Manage DevEnv Containers:
   $ devenv-container list
   $ devenv-container start python
   $ devenv-container stop python

3. Run command in container:
   $ devenv-container exec python pip list

Docker Aliases:
-------------
d     : docker
dc    : docker compose
di    : docker images
dps   : docker ps
dex   : docker exec -it

DevEnv Container Commands:
------------------------
devenv-container list   : List DevEnv containers
devenv-container build  : Build container for module
devenv-container start  : Start container for module
devenv-container stop   : Stop container for module
devenv-container exec   : Run command in module container

Configuration:
-------------
Location: /etc/docker/daemon.json
Container config: ${DEVENV_ROOT}/data/docker/containers

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
                "compose")
                    if command -v docker-compose &>/dev/null; then
                        echo "  Compose Version: $(docker-compose --version)"
                    elif docker compose version &>/dev/null; then
                        echo "  Compose Plugin: $(docker compose version)"
                    fi
                    ;;
                "service")
                    local running=false
                    if command -v systemctl &>/dev/null && systemctl is-active --quiet docker; then
                        running=true
                    elif command -v docker &>/dev/null && docker info &>/dev/null; then
                        running=true
                    fi
                    
                    if $running; then
                        echo "  Service: Running"
                    else
                        echo "  Service: Not running"
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

# Check if running in WSL
is_wsl() {
    grep -q "microsoft" /proc/version 2>/dev/null
    return $?
}

# Detect platform and return docker installation commands
get_docker_install_command() {
    if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        echo "apt-get update && apt-get install -y docker.io docker-compose"
    elif command -v dnf &>/dev/null; then
        # Fedora/RHEL
        echo "dnf -y install docker docker-compose"
    elif command -v yum &>/dev/null; then
        # Older RHEL/CentOS
        echo "yum -y install docker docker-compose"
    else
        # Unknown platform, use official install script
        echo 'curl -fsSL https://get.docker.com | sh'
    fi
}

# Install core Docker
install_docker_core() {
    if ! command -v docker &>/dev/null; then
        log "INFO" "Installing Docker..." "docker"

        if is_wsl; then
            log "INFO" "WSL detected, installing Docker..." "docker"
            
            # For WSL, we install Docker CLI only since we'll use Docker Desktop
            sudo apt-get update
            sudo apt-get install -y docker.io docker-compose
            
            # Create daemon configuration for Docker Desktop socket
            sudo mkdir -p /etc/docker
            echo '{"hosts": ["unix:///var/run/docker.sock", "unix:///var/run/docker-desktop.sock"]}' | sudo tee /etc/docker/daemon.json
            
            log "INFO" "Docker CLI installed for WSL" "docker"
            log "INFO" "Please ensure Docker Desktop for Windows is running with WSL integration enabled" "docker"
        else
            # Get and execute the installation command
            local install_cmd=$(get_docker_install_command)
            log "INFO" "Running: $install_cmd" "docker"
            sudo bash -c "$install_cmd"
        fi
    fi

    # Check if Docker was installed successfully
    if ! command -v docker &>/dev/null; then
        log "ERROR" "Failed to install Docker" "docker"
        return 1
    fi

    return 0
}

# Configure Docker daemon
configure_docker_daemon() {
    log "INFO" "Configuring Docker daemon..." "docker"

    if is_wsl; then
        # For WSL, we've already set up the daemon.json file in install_docker_core
        log "INFO" "Docker daemon configured for WSL" "docker"
        return 0
    fi

    # Configure daemon.json
    local daemon_config="/etc/docker/daemon.json"
    local temp_config=$(mktemp)

    # Get daemon configuration from config file
    local docker_config=$(get_module_config "docker" ".docker.daemon")
    
    if [[ -n "$docker_config" ]]; then
        echo "$docker_config" > "$temp_config"
        sudo mkdir -p "$(dirname "$daemon_config")"
        sudo cp "$temp_config" "$daemon_config"
        sudo chmod 644 "$daemon_config"
    else
        # Default configuration if none specified
        cat > "$temp_config" << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
        sudo mkdir -p "$(dirname "$daemon_config")"
        sudo cp "$temp_config" "$daemon_config"
        sudo chmod 644 "$daemon_config"
    fi

    # Clean up
    rm -f "$temp_config"

    return 0
}

# Configure Docker service
configure_docker_service() {
    log "INFO" "Configuring Docker service..." "docker"

    if is_wsl; then
        # For WSL, we don't need to start the service, we use Docker Desktop
        log "INFO" "Docker service managed by Docker Desktop in WSL" "docker"
        return 0
    fi

    # Enable and start the Docker service
    if command -v systemctl &>/dev/null; then
        sudo systemctl enable docker
        sudo systemctl start docker
    else
        log "WARN" "systemctl not found, unable to enable Docker service" "docker"
        return 1
    fi

    return 0
}

# Configure Docker Compose
configure_docker_compose() {
    log "INFO" "Configuring Docker Compose..." "docker"

    # Check if Docker Compose is already installed
    if command -v docker-compose &>/dev/null || docker compose version &>/dev/null; then
        log "INFO" "Docker Compose already installed" "docker"
        return 0
    fi

    # Install Docker Compose
    log "INFO" "Installing Docker Compose..." "docker"
    
    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y docker-compose
    elif command -v dnf &>/dev/null; then
        sudo dnf -y install docker-compose
    elif command -v yum &>/dev/null; then
        sudo yum -y install docker-compose
    else
        # Use Python PIP as fallback
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

    # Check if Docker Compose was installed successfully
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        log "ERROR" "Failed to install Docker Compose" "docker"
        return 1
    fi

    return 0
}

# Configure DevEnv container management
configure_devenv_containers() {
    log "INFO" "Configuring DevEnv container management..." "docker"

    local devenv_data_dir="${DEVENV_ROOT}/data/docker"
    local container_dir="${devenv_data_dir}/containers"
    local bin_dir="${DEVENV_ROOT}/bin"

    # Create directories
    mkdir -p "$container_dir" "$bin_dir"

    # Create the container management script
    cat > "${bin_dir}/devenv-container" << 'EOF'
#!/bin/bash

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$ROOT_DIR/config.json"
CONTAINER_DIR="$ROOT_DIR/data/docker/containers"

# Command help
show_help() {
    echo "DevEnv Container Management Utility"
    echo ""
    echo "Usage: devenv-container COMMAND [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list                 List all DevEnv containers"
    echo "  build MODULE         Build container for MODULE"
    echo "  start MODULE         Start container for MODULE"
    echo "  stop MODULE          Stop container for MODULE"
    echo "  restart MODULE       Restart container for MODULE"
    echo "  exec MODULE CMD      Execute CMD in MODULE container"
    echo "  logs MODULE          Show logs for MODULE container"
    echo "  shell MODULE         Start a shell in MODULE container"
    echo "  status MODULE        Show status of MODULE container"
    echo ""
    echo "Options:"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  devenv-container list"
    echo "  devenv-container build python"
    echo "  devenv-container start python"
    echo "  devenv-container exec python pip list"
    echo "  devenv-container shell python"
}

# List containers
list_containers() {
    echo "DevEnv Containers:"
    echo "-----------------"
    
    # Get all modules that can be containerized
    if command -v jq &>/dev/null; then
        local modules=$(jq -r '.global.container.modules | keys[]' "$CONFIG_FILE" 2>/dev/null)
        
        if [[ -n "$modules" ]]; then
            for module in $modules; do
                local containerize=$(jq -r ".global.container.modules.\"$module\".containerize" "$CONFIG_FILE" 2>/dev/null)
                if [[ "$containerize" == "true" ]]; then
                    local image=$(jq -r ".global.container.modules.\"$module\".image" "$CONFIG_FILE" 2>/dev/null)
                    
                    # Check container status
                    if docker ps -a --format '{{.Names}}' | grep -q "devenv-$module"; then
                        if docker ps --format '{{.Names}}' | grep -q "devenv-$module"; then
                            echo "✓ $module (Running) - $image"
                        else
                            echo "✗ $module (Stopped) - $image"
                        fi
                    else
                        echo "- $module (Not created) - $image"
                    fi
                fi
            done
        else
            echo "No containerized modules found in configuration."
        fi
    else
        echo "Error: jq not installed. Please install jq to use this command."
        return 1
    fi
}

# Build container for module
build_container() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    # Check if module can be containerized
    if command -v jq &>/dev/null; then
        local containerize=$(jq -r ".global.container.modules.\"$module\".containerize" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$containerize" != "true" ]]; then
            echo "Error: Module $module is not configured for containerization"
            return 1
        fi
        
        local image=$(jq -r ".global.container.modules.\"$module\".image" "$CONFIG_FILE" 2>/dev/null)
        if [[ -z "$image" || "$image" == "null" ]]; then
            echo "Error: No image specified for module $module"
            return 1
        fi
        
        # Pull the image
        echo "Pulling image: $image"
        docker pull "$image"
        
        # Create a simple Dockerfile for the module
        mkdir -p "$CONTAINER_DIR/$module"
        cat > "$CONTAINER_DIR/$module/Dockerfile" << EOF
FROM $image

# Create user to match host user
RUN groupadd -g $(id -g) $(id -gn) && \\
    useradd -m -u $(id -u) -g $(id -g) -s /bin/bash user

# Create directories
RUN mkdir -p /devenv/modules /devenv/lib /devenv/bin /devenv/data

# Set working directory
WORKDIR /devenv

# Set user
USER user

# Set entrypoint to bash by default
ENTRYPOINT ["/bin/bash"]
EOF
        
        # Build the container
        echo "Building container for module: $module"
        docker build -t "devenv-$module" -f "$CONTAINER_DIR/$module/Dockerfile" "$CONTAINER_DIR/$module"
        
        echo "Container for module $module built successfully"
        return 0
    else
        echo "Error: jq not installed. Please install jq to use this command."
        return 1
    fi
}

# Start container for module
start_container() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    # Check if module can be containerized
    if command -v jq &>/dev/null; then
        local containerize=$(jq -r ".global.container.modules.\"$module\".containerize" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$containerize" != "true" ]]; then
            echo "Error: Module $module is not configured for containerization"
            return 1
        fi
        
        # Check if container exists
        if ! docker ps -a --format '{{.Names}}' | grep -q "devenv-$module"; then
            # Build the container first
            build_container "$module"
        fi
        
        # Get container configuration
        local image=$(jq -r ".global.container.modules.\"$module\".image" "$CONFIG_FILE" 2>/dev/null)
        local mounts=""
        
        # Add global mount paths
        for key in $(jq -r '.global.container.mount_paths | keys[]' "$CONFIG_FILE" 2>/dev/null); do
            local path=$(jq -r ".global.container.mount_paths.\"$key\"" "$CONFIG_FILE" 2>/dev/null)
            # Expand environment variables
            path=$(eval echo "$path")
            mounts="$mounts -v $path"
        done
        
        # Add module-specific extra mounts
        for mount in $(jq -r ".global.container.modules.\"$module\".extra_mounts[]" "$CONFIG_FILE" 2>/dev/null); do
            # Expand environment variables
            mount=$(eval echo "$mount")
            mounts="$mounts -v $mount"
        done
        
        # Get extra arguments
        local extra_args=$(jq -r ".global.container.modules.\"$module\".extra_args" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$extra_args" == "null" ]]; then
            extra_args=""
        fi
        
        # Get network configuration
        local network=$(jq -r ".global.container.network" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$network" == "null" ]]; then
            network="bridge"
        fi
        
        # Start the container
        echo "Starting container for module: $module"
        docker run -d --name "devenv-$module" \
            $mounts \
            -v "$ROOT_DIR:/devenv" \
            -v "/var/run/docker.sock:/var/run/docker.sock" \
            --network="$network" \
            $extra_args \
            "devenv-$module" \
            sleep infinity
        
        echo "Container for module $module started"
        return 0
    else
        echo "Error: jq not installed. Please install jq to use this command."
        return 1
    fi
}

# Stop container for module
stop_container() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    # Check if container exists and is running
    if docker ps --format '{{.Names}}' | grep -q "devenv-$module"; then
        echo "Stopping container for module: $module"
        docker stop "devenv-$module"
        echo "Container for module $module stopped"
    else
        echo "Container for module $module is not running"
    fi
    
    return 0
}

# Execute command in container
exec_in_container() {
    local module="$1"
    shift
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    if [[ $# -eq 0 ]]; then
        echo "Error: Command is required"
        show_help
        return 1
    fi
    
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "devenv-$module"; then
        echo "Container for module $module is not running"
        
        # Ask to start the container
        read -p "Start the container? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            start_container "$module"
        else
            return 1
        fi
    fi
    
    # Execute the command
    echo "Executing in container for module $module: $@"
    docker exec -it "devenv-$module" "$@"
    
    return 0
}

# Start a shell in container
shell_in_container() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    # Check if container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "devenv-$module"; then
        echo "Container for module $module is not running"
        
        # Ask to start the container
        read -p "Start the container? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            start_container "$module"
        else
            return 1
        fi
    fi
    
    # Start a shell
    echo "Starting shell in container for module $module"
    docker exec -it "devenv-$module" bash
    
    return 0
}

# Show logs for container
show_container_logs() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "devenv-$module"; then
        echo "Showing logs for container: $module"
        docker logs "devenv-$module"
    else
        echo "Container for module $module does not exist"
        return 1
    fi
    
    return 0
}

# Show status of container
show_container_status() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        echo "Error: MODULE is required"
        show_help
        return 1
    fi
    
    # Check if container exists
    if docker ps -a --format '{{.Names}}' | grep -q "devenv-$module"; then
        echo "Status for container: $module"
        docker ps -a --filter "name=devenv-$module" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
        
        # Show additional information
        echo -e "\nContainer Details:"
        docker inspect "devenv-$module" --format '{{json .}}' | jq '.ContainerJSONFile'
    else
        echo "Container for module $module does not exist"
        return 1
    fi
    
    return 0
}

# Main function
main() {
    local command="$1"
    shift
    
    case "$command" in
        list)
            list_containers
            ;;
        build)
            build_container "$@"
            ;;
        start)
            start_container "$@"
            ;;
        stop)
            stop_container "$@"
            ;;
        restart)
            stop_container "$1" && start_container "$1"
            ;;
        exec)
            exec_in_container "$@"
            ;;
        shell)
            shell_in_container "$@"
            ;;
        logs)
            show_container_logs "$@"
            ;;
        status)
            show_container_status "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
EOF

    # Make the script executable
    chmod +x "${bin_dir}/devenv-container"
    
    # Add to PATH
    echo 'export PATH="$PATH:'"${bin_dir}"'"' >> "$HOME/.bashrc"
    
    # If ZSH exists, add to ZSH also
    if [[ -f "$HOME/.zshrc" ]]; then
        echo 'export PATH="$PATH:'"${bin_dir}"'"' >> "$HOME/.zshrc"
    fi
    
    return 0
}

# Add Docker aliases
configure_docker_aliases() {
    log "INFO" "Configuring Docker aliases..." "docker"

    # Add aliases from config
    add_module_aliases "docker" "basic" || return 1
    add_module_aliases "docker" "container" || return 1
    add_module_aliases "docker" "cleanup" || return 1

    return 0
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
            if install_docker_core; then
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
        "compose")
            if configure_docker_compose; then
                save_state "compose" "installed"
                return 0
            fi
            ;;
        "devenv")
            if configure_devenv_containers && configure_docker_aliases; then
                save_state "devenv" "installed"
                return 0
            fi
            ;;
    esac
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
            # For WSL, we just check if Docker Desktop integration works
            if is_wsl; then
                docker info &>/dev/null
            else
                # For native Linux, check if daemon.json exists
                [[ -f "/etc/docker/daemon.json" ]]
            fi
            ;;
        "service")
            # For WSL, we check if Docker Desktop works
            if is_wsl; then
                docker info &>/dev/null
            else
                # For native Linux, check if service is running
                if command -v systemctl &>/dev/null; then
                    systemctl is-active --quiet docker
                else
                    docker info &>/dev/null
                fi
            fi
            ;;
        "compose")
            command -v docker-compose &>/dev/null || docker compose version &>/dev/null
            ;;
        "devenv")
            # Check if container management script exists and is executable
            [[ -x "$DEVENV_ROOT/bin/devenv-container" ]] && 
            # Check if Docker aliases are configured
            list_module_aliases "docker" "basic" &>/dev/null && 
            list_module_aliases "docker" "container" &>/dev/null && 
            list_module_aliases "docker" "cleanup" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
    return $?
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

    # Stop and remove all DevEnv containers
    if command -v docker &>/dev/null; then
        log "INFO" "Stopping and removing DevEnv containers..." "docker"
        for container in $(docker ps -a --format '{{.Names}}' | grep "^devenv-"); do
            docker stop "$container" 2>/dev/null
            docker rm "$container" 2>/dev/null
        done
    fi

    # Remove DevEnv container management script
    rm -f "$DEVENV_ROOT/bin/devenv-container"

    # Remove aliases
    remove_module_aliases "docker" "basic"
    remove_module_aliases "docker" "container"
    remove_module_aliases "docker" "cleanup"

    # Remove state file
    rm -f "$STATE_FILE"

    log "WARN" "Docker engine was preserved. Use 'sudo apt-get remove docker.io docker-compose' to remove completely." "docker"

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
        docker --version
        
        # Test Docker functionality
        log "INFO" "Testing Docker functionality..." "docker"
        if docker run --rm hello-world 2>/dev/null | grep -q "Hello from Docker!"; then
            log "INFO" "Docker is functioning correctly" "docker"
        else
            log "WARN" "Docker hello-world test failed" "docker"
            status=1
        fi
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