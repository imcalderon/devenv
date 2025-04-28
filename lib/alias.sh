#!/bin/bash
# lib/utils/alias.sh - Alias management utilities

# Get the aliases directory path
get_aliases_dir() {
    local zsh_config="$MODULES_DIR/zsh/config.json"
    if [[ ! -f "$zsh_config" ]]; then
        log "ERROR" "ZSH module configuration not found" "alias"
        return 1
    fi

    # First try to get from config
    local modules_dir=$(get_json_value "$zsh_config" ".shell.paths.modules_dir" "")
    
    # Check if value is null or empty
    if [[ -z "$modules_dir" || "$modules_dir" == "null" ]]; then
        # Fallback to default location
        modules_dir="$HOME/.config/zsh/modules"
        log "WARN" "ZSH modules_dir not found in config, using default: $modules_dir" "alias"
    fi
    
    # Expand env variables
    modules_dir=$(eval echo "$modules_dir")
    
    # Create directory if it doesn't exist
    mkdir -p "$modules_dir"
    
    echo "$modules_dir"
}

# Add aliases for a module
add_module_aliases() {
    local module=$1
    local category=${2:-}
    
    # Get the aliases directory
    local aliases_dir=$(get_aliases_dir) || return 1
    local aliases_file="$aliases_dir/aliases.zsh"
    
    # Ensure the aliases directory exists
    mkdir -p "$aliases_dir"
    
    # Create aliases file if it doesn't exist
    touch "$aliases_file"
    
    # Remove existing aliases for this module/category if they exist
    local marker_start="# BEGIN ${module}${category:+_$category} aliases"
    local marker_end="# END ${module}${category:+_$category} aliases"
    
    # Use a temporary file for sed operations
    local temp_file=$(mktemp)
    sed "/^${marker_start}/,/^${marker_end}/d" "$aliases_file" > "$temp_file"
    cat "$temp_file" > "$aliases_file"
    rm -f "$temp_file"
    
    # Get aliases from module config
    local query=".shell.aliases"
    [[ -n "$category" ]] && query="$query.$category"
    
    local aliases=($(get_module_config "$module" "$query | keys[]" || echo ""))
    if [[ ${#aliases[@]} -gt 0 ]]; then
        {
            echo "$marker_start"
            for alias_name in "${aliases[@]}"; do
                local cmd=$(get_module_config "$module" "$query[\"$alias_name\"]")
                echo "alias $alias_name='$cmd'"
            done
            echo "$marker_end"
            echo "" # Add newline after block
        } >> "$aliases_file"
        
        log "INFO" "Added aliases for $module${category:+ ($category)}" "alias"
        return 0
    fi
    
    return 0
}

# Remove aliases for a module
remove_module_aliases() {
    local module=$1
    local category=${2:-}
    
    local aliases_dir=$(get_aliases_dir) || return 1
    local aliases_file="$aliases_dir/aliases.zsh"
    
    if [[ -f "$aliases_file" ]]; then
        local marker_start="# BEGIN ${module}${category:+_$category} aliases"
        local marker_end="# END ${module}${category:+_$category} aliases"
        sed -i "/^${marker_start}/,/^${marker_end}/d" "$aliases_file"
        
        log "INFO" "Removed aliases for $module${category:+ ($category)}" "alias"
    fi
    
    return 0
}

# List all aliases for a module
list_module_aliases() {
    local module=$1
    local category=${2:-}
    
    local aliases_dir=$(get_aliases_dir) || return 1
    local aliases_file="$aliases_dir/aliases.zsh"
    
    if [[ -f "$aliases_file" ]]; then
        local marker_start="# BEGIN ${module}${category:+_$category} aliases"
        local marker_end="# END ${module}${category:+_$category} aliases"
        sed -n "/^${marker_start}/,/^${marker_end}/p" "$aliases_file"
    fi
    
    return 0
}
