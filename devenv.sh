#!/bin/bash
# devenv.sh - Development environment setup with JSON configuration

set -euo pipefail

# Get absolute paths
export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR="$ROOT_DIR/lib"
export MODULES_DIR="$ROOT_DIR/modules"
export CONFIG_FILE="$ROOT_DIR/config.json"

# Load utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities

# Verify environment
verify_environment() {
    # Check for required directories
    for dir in "$SCRIPT_DIR" "$MODULES_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log "ERROR" "Required directory not found: $dir"
            return 1
        fi
    done
    
    # Check for global config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Global config not found: $CONFIG_FILE"
        return 1
    fi
    
    log "DEBUG" "About to validate config file: $CONFIG_FILE"
    log "DEBUG" "Current directory: $(pwd)"
    log "DEBUG" "Config file contents:"
    cat "$CONFIG_FILE" >&2
    
    # Ensure fq is available before validation
    if ! ensure_json_parser; then
        log "ERROR" "jq is not available"
        return 1
    fi
    
    # Test fq directly
    log "DEBUG" "Testing fq with config file..."
    if ! jq . "$CONFIG_FILE" 2>jq_error.log; then
        log "ERROR" "Direct fq test failed:"
        cat jq_error.log >&2
        rm jq_error.log
        return 1
    fi
    rm -f jq_error.log
    
    # Validate global config
    if ! validate_json "$CONFIG_FILE"; then
        log "ERROR" "Config validation failed"
        return 1
    fi
    
    return 0
}

# Get ordered list of enabled modules
get_ordered_modules() {
    local modules=($(get_json_value "$CONFIG_FILE" '.modules.order[]'))
    local enabled_modules=()
    
    for module in "${modules[@]}"; do
        if is_module_enabled "$module"; then
            enabled_modules+=("$module")
        fi
    done
    
    printf '%s\n' "${enabled_modules[@]}"
}

# Execute a stage for modules
execute_stage() {
    local stage=$1
    local specific_module=${2:-}
    local -a modules
    
    if [[ -n "$specific_module" ]]; then
        if ! verify_module "$specific_module"; then
            return 1
        fi
        modules=("$specific_module")
    else
        readarray -t modules < <(get_ordered_modules)
    fi
    
    if [[ ${#modules[@]} -eq 0 ]]; then
        log "WARN" "No enabled modules found"
        return 0
    fi
    
    log "INFO" "Executing stage: $stage"
    local exit_code=0
    
    for module in "${modules[@]}"; do
        # Initialize module context
        if ! init_module "$module"; then
            log "ERROR" "Failed to initialize module: $module"
            continue
        fi
        
        local module_script="$MODULES_DIR/$module/$module.sh"
        if [[ -f "$module_script" ]]; then
            log "INFO" "Running $stage for module: $module" "$module"
            
            if [[ "$stage" == "grovel" ]]; then
                bash "$module_script" "$stage" || {
                    log "WARN" "Module $module needs installation" "$module"
                    continue
                }
            else
                bash "$module_script" "$stage" || {
                    log "ERROR" "Stage $stage failed for module: $module" "$module"
                    exit_code=1
                }
            fi
        else
            log "ERROR" "Module script not found: $module_script" "$module"
            [[ "$stage" != "grovel" ]] && exit_code=1
        fi
    done
    
    return $exit_code
}

# Create backup of current environment
create_backup() {
    local specific_module=${1:-}
    local -a modules
    
    if [[ -n "$specific_module" ]]; then
        modules=("$specific_module")
    else
        readarray -t modules < <(get_ordered_modules)
    fi
    
    for module in "${modules[@]}"; do
        # Initialize module context
        if ! init_module "$module"; then
            log "ERROR" "Failed to initialize module: $module"
            continue
        fi
        
        log "INFO" "Creating backup for module: $module" "$module"
        
        # Get module-specific backup paths
        local paths=($(get_module_config "$module" '.backup.paths[]'))
        
        for path in "${paths[@]}"; do
            path=$(eval echo "$path")  # Expand environment variables
            if [[ -e "$path" ]]; then
                backup_file "$path" "$module"
            fi
        done
    done
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {install|remove|verify|backup|restore} [module_name]"
        exit 1
    fi
    
    # Verify environment first
    if ! verify_environment; then
        log "ERROR" "Environment verification failed"
        exit 1
    fi
    
    local action=$1
    local specific_module=${2:-}
    
    case "$action" in
        install)
            create_backup "$specific_module"
            if [[ -n "$specific_module" ]]; then
                execute_stage "grovel" "$specific_module" &&
                execute_stage "install" "$specific_module" &&
                execute_stage "verify" "$specific_module"
            else
                execute_stage "grovel" &&
                execute_stage "install" &&
                execute_stage "verify"
            fi
            ;;
        remove)
            execute_stage "remove" "$specific_module"
            ;;
        verify)
            execute_stage "verify" "$specific_module"
            ;;
        backup)
            create_backup "$specific_module"
            ;;
        restore)
            shift
            execute_stage "restore" "$@"
            ;;
        *)
            log "ERROR" "Unknown action: $action"
            log "ERROR" "Usage: $0 {install|remove|verify|backup|restore} [module_name]"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
