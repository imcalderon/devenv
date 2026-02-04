#!/bin/bash
# modules/docker/docker.sh - Docker module implementation for containerization support

# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "docker" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/docker.state"
WSL_CONFIG_STATE="$HOME/.devenv/state/wsl_docker.state"

# Define module components
COMPONENTS=(
    "core"          # Base Docker installation
    "daemon"        # Docker daemon configuration
    "service"       # Docker service setup
    "compose"       # Docker Compose installation
    "devenv"        # DevEnv container management
)



# Detect if running in WSL
is_wsl() {
    grep -q "microsoft" /proc/version 2>/dev/null
    return $?
}

# Verify Docker is fully functional in WSL environment
# This function can be used by other modules (exported)
verify_docker_wsl_integration() {
    # Only applicable in WSL environments
    if ! is_wsl; then
        return 0  # Not in WSL, so no integration needed
    fi
    
    # Check if Docker command exists
    if ! command -v docker &>/dev/null; then
        log "DEBUG" "Docker command not found" "docker"
        return 1
    fi
    
    # Check if Docker socket exists
    if [[ ! -S /var/run/docker.sock ]] && [[ ! -S /var/run/docker-desktop.sock ]]; then
        log "DEBUG" "No Docker socket found" "docker"
        return 1
    fi
    
    # Try to connect to Docker with timeout 
    if ! timeout 20 docker info &>/dev/null; then
        log "DEBUG" "Docker daemon not accessible within timeout" "docker"
        return 1
    fi
    
    # Check if current user is in docker group
    if ! groups | grep -q docker; then
        log "DEBUG" "Current user not in docker group" "docker"
        return 1
    fi
    
    # If we got here, Docker is correctly configured for WSL
    return 0
}
# Export essential functions for other modules
export -f is_wsl
export -f verify_docker_wsl_integration
# Check if Docker Desktop restart is needed
is_restart_needed() {
    # If a restart was requested but not completed, return true
    if [[ -f "$WSL_CONFIG_STATE" ]]; then
        local restart_time=$(grep "docker_restart_requested=" "$WSL_CONFIG_STATE" | cut -d '=' -f2)
        if [[ -n "$restart_time" ]]; then
            local current_time=$(date +%s)
            local restart_age=$((current_time - restart_time))
            
            # If restart was requested less than 1 hour ago and Docker isn't working
            if [[ $restart_age -lt 3600 ]] && ! verify_docker_wsl_integration; then
                return 0
            fi
        fi
    fi
    
    # No restart needed
    return 1
}

# Request WSL restart when needed
request_wsl_restart() {
    log "INFO" "A system restart is needed for Docker permissions to take effect" "docker"
    
    # Save state indicating Docker was just configured
    mkdir -p "$(dirname "$WSL_CONFIG_STATE")"
    echo "docker_restart_requested=$(date +%s)" > "$WSL_CONFIG_STATE"
    
    # Ask user if they want to restart now
    echo -e "\n⚠️  Your WSL environment needs to restart for Docker permissions to take effect."
    read -p "Would you like to restart WSL now? (y/n): " restart_now
    if [[ "$restart_now" =~ ^[Yy]$ ]]; then
        log "INFO" "Requesting WSL restart... this will close your current session" "docker"
        echo -e "\n🔄 Shutting down WSL... Please restart your WSL session after shutdown completes."
        echo "🛠️  After restarting, run the installation command again to continue setup."
        
        # Request WSL shutdown with a delay to let the message be seen
        sleep 2
        powershell.exe -Command "wsl --shutdown" || true
        log "INFO" "WSL shutdown requested" "docker"
        exit 0
    else
        log "WARN" "Docker configuration is incomplete until you restart WSL" "docker"
        echo -e "\n⚠️  You'll need to restart WSL manually before Docker will work correctly."
        echo "📋 Run the following in PowerShell to restart when ready:"
        echo "   wsl --shutdown"
        return 1
    fi
}

# Clear docker restart state
clear_restart_state() {
    if [[ -f "$WSL_CONFIG_STATE" ]]; then
        # Keep the file but remove the restart request
        sed_inplace '/docker_restart_requested=/d' "$WSL_CONFIG_STATE"
    fi
}

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
Container config: ${DEVENV_DATA_ROOT}/containers

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
                        echo "  Version: $(docker --version 2>/dev/null || echo "Not available")"
                    fi
                    ;;
                "compose")
                    if command -v docker-compose &>/dev/null; then
                        echo "  Compose Version: $(docker-compose --version 2>/dev/null || echo "Not available")"
                    elif docker compose version &>/dev/null; then
                        echo "  Compose Plugin: $(docker compose version 2>/dev/null || echo "Not available")"
                    fi
                    ;;
                "service")
                    if is_wsl; then
                        if verify_docker_wsl_integration; then
                            echo "  WSL Integration: Active"
                        else
                            echo "  WSL Integration: ⚠️ Configuration incomplete"
                        fi
                    else
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
                    fi
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
    
    # Show special WSL status if applicable
    if is_wsl; then
        echo -e "\nWSL Integration Status:"
        echo "--------------------"
        if verify_docker_wsl_integration; then
            echo "✓ Docker Desktop WSL Integration: Active and working"
        else
            echo "✗ Docker Desktop WSL Integration: Not properly configured"
            if command -v docker &>/dev/null; then
                echo "  • Docker CLI is installed"
            else
                echo "  ✗ Docker CLI is not installed"
            fi
            
            if groups | grep -q docker; then
                echo "  • Current user is in the docker group"
            else
                echo "  ✗ Current user is not in the docker group"
            fi
            
            if [[ -S /var/run/docker.sock ]]; then
                echo "  • Docker socket exists"
                if timeout 2 docker info &>/dev/null; then
                    echo "  • Docker daemon is responsive"
                else
                    echo "  ✗ Docker daemon is not responsive"
                    echo "    → Ensure Docker Desktop is running with WSL integration enabled"
                    echo "    → You may need to restart WSL: 'wsl --shutdown' in PowerShell"
                fi
            else
                echo "  ✗ Docker socket not found"
                echo "    → Ensure Docker Desktop is running with WSL integration enabled"
            fi
        fi
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

# Get Docker socket path (handles both standard and WSL Desktop paths)
get_docker_socket_path() {
    if [[ -S /var/run/docker-desktop.sock ]]; then
        echo "/var/run/docker-desktop.sock"
    else
        echo "/var/run/docker.sock"
    fi
}

# Improved permission handling for Docker in WSL
fix_docker_permissions() {
    if command -v docker &>/dev/null; then
        log "INFO" "Docker found, checking permissions..." "docker"
        
        # Determine which Docker socket to use
        local docker_socket=$(get_docker_socket_path)
        log "INFO" "Using Docker socket: $docker_socket" "docker"
        
        # Test Docker connectivity with timeout (10 seconds)
        if ! timeout 10 docker info &>/dev/null; then
            log "WARN" "Docker permission issues detected" "docker"
            
            # Check if docker group exists
            if getent group docker &>/dev/null; then
                # Check if user is already in the docker group
                if ! groups | grep -q docker; then
                    log "INFO" "Adding current user to docker group..." "docker"
                    sudo usermod -aG docker $USER
                    
                    # Fix socket permissions
                    if [[ -S "$docker_socket" ]]; then
                        log "INFO" "Fixing Docker socket permissions..." "docker"
                        sudo chown root:docker "$docker_socket"
                        sudo chmod 660 "$docker_socket"
                    fi
                    
                    log "WARN" "Docker permissions fixed. You need to log out and back in for group changes to take effect"
                    # Signal that a restart is required
                    request_wsl_restart
                else
                    log "INFO" "User already in docker group, but Docker still not accessible" "docker"
                    
                    # Try to fix socket permissions anyway
                    if [[ -S "$docker_socket" ]]; then
                        log "INFO" "Fixing Docker socket permissions..." "docker"
                        sudo chown root:docker "$docker_socket"
                        sudo chmod 660 "$docker_socket"
                        
                        log "INFO" "Please try running docker commands again" "docker"
                    fi
                    
                    log "INFO" "This could be a Docker Desktop configuration issue" "docker"
                    request_wsl_restart
                fi
            else
                log "INFO" "Docker group doesn't exist, creating..." "docker"
                sudo groupadd docker
                sudo usermod -aG docker $USER
                
                log "INFO" "Added docker group and current user to it" "docker"
                log "WARN" "You need to log out and back in for group changes to take effect" "docker"
                request_wsl_restart
            fi
        else
            log "INFO" "Docker permissions are correctly configured" "docker"
            clear_restart_state
        fi

        log "INFO" "checking WSL integration..." "docker"
        
        if ! timeout 5 docker info &>/dev/null; then
            log "WARN" "Docker command exists but daemon is not accessible." "docker"
            log "INFO" "Please ensure Docker Desktop is running with WSL integration enabled for this distribution." "docker"
            log "INFO" "Steps to enable:" "docker"
            log "INFO" "1. Open Docker Desktop" "docker"
            log "INFO" "2. Go to Settings > Resources > WSL Integration" "docker"
            log "INFO" "3. Enable integration with this distribution" "docker"
            log "INFO" "4. Click 'Apply & Restart'" "docker"
        else
            log "INFO" "Docker Desktop WSL integration is working correctly." "docker"
            clear_restart_state
        fi
    fi
}

# Detect and configure WSL environment
setup_wsl_environment() {
    local force_flag="${1:-}"  # Set default empty value to avoid unbound variable
    
    # Only run this on Windows/WSL
    if ! is_wsl; then
        return 0
    fi
    
    # Check if WSL is already configured
    local wsl_state_file="${DEVENV_STATE_DIR}/wsl_configured"
    if [[ -f "$wsl_state_file" ]] && [[ "$force_flag" != "--force" ]]; then
        log "INFO" "WSL environment already configured, running permission check anyway..." "docker"
        # Even if configured, check docker permissions
        fix_docker_permissions
        return 0
    fi
    
    log "INFO" "WSL environment detected, configuring for optimal performance..." "docker"
    
    # Get Windows home directory path
    local windows_home=$(wslpath "$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')")
    local wslconfig="${windows_home}/.wslconfig"
    
    # Create optimized .wslconfig content
    local wslconfig_content=$(cat << 'EOF'
[wsl2]
# Memory allocation
memory=8GB
# CPU allocation
processors=4
# Enable better GPU support
gpuSupport=true
# Enable experimental features
nestedVirtualization=true
# Network settings
dnsTunneling=true
firewall=true
# Set swap storage
swap=4GB
# Set VM disk compression
diskCompression=zstd
EOF
)
    
    # Check if .wslconfig already exists
    if [[ -f "$wslconfig" ]]; then
        log "WARN" "Existing .wslconfig found at $windows_home"
        log "INFO" "DevEnv can create an optimized .wslconfig for better performance"
        
        # Ask user for permission to overwrite
        read -p "Would you like to overwrite the existing .wslconfig with optimized settings? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log "INFO" "Keeping existing .wslconfig"
        else
            log "INFO" "Overwriting .wslconfig with optimized settings..."
            echo "$wslconfig_content" > "$wslconfig"
            log "INFO" "Created optimized .wslconfig file at $wslconfig"
        fi
    else
        # No existing file, create a new one
        log "INFO" "Creating optimized .wslconfig in Windows home directory..."
        echo "$wslconfig_content" > "$wslconfig"
        log "INFO" "Created optimized .wslconfig file at $wslconfig"
    fi
    
    # Fix Docker permissions
    fix_docker_permissions
    
    # Configure systemd if not already enabled
    if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
        log "INFO" "WSL distribution would benefit from systemd support."
        read -p "Would you like to enable systemd in WSL? (requires sudo, y/n): " confirm
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            log "INFO" "Configuring systemd support in WSL..."
            
            sudo tee /etc/wsl.conf > /dev/null << EOF
[boot]
systemd=true

[automount]
enabled=true
options=metadata,uid=1000,gid=1000,umask=022

[network]
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=true
EOF
            
            log "WARN" "WSL configured with systemd support. You must restart WSL for changes to take effect."
            log "INFO" "Run 'wsl.exe --shutdown' from PowerShell to restart WSL."
            request_wsl_restart
        fi
    fi
    
    # Mark WSL as configured
    mkdir -p "$(dirname "$wsl_state_file")"
    echo "WSL configured on $(date)" > "$wsl_state_file"
    log "INFO" "WSL configuration complete and marked as configured"

    return 0
}

# Install core Docker
install_docker_core() {
    # Check for restart needed first
    if is_wsl && is_restart_needed; then
        log "WARN" "Docker configuration is incomplete because WSL restart is needed" "docker"
        request_wsl_restart
        return 1
    fi
    
    if ! command -v docker &>/dev/null; then
        log "INFO" "Installing Docker..." "docker"

        if is_wsl; then
            log "INFO" "WSL detected, configuring Docker..." "docker"
            setup_wsl_environment "$2"  # Pass force flag if present
            
            # For WSL, we install Docker CLI only since we'll use Docker Desktop
            sudo apt-get update
            sudo apt-get install -y docker.io docker-compose
            
            # Create daemon configuration for Docker Desktop socket
            sudo mkdir -p /etc/docker
            echo "{\"hosts\": [\"unix://$(get_docker_socket_path)\"]}" | sudo tee /etc/docker/daemon.json
            
            log "INFO" "Docker CLI installed for WSL" "docker"
            log "INFO" "Please ensure Docker Desktop for Windows is running with WSL integration enabled" "docker"
        else
            # Get and execute the installation command
            if command -v apt-get &>/dev/null; then
                # Debian/Ubuntu
                log "INFO" "Installing Docker with apt..." "docker"
                sudo apt-get update
                sudo apt-get install -y docker.io docker-compose
            elif command -v dnf &>/dev/null; then
                # Fedora/RHEL
                log "INFO" "Installing Docker with dnf..." "docker"
                sudo dnf -y install docker docker-compose
            elif command -v yum &>/dev/null; then
                # Older RHEL/CentOS
                log "INFO" "Installing Docker with yum..." "docker"
                sudo yum -y install docker docker-compose
            else
                # Unknown platform, use official install script
                log "INFO" "Using Docker's official install script..." "docker"
                curl -fsSL https://get.docker.com | sudo sh
            fi
        fi
    else
        # Docker is already installed, but we should still run WSL setup for permissions
        if is_wsl; then
            log "INFO" "Docker already installed, configuring WSL environment..." "docker"
            setup_wsl_environment "$2"  # Pass force flag if present
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
        # For WSL, ensure socket path is correctly set
        local docker_socket=$(get_docker_socket_path)
        log "INFO" "Configuring Docker daemon for WSL using socket: $docker_socket" "docker"
        
        sudo mkdir -p /etc/docker
        echo "{\"hosts\": [\"unix://$docker_socket\"]}" | sudo tee /etc/docker/daemon.json
        
        # Special check for Docker Desktop integration
        log "INFO" "Checking Docker Desktop WSL integration..." "docker"
        if ! timeout 5 docker info &>/dev/null; then
            log "WARN" "Docker Desktop doesn't appear to be running or WSL integration might not be enabled" "docker"
            log "INFO" "Please check that Docker Desktop is running and has WSL integration enabled for this distribution" "docker"
        else
            log "INFO" "Docker Desktop WSL integration is active" "docker"
        fi
        
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

    local container_dir="$HOME/.devenv/containers"
    local bin_dir="$HOME/.devenv/bin"
    local module_bin_dir="${DEVENV_ROOT}/modules/docker/bin"

    # Create directories
    mkdir -p "$container_dir" "$bin_dir"
        
    # Create a wrapper script for devenv-container
    if [[ -f "${module_bin_dir}/devenv-container" ]]; then
        # Create a wrapper script instead of a symlink
        cat > "$bin_dir/devenv-container" << EOF
#!/bin/bash
# Wrapper for devenv-container
bash "${module_bin_dir}/devenv-container" "\$@"
EOF
        chmod +x "$bin_dir/devenv-container"
                
        # Verify script is executable
        if [[ -x "$bin_dir/devenv-container" ]]; then
            log "INFO" "Successfully created wrapper for devenv-container" "docker"
        else
            log "ERROR" "Failed to create executable wrapper" "docker"
        fi
    else
        log "ERROR" "devenv-container source not found" "docker"
    fi
    
    # Add to PATH if not already there
    if ! grep -q "$bin_dir" "$HOME/.bashrc"; then
        echo 'export PATH="$PATH:'"${bin_dir}"'"' >> "$HOME/.bashrc"
    fi
    
    # If ZSH exists, add to ZSH also
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "$bin_dir" "$HOME/.zshrc"; then
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
            if install_docker_core "$@"; then
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
                timeout 5 docker info &>/dev/null
            else
                # For native Linux, check if daemon.json exists
                [[ -f "/etc/docker/daemon.json" ]]
            fi
            ;;
        "service")
            # For WSL, we check if Docker Desktop works
            if is_wsl; then
                timeout 5 docker info &>/dev/null
            else
                # For native Linux, check if service is running
                if command -v systemctl &>/dev/null; then
                    systemctl is-active --quiet docker
                else
                    timeout 5 docker info &>/dev/null
                fi
            fi
            ;;
        "compose")
            command -v docker-compose &>/dev/null || docker compose version &>/dev/null
            ;;
        "devenv")
            # Check if container management script exists and is executable
            [[ -x "$HOME/.devenv/bin/devenv-container" ]] && 
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
    
    # Special check for WSL restart
    if is_wsl && is_restart_needed; then
        log "WARN" "WSL restart needed to complete Docker configuration" "docker"
        status=1
    fi
    
    return $status
}

# Install with state awareness
install_docker() {
    local force=${1:-false}
    
    # Check for restart needed first
    if is_wsl && is_restart_needed; then
        log "WARN" "Docker configuration incomplete - WSL restart required" "docker"
        request_wsl_restart
        return 1
    fi
    
    if [[ "$force" == "true" ]] || ! grovel_docker &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "docker"
            if ! install_component "$component" "$force"; then
                log "ERROR" "Failed to install component: $component" "docker"
                
                # Special handling for WSL installs
                if is_wsl && is_restart_needed; then
                    log "WARN" "Docker installation incomplete - WSL restart required" "docker"
                    request_wsl_restart
                fi
                
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "docker"
        fi
    done
    
    # Additional step to verify WSL integration is working
    if is_wsl && ! verify_docker_wsl_integration; then
        log "WARN" "Docker installed but WSL integration is not working properly" "docker"
        log "INFO" "Trying to fix Docker permissions..." "docker"
        fix_docker_permissions
        
        if is_restart_needed; then
            log "WARN" "Docker configuration incomplete - WSL restart required" "docker"
            request_wsl_restart
            return 1
        fi
    fi
    
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
        for container in $(docker ps -a --format '{{.Names}}' | grep "^devenv-" 2>/dev/null || echo ""); do
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
        done
    fi

    # Remove DevEnv container management script
    rm -f "$HOME/.devenv/bin/devenv-container"

    # Remove aliases
    remove_module_aliases "docker" "basic"
    remove_module_aliases "docker" "container"
    remove_module_aliases "docker" "cleanup"

    # Remove state files
    rm -f "$STATE_FILE"
    rm -f "$WSL_CONFIG_STATE"

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
    
    # Special verification for WSL integration
    if is_wsl && ! verify_docker_wsl_integration; then
        log "WARN" "Docker installed but WSL integration check failed" "docker"
        log "INFO" "This may require a WSL restart to complete setup" "docker"
        status=1
    fi
    
    if [ $status -eq 0 ]; then
        log "INFO" "Docker verification completed successfully" "docker"
        
        # Test Docker functionality with timeout to prevent hanging
        log "INFO" "Testing Docker functionality..." "docker"
        if timeout 20 docker run --rm hello-world 2>/dev/null | grep -q "Hello from Docker!"; then
            log "INFO" "Docker is functioning correctly" "docker"
        else
            log "WARN" "Docker hello-world test failed" "docker"
            
            if is_wsl; then
                log "WARN" "This may be due to Docker Desktop not running or WSL integration being disabled" "docker"
                log "INFO" "Please verify that Docker Desktop is running and WSL integration is enabled" "docker"
            fi
            
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