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
    if ! command -v jq &>/dev/null; then
        log "INFO" "Installing jq..." "json"
        
        # Request sudo access first
        if ! ensure_sudo "json"; then
            return 1
        fi
        
        # Try package managers
        if command -v dnf &>/dev/null; then
            log "INFO" "Installing jq via dnf..." "json"
            if ! sudo dnf install -y jq; then
                log "ERROR" "Failed to install jq via dnf" "json"
                return 1
            fi
        elif command -v apt-get &>/dev/null; then
            log "INFO" "Installing jq via apt..." "json"
            if ! sudo apt-get update && sudo apt-get install -y jq; then
                log "ERROR" "Failed to install jq via apt" "json"
                return 1
            fi
        else
            log "ERROR" "No supported package manager found" "json"
            return 1
        fi
        
        # Verify installation
        if ! command -v jq &>/dev/null; then
            log "ERROR" "jq installation verification failed" "json"
            return 1
        fi
    fi
    return 0
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
