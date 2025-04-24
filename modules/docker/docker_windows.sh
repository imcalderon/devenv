#!/bin/bash
# docker_windows.sh - Windows-specific additions to the Docker module

# Add these functions to the existing docker.sh module implementation

# Function to detect WSL environment
is_wsl() {
    grep -q "microsoft" /proc/version 2>/dev/null
    return $?
}

# Function to set up Docker Desktop integration
setup_docker_desktop() {
    log "INFO" "Setting up Docker Desktop integration..." "docker"
    
    # Check if WSL integration is enabled in config
    local wsl_integration=$(get_module_config "docker" ".docker.windows.wsl_integration")
    if [[ "$wsl_integration" != "true" ]]; then
        log "INFO" "WSL integration not enabled in config" "docker"
        return 0
    fi
    
    # Create Windows scripts directory
    local scripts_dir=$(get_module_config "docker" ".shell.paths.windows_scripts_dir")
    scripts_dir=$(eval echo "$scripts_dir")
    mkdir -p "$scripts_dir"
    
    # Copy Docker WSL helper script
    cp "$MODULE_DIR/docker_wsl.sh" "$scripts_dir/"
    chmod +x "$scripts_dir/docker_wsl.sh"
    
    # Check if Docker Desktop is installed
    local docker_desktop=$(get_module_config "docker" ".shell.paths.docker_desktop")
    docker_desktop=$(eval echo "$docker_desktop")
    
    if powershell.exe "Test-Path '$docker_desktop'" | grep -q "True"; then
        log "INFO" "Docker Desktop found at $docker_desktop" "docker"
        
        # Run the Docker WSL helper script to set up Docker
        local setup_script="$scripts_dir/docker_wsl.sh"
        if [[ -x "$setup_script" ]]; then
            "$setup_script" setup
        else
            log "ERROR" "Docker WSL helper script not found or not executable" "docker"
            return 1
        fi
    else
        log "WARN" "Docker Desktop not found at $docker_desktop" "docker"
        log "INFO" "Please install Docker Desktop for Windows first" "docker"
        
        # Open Docker Desktop download page
        powershell.exe "Start-Process 'https://www.docker.com/products/docker-desktop/'"
        return 1
    fi
    
    # Add Windows-specific aliases
    add_module_aliases "docker" "windows" || return 1
    
    return 0
}

# Install Docker CLI only for WSL
install_docker_cli_wsl() {
    log "INFO" "Installing Docker CLI for WSL..." "docker"
    
    # Update package lists
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the stable repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker CLI
    sudo apt-get update
    sudo apt-get install -y docker-ce-cli
    
    # Set up Docker configuration directory
    local config_dir=$(get_module_config "docker" ".shell.paths.config_dir")
    local user_config=$(get_module_config "docker" ".shell.paths.user_config")
    
    config_dir=$(eval echo "$config_dir")
    user_config=$(eval echo "$user_config")
    
    # Create Docker configuration directory
    mkdir -p "$(dirname "$user_config")"
    
    # Configure Docker to use desktop.exe credential store
    cat > "$user_config" << EOF
{
  "credsStore": "desktop.exe"
}
EOF
    
    log "INFO" "Docker CLI installed successfully" "docker"
    return 0
}

# Override install_docker_package for WSL environments
install_docker_package_wsl() {
    # Check if we're running in WSL
    if is_wsl; then
        log "INFO" "Running in WSL, using Docker Desktop integration..." "docker"
        
        # Check if we should use Docker Desktop
        local use_docker_desktop=$(get_module_config "docker" ".docker.windows.use_docker_desktop")
        if [[ "$use_docker_desktop" == "true" ]]; then
            # Install Docker CLI only, not the daemon
            install_docker_cli_wsl || return 1
            
            # Set up Docker Desktop integration
            setup_docker_desktop || return 1
        else
            # Fall back to normal installation if not using Docker Desktop
            install_docker_package || return 1
        fi
    else
        # Not in WSL, use normal installation
        install_docker_package || return 1
    fi
    
    return 0
}

# Override the original install_component function for the "core" component
install_component_override() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "docker"
        return 0
    fi
    
    case "$component" in
        "core")
            # Use WSL-specific installation if in WSL environment
            if is_wsl && [[ "$(get_module_config "docker" ".docker.windows.use_docker_desktop")" == "true" ]]; then
                if install_docker_package_wsl; then
                    save_state "core" "installed"
                    return 0
                fi
            else
                # Otherwise use the original function
                if install_docker_package; then
                    save_state "core" "installed"
                    return 0
                fi
            fi
            ;;
        # Other components remain the same
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

# Override the original verify_component function for WSL environments
verify_component_override() {
    local component=$1
    
    # For WSL environments with Docker Desktop integration
    if is_wsl && [[ "$(get_module_config "docker" ".docker.windows.use_docker_desktop")" == "true" ]]; then
        case "$component" in
            "core")
                command -v docker &>/dev/null
                ;;
            "daemon")
                # Skip daemon verification in WSL with Docker Desktop
                return 0
                ;;
            "service")
                # Check Docker connection instead of service
                docker info &>/dev/null
                ;;
            "groups")
                # Skip group verification in WSL with Docker Desktop
                return 0
                ;;
            "helpers")
                verify_helpers
                ;;
            *)
                return 1
                ;;
        esac
        return $?
    else
        # Use original verification for non-WSL environments
        case "$component" in
            "core")
                command -v docker &>/dev/null
                ;;
            "daemon")
                [[ -f "/etc/docker/daemon.json" ]] && validate_json "/etc/docker/daemon.json"
                ;;
            "service")
                systemctl is-active --quiet docker
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
    fi
}

# Function to apply WSL overrides
apply_wsl_overrides() {
    # Only apply overrides if running in WSL and using Docker Desktop
    if is_wsl && [[ "$(get_module_config "docker" ".docker.windows.use_docker_desktop")" == "true" ]]; then
        log "INFO" "Applying WSL overrides for Docker module..." "docker"
        
        # Override install_component function
        install_component() {
            install_component_override "$@"
        }
        
        # Override verify_component function
        verify_component() {
            verify_component_override "$@"
        }
    fi
}

# Call this function at the beginning of the module
apply_wsl_overrides