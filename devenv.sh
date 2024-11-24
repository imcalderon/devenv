#!/bin/bash
# devenv.sh - Main entry point for development environment setup

set -euo pipefail

# Get absolute paths
export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR="$ROOT_DIR/lib"

# Load utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/yaml_parser.sh"
source "$SCRIPT_DIR/module_base.sh"

# Constants
CONFIG_FILE="$ROOT_DIR/config.yaml"
BACKUP_DIR="$HOME/.devenv/backups/$(date +%Y%m%d_%H%M%S)"

# Get ordered list of enabled modules
get_ordered_modules() {
    local -a modules=()
    eval $(parse_yaml "$CONFIG_FILE" "config_")
    
    # Get all enabled modules with their runlevels
    declare -A module_levels=()
    while IFS= read -r module; do
        if [[ -n "$module" ]]; then
            # Strip any comments and whitespace
            module=$(echo "$module" | sed 's/#.*$//' | tr -d '[:space:]')
            if [[ -n "$module" ]]; then
                local runlevel=$(get_module_runlevel "$module")
                module_levels["$module"]=$runlevel
            fi
        fi
    done < <(get_enabled_modules "$CONFIG_FILE")
    
    # Sort modules by runlevel
    for module in "${!module_levels[@]}"; do
        modules+=("${module_levels[$module]} $module")
    done
    
    # Sort numerically and extract just the module names
    if [ ${#modules[@]} -gt 0 ]; then
        printf '%s\n' "${modules[@]}" | sort -n | cut -d' ' -f2-
    fi
}

# Execute a stage for all enabled modules
execute_stage() {
    local stage=$1
    local -a modules
    
    # Read the ordered modules into an array
    readarray -t modules < <(get_ordered_modules)
    
    if [ ${#modules[@]} -eq 0 ]; then
        log "WARN" "No enabled modules found in config"
        return 0
    fi
    
    log "INFO" "Executing stage: $stage"
    local exit_code=0
    
    for module in "${modules[@]}"; do
        # Skip empty module names
        if [[ -z "$module" ]]; then
            continue
        fi
        
        local module_script="$SCRIPT_DIR/$module/$module.sh"
        if [[ -f "$module_script" ]]; then
            log "INFO" "Running $stage for module: $module"
            
            if [[ "$stage" == "grovel" ]]; then
                # For grovel stage, we want to continue even if it fails
                if ! bash "$module_script" "$stage"; then
                    log "WARN" "Module $module needs installation"
                fi
            else
                # For other stages, we want to track failures but continue
                if ! bash "$module_script" "$stage"; then
                    log "ERROR" "Stage $stage failed for module: $module"
                    exit_code=1
                fi
            fi
        else
            log "ERROR" "Module script not found: $module_script"
            if [[ "$stage" != "grovel" ]]; then
                exit_code=1
            fi
        fi
    done
    
    return $exit_code
}

# Create backup
create_backup() {
    mkdir -p "$BACKUP_DIR"
    if [[ -f "$HOME/.zshrc" ]]; then
        cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc.backup"
    fi
    log "INFO" "Created backup at: $BACKUP_DIR"
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {install|remove|verify|backup|restore}"
        exit 1
    fi
    
    local action=$1
    
    case "$action" in
        install)
            create_backup
            execute_stage "grovel"
            execute_stage "install"
            execute_stage "verify"
            ;;
        remove)
            execute_stage "remove"
            ;;
        verify)
            execute_stage "verify"
            ;;
        backup)
            execute_stage "backup"
            ;;
        restore)
            shift
            execute_stage "restore" "$@"
            ;;
        *)
            log "ERROR" "Unknown action: $action"
            log "ERROR" "Usage: $0 {install|remove|verify|backup|restore}"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi