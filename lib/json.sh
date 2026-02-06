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

# Validate root config.json structure using jq
# Returns 0 on success, 1 on failure. Logs warnings for issues.
validate_root_config() {
    local file=${1:-$CONFIG_FILE}
    local module="json"
    local status=0

    if [[ ! -f "$file" ]]; then
        log "WARN" "Root config not found: $file" "$module"
        return 1
    fi

    # Check required top-level keys
    local required_keys=("version" "metadata" "global" "platforms")
    for key in "${required_keys[@]}"; do
        if ! jq -e "has(\"$key\")" "$file" >/dev/null 2>&1; then
            log "WARN" "Root config missing required key: $key" "$module"
            status=1
        fi
    done

    # Validate version is semver-like
    local version
    version=$(jq -r '.version // empty' "$file" 2>/dev/null)
    if [[ -n "$version" ]] && ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "WARN" "Root config version is not valid semver: $version" "$module"
        status=1
    fi

    # Validate platform keys are valid
    local platform_keys
    platform_keys=$(jq -r '.platforms | keys[]' "$file" 2>/dev/null)
    for key in $platform_keys; do
        case "$key" in
            windows|linux|darwin) ;;
            *)
                log "WARN" "Unknown platform key in config: $key" "$module"
                status=1
                ;;
        esac
    done

    # Validate each platform has required fields
    for platform in $platform_keys; do
        for field in script shell modules; do
            if ! jq -e ".platforms.\"$platform\" | has(\"$field\")" "$file" >/dev/null 2>&1; then
                log "WARN" "Platform '$platform' missing required field: $field" "$module"
                status=1
            fi
        done
    done

    # Validate global.paths has required path keys
    local required_paths=("data_dir" "logs_dir" "backups_dir" "state_dir" "modules_dir")
    for path_key in "${required_paths[@]}"; do
        if ! jq -e ".global.paths | has(\"$path_key\")" "$file" >/dev/null 2>&1; then
            log "WARN" "Root config global.paths missing required key: $path_key" "$module"
            status=1
        fi
    done

    # Verify modules referenced in platform orders actually exist as directories
    local modules_dir="${MODULES_DIR:-$(dirname "$file")/modules}"
    for platform in $platform_keys; do
        local modules
        modules=$(jq -r ".platforms.\"$platform\".modules.order[]?" "$file" 2>/dev/null)
        for mod in $modules; do
            if [[ ! -d "$modules_dir/$mod" ]]; then
                log "WARN" "Platform '$platform' references non-existent module: $mod" "$module"
                status=1
            fi
        done
    done

    return $status
}

# Validate module config.json structure using jq
# Usage: validate_module_config <config_file> [module_name]
validate_module_config() {
    local file=$1
    local mod_name=${2:-$(basename "$(dirname "$file")")}
    local module="json"
    local status=0

    if [[ ! -f "$file" ]]; then
        log "WARN" "Module config not found: $file" "$module"
        return 1
    fi

    # Check required fields
    if ! jq -e 'has("enabled")' "$file" >/dev/null 2>&1; then
        log "WARN" "Module '$mod_name' config missing required field: enabled" "$module"
        status=1
    else
        # Validate enabled is boolean
        local enabled_type
        enabled_type=$(jq -r '.enabled | type' "$file" 2>/dev/null)
        if [[ "$enabled_type" != "boolean" ]]; then
            log "WARN" "Module '$mod_name' config 'enabled' must be boolean, got: $enabled_type" "$module"
            status=1
        fi
    fi

    if ! jq -e 'has("runlevel")' "$file" >/dev/null 2>&1; then
        log "WARN" "Module '$mod_name' config missing required field: runlevel" "$module"
        status=1
    else
        # Validate runlevel is integer 0-99
        local runlevel
        runlevel=$(jq -r '.runlevel' "$file" 2>/dev/null)
        if ! [[ "$runlevel" =~ ^[0-9]+$ ]] || [[ "$runlevel" -gt 99 ]]; then
            log "WARN" "Module '$mod_name' config 'runlevel' must be integer 0-99, got: $runlevel" "$module"
            status=1
        fi
    fi

    # Validate dependencies reference existing modules if present
    local deps
    deps=$(jq -r '.dependencies[]?' "$file" 2>/dev/null)
    local modules_dir="${MODULES_DIR:-}"
    if [[ -n "$deps" && -n "$modules_dir" ]]; then
        for dep in $deps; do
            if [[ ! -d "$modules_dir/$dep" ]]; then
                log "WARN" "Module '$mod_name' depends on non-existent module: $dep" "$module"
                status=1
            fi
        done
    fi

    # Validate platform keys if present
    local plat_keys
    plat_keys=$(jq -r '.platforms | keys[]?' "$file" 2>/dev/null)
    for key in $plat_keys; do
        case "$key" in
            windows|linux|darwin) ;;
            *)
                log "WARN" "Module '$mod_name' has unknown platform key: $key" "$module"
                status=1
                ;;
        esac
    done

    return $status
}
