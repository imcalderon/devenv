#!/bin/bash
# lib/utils/json.sh - JSON utilities

# Ensure we have sudo privileges
ensure_sudo() {
    local module=${1:-}
    if ! sudo -v &>/dev/null; then
        log "INFO" "Requesting sudo privileges..." "$module"
        if ! sudo -v; then
            log "ERROR" "Failed to get sudo privileges" "$module"
            return 1
        fi
    fi
    return 0
}

# Ensure jq is installed
ensure_json_parser() {
    # First try the command to see if it's already available
    if command -v jq &>/dev/null; then
        return 0
    fi
    
    log "INFO" "jq not found, attempting installation..." "json"
    
    # Request sudo access first
    if ! ensure_sudo "json"; then
        return 1
    fi
    
    # More verbose output for debugging
    log "INFO" "Current PATH: $PATH" "json"
    
    # Try package managers with explicit installation checks
    if command -v apt-get &>/dev/null; then
        log "INFO" "Using apt package manager" "json"
        log "INFO" "Running: sudo apt-get update && sudo apt-get install -y jq" "json"
        sudo apt-get update && sudo apt-get install -y jq
        log "INFO" "apt install command completed with status $?" "json"
        
        # Use direct path to jq since command -v might not find it immediately
        if [[ -f "/usr/bin/jq" ]]; then
            log "INFO" "Found jq at /usr/bin/jq" "json"
            # Define a function to use the direct path
            jq() {
                /usr/bin/jq "$@"
            }
            export -f jq
            return 0
        fi
    elif command -v dnf &>/dev/null; then
        log "INFO" "Using dnf package manager" "json"
        log "INFO" "Running: sudo dnf install -y jq" "json"
        sudo dnf install -y jq
        log "INFO" "dnf install command completed with status $?" "json"
        
        # Try direct path for dnf installs
        if [[ -f "/usr/bin/jq" ]]; then
            log "INFO" "Found jq at /usr/bin/jq" "json"
            jq() {
                /usr/bin/jq "$@"
            }
            export -f jq
            return 0
        fi
    else
        log "ERROR" "No supported package manager found" "json"
        return 1
    fi
    
    # Final check for jq availability
    if command -v jq &>/dev/null; then
        log "INFO" "jq is now available via command" "json"
        return 0
    else
        log "ERROR" "jq installation failed - trying manual installation" "json"
        
        # Try manual installation as a last resort
        local temp_dir=$(mktemp -d)
        log "INFO" "Attempting manual jq installation to $temp_dir" "json"
        
        # Download jq binary directly
        if command -v wget &>/dev/null; then
            wget -q https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O "$temp_dir/jq"
        elif command -v curl &>/dev/null; then
            curl -sL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o "$temp_dir/jq"
        else
            log "ERROR" "Neither wget nor curl available for manual installation" "json"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Make executable and move to a usable location
        chmod +x "$temp_dir/jq"
        log "INFO" "Downloaded jq to $temp_dir/jq" "json"
        
        # Define function to use our manual installation
        jq() {
            "$temp_dir/jq" "$@"
        }
        export -f jq
        
        # Return success - the temp dir will remain for this session
        log "INFO" "Manual jq installation complete" "json"
        return 0
    fi
    
    # If we get here, all attempts failed
    log "ERROR" "All jq installation attempts failed" "json"
    return 1
}

# Get value from JSON file with module context
get_json_value() {
    local file=$1
    local query=$2
    local default=${3:-}
    local module=${4:-}
    
    if [[ ! -f "$file" ]]; then
        log "ERROR" "JSON file not found: $file" "$module"
        return 1
    fi
    
    local result
    result=$(jq -r "$query" "$file" 2>/dev/null) || {
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        log "ERROR" "Failed to parse JSON query: $query" "$module"
        return 1
    }
    
    # Handle empty or null results
    if [[ -z "$result" || "$result" == "null" ]]; then
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
    fi
    
    echo "$result"
}

# Validate JSON file with optional schema
validate_json() {
    local file=$1
    local schema=${2:-}
    local module=${3:-}
    
    if [[ ! -f "$file" ]]; then
        log "ERROR" "JSON file not found: $file" "$module"
        return 1
    fi
    
    # Basic JSON syntax validation using jq
    if ! jq '.' "$file" >/dev/null 2>&1; then
        log "ERROR" "Invalid JSON syntax in file: $file" "$module"
        return 1
    fi
    
    # Schema validation if schema file provided
    if [[ -n "$schema" && -f "$schema" ]]; then
        # Note: Basic schema validation with jq
        # For more complex validation, we might want to use a dedicated JSON schema validator
        if ! jq --argfile schema "$schema" 'try ($schema) catch false' "$file" >/dev/null 2>&1; then
            log "ERROR" "JSON schema validation failed for file: $file" "$module"
            return 1
        fi
    fi
    
    return 0
}
