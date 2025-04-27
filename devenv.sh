#!/bin/bash
# devenv.sh - Development environment setup with cross-platform support

set -euo pipefail

# Get absolute paths
if [[ -z "${ROOT_DIR:-}" ]]; then
    export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "${CONFIG_FILE:-}" ]]; then
    export CONFIG_FILE="$ROOT_DIR/config.json"
fi

# Detect platform
detect_platform() {
    local platform="unknown"
    case "$(uname -s)" in
        Linux*)     platform="linux";;
        Darwin*)    platform="darwin";;
        *)          platform="unknown";;
    esac
    
    echo "$platform"
}

PLATFORM=$(detect_platform)

# Set platform-specific script directory
export SCRIPT_DIR="$ROOT_DIR/lib"
export MODULES_DIR="$ROOT_DIR/modules"
export STATE_DIR="$HOME/.devenv/state"

# Load utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities

# Create required directories
mkdir -p "$STATE_DIR"

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
    
    # Ensure jq is available
    if ! ensure_json_parser; then
        log "ERROR" "jq is not available"
        return 1
    fi
    
    # Validate global config
    if ! validate_json "$CONFIG_FILE"; then
        log "ERROR" "Config validation failed"
        return 1
    fi
    
    return 0
}

# Get ordered list of enabled modules
get_ordered_modules() {
    local modules=($(get_json_value "$CONFIG_FILE" '.global.modules.order[]'))
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
    local force=${3:-false}
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
        
        # Check if there's a platform-specific implementation
        local module_script="$MODULES_DIR/$module/$PLATFORM/$module.sh"
        
        # Fall back to common implementation if platform-specific one doesn't exist
        if [[ ! -f "$module_script" ]]; then
            module_script="$MODULES_DIR/$module/$module.sh"
        fi
        
        if [[ -f "$module_script" ]]; then
            log "INFO" "Running $stage for module: $module" "$module"
            
            case "$stage" in
                "install")
                    bash "$module_script" "$stage" "$force" || exit_code=1
                    ;;
                "info")
                    bash "$module_script" "$stage" || true  # Don't fail on info
                    ;;
                *)
                    bash "$module_script" "$stage" || exit_code=1
                    ;;
            esac
        else
            log "ERROR" "Module script not found: $module_script" "$module"
            [[ "$stage" != "grovel" ]] && exit_code=1
        fi
    done
    
    return $exit_code
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 COMMAND [MODULE] [OPTIONS]

Commands:
  install   Install one or all modules
  remove    Remove one or all modules
  verify    Verify one or all modules
  info      Show information about one or all modules
  backup    Create backup of current environment
  restore   Restore from backup

Options:
  --force   Force installation even if already installed

Examples:
  $0 install              # Install all modules
  $0 install git --force  # Force install git module
  $0 info docker         # Show docker module information
  $0 verify             # Verify all modules
EOF
}

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
        
        # Get module-specific backup paths from global config
        local paths=($(get_module_config "$module" '.backup.paths[]'))
        
        # Get platform-specific backup paths
        local platform_paths=($(get_module_config "$module" ".platforms.$PLATFORM.backup.paths[]" || echo ""))
        
        # Combine paths
        paths+=("${platform_paths[@]}")
        
        for path in "${paths[@]}"; do
            path=$(eval echo "$path")  # Expand environment variables
            if [[ -e "$path" ]]; then
                backup_file "$path" "$module"
            fi
        }
    done
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    # Parse arguments
    local action=$1
    shift
    local specific_module=""
    local force="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force="true"
                shift
                ;;
            *)
                if [[ -z "$specific_module" ]]; then
                    specific_module="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Verify environment first
    if ! verify_environment; then
        log "ERROR" "Environment verification failed"
        exit 1
    fi
    
    case "$action" in
        install)
            create_backup "$specific_module"
            execute_stage "install" "$specific_module" "$force"
            ;;
        remove)
            execute_stage "remove" "$specific_module"
            ;;
        verify)
            execute_stage "verify" "$specific_module"
            ;;
        info)
            execute_stage "info" "$specific_module"
            ;;
        backup)
            create_backup "$specific_module"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi