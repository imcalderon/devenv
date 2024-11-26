#!/bin/bash
# lib/utils/module.sh - Module utilities

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

# Initialize module
init_module() {
    local module=$1
    
    # Verify module first
    if ! verify_module "$module"; then
        return 1
    fi
    
    # Initialize module-specific logging
    init_logging "$module"
    
    # Export module context variables
    export MODULE_NAME="$module"
    export MODULE_DIR="$MODULES_DIR/$module"
    export MODULE_CONFIG="$MODULE_DIR/config.json"
    
    return 0
}
