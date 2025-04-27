#!/bin/bash
# lib/utils/module.sh - Module utilities with containerization support

# Get module configuration
get_module_config() {
    local module=$1
    local key=$2
    local default=${3:-}
    
    local config_file="$MODULES_DIR/$module/config.json"
    get_json_value "$config_file" "$key" "$default" "$module"
}

# Check if module is enabled
is_module_enabled() {
    local module=$1
    local enabled=$(get_module_config "$module" ".enabled" "false")
    [[ "$enabled" == "true" ]]
}

# Get module runlevel
get_module_runlevel() {
    local module=$1
    get_module_config "$module" ".runlevel" "999"
}

# Get module dependencies
get_module_dependencies() {
    local module=$1
    get_module_config "$module" ".dependencies[]" "" | sort -u
}

# Check if a module should be containerized
should_containerize() {
    local module=$1
    
    # First check global container enablement
    local container_enabled=$(get_json_value "$CONFIG_FILE" ".global.container.enabled" "false")
    if [[ "$container_enabled" != "true" ]]; then
        return 1
    fi
    
    # Then check module-specific containerization
    local containerize=$(get_json_value "$CONFIG_FILE" ".global.container.modules.$module.containerize" "false")
    [[ "$containerize" == "true" ]]
}

# Get module container image
get_module_container_image() {
    local module=$1
    get_json_value "$CONFIG_FILE" ".global.container.modules.$module.image" ""
}

# Get extra container mount options
get_module_container_mounts() {
    local module=$1
    
    # Get global mount paths
    local mounts=""
    local mount_paths=$(get_json_value "$CONFIG_FILE" ".global.container.mount_paths | keys[]")
    
    for mount_key in $mount_paths; do
        local mount_value=$(get_json_value "$CONFIG_FILE" ".global.container.mount_paths[\"$mount_key\"]")
        
        # Expand environment variables
        mount_value=$(eval echo "$mount_value")
        
        # Add to mounts string
        mounts="$mounts -v $mount_value"
    done
    
    # Get module-specific extra mounts
    local extra_mounts=$(get_json_value "$CONFIG_FILE" ".global.container.modules.$module.extra_mounts[]" "")
    
    for mount in $extra_mounts; do
        # Expand environment variables
        mount=$(eval echo "$mount")
        
        # Add to mounts string
        mounts="$mounts -v $mount"
    done
    
    echo "$mounts"
}

# Get extra container arguments
get_module_container_args() {
    local module=$1
    get_json_value "$CONFIG_FILE" ".global.container.modules.$module.extra_args" ""
}

# Get container network
get_container_network() {
    get_json_value "$CONFIG_FILE" ".global.container.network" "bridge"
}

# Check if running in WSL
is_wsl() {
    grep -q "microsoft" /proc/version 2>/dev/null
    return $?
}

# Get Docker socket path
get_docker_socket() {
    if is_wsl; then
        # Check configuration first
        local socket_path
        if [[ "$PLATFORM" == "windows" ]]; then
            socket_path=$(get_json_value "$CONFIG_FILE" ".platforms.windows.wsl.docker_socket" "")
        else
            socket_path=$(get_json_value "$CONFIG_FILE" ".platforms.linux.wsl.docker_socket" "")
        fi
        
        # Fall back to default sockets
        if [[ -z "$socket_path" ]]; then
            if [[ -e "/var/run/docker-desktop.sock" ]]; then
                socket_path="/var/run/docker-desktop.sock"
            else
                socket_path="/var/run/docker.sock"
            fi
        fi
        
        echo "$socket_path"
    else
        # Standard docker socket
        echo "/var/run/docker.sock"
    fi
}

# Run a module command in container
run_module_in_container() {
    local module=$1
    local action=$2
    shift 2  # Remove first two arguments
    
    local image=$(get_module_container_image "$module")
    if [[ -z "$image" ]]; then
        log "ERROR" "No container image specified for module $module" "$module"
        return 1
    fi
    
    # Get container mount options
    local mounts=$(get_module_container_mounts "$module")
    
    # Get extra container arguments
    local extra_args=$(get_module_container_args "$module")
    
    # Get container network
    local network=$(get_container_network)
    
    # Get Docker socket path for volume mounting
    local docker_socket=$(get_docker_socket)
    
    # Mount the module directory and scripts
    local module_mount="-v $MODULES_DIR/$module:/devenv/modules/$module"
    local lib_mount="-v $SCRIPT_DIR:/devenv/lib"
    
    # Create a temporary script to execute inside the container
    local temp_script=$(mktemp)
    
    cat > "$temp_script" << EOF
#!/bin/bash
export SCRIPT_DIR="/devenv/lib"
export MODULE_NAME="$module"
export MODULE_DIR="/devenv/modules/$module"
export MODULE_CONFIG="/devenv/modules/$module/config.json"
export CONFIG_FILE="/devenv/config.json"
export DEVENV_ROOT="/devenv"
export DEVENV_DATA_DIR="/devenv/data"
export PATH="/devenv/bin:\$PATH"
cd /devenv
/devenv/modules/$module/$module.sh $action "\$@"
EOF
    
    chmod +x "$temp_script"
    
    # Define the docker run command
    local docker_run="docker run --rm -it \
        $mounts \
        $module_mount \
        $lib_mount \
        -v $CONFIG_FILE:/devenv/config.json \
        -v $temp_script:/tmp/run_module.sh \
        -v $docker_socket:/var/run/docker.sock \
        --network=$network \
        $extra_args \
        $image \
        /tmp/run_module.sh $@"
    
    # Log the docker command
    log "DEBUG" "Running docker command: $docker_run" "$module"
    
    # Execute the docker command
    eval "$docker_run"
    local exit_code=$?
    
    # Clean up
    rm -f "$temp_script"
    
    return $exit_code
}

# Verify module configuration
verify_module() {
    local module=$1
    local config_file="$MODULES_DIR/$module/config.json"
    
    # Check for required files
    if [[ ! -f "$config_file" ]]; then
        log "ERROR" "Module configuration not found" "$module"
        return 1
    fi
    
    if [[ ! -f "$MODULES_DIR/$module/$module.sh" ]]; then
        log "ERROR" "Module script not found" "$module"
        return 1
    fi
    
    # Validate JSON configuration
    if ! validate_json "$config_file" "" "$module"; then
        return 1
    fi
    
    return 0
}

# Execute a module script
execute_module() {
    local module=$1
    local action=$2
    shift 2  # Remove first two arguments
    
    # Check if module should be containerized
    if should_containerize "$module"; then
        log "INFO" "Running module $module in container" "$module"
        run_module_in_container "$module" "$action" "$@"
    else
        log "INFO" "Running module $module natively" "$module"
        "$MODULES_DIR/$module/$module.sh" "$action" "$@"
    fi
}

# Initialize module
init_module() {
    local module=$1
    
    # Save current LOG_LEVEL
    local current_log_level="${LOG_LEVEL:-INFO}"
    
    # Verify module first
    if ! verify_module "$module"; then
        return 1
    fi
    
    # Initialize module-specific logging with preserved log level
    LOG_LEVEL="$current_log_level" init_logging "$module"
    
    # Export module context variables
    export MODULE_NAME="$module"
    export MODULE_DIR="$MODULES_DIR/$module"
    export MODULE_CONFIG="$MODULE_DIR/config.json"
    
    return 0
}