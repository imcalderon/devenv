#!/bin/bash
# devenv.sh - Development environment setup with cross-platform support

set -euo pipefail

# Get absolute paths if not already set
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

# Ensure DEVENV environment variables are set
if [[ -z "${DEVENV_ROOT:-}" ]]; then
    export DEVENV_ROOT="$ROOT_DIR"
    export DEVENV_DATA_DIR="$HOME/.devenv"
    export DEVENV_MODULES_DIR="$ROOT_DIR/modules"
    export DEVENV_STATE_DIR="$DEVENV_DATA_DIR/state"
    export DEVENV_LOGS_DIR="$DEVENV_DATA_DIR/logs"
    export DEVENV_BACKUPS_DIR="$DEVENV_DATA_DIR/backups"
    
    # Create data directories if they don't exist
    mkdir -p "$DEVENV_DATA_DIR"
    mkdir -p "$DEVENV_STATE_DIR"
    mkdir -p "$DEVENV_LOGS_DIR"
    mkdir -p "$DEVENV_BACKUPS_DIR"
fi

# Use project-based state directory
export STATE_DIR="$DEVENV_STATE_DIR"

# Load utilities
source "$SCRIPT_DIR/compat.sh"   # Cross-platform compatibility helpers
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/secrets.sh"  # Secrets management
source "$SCRIPT_DIR/scaffold.sh" # Project scaffolding

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
    
    # Validate global config syntax
    if ! validate_json "$CONFIG_FILE"; then
        log "ERROR" "Config validation failed"
        return 1
    fi

    # Structural validation (warnings only, don't block on schema issues)
    validate_root_config "$CONFIG_FILE" || \
        log "WARN" "Config structural validation found issues (see warnings above)"

    return 0
}

# Get ordered list of enabled modules
get_ordered_modules() {
    local modules=($(get_json_value "$CONFIG_FILE" ".platforms.$PLATFORM.modules.order[]"))
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
    local specific_module="${2:-}"  # Default to empty string
    local force="${3:-false}"       # Default to false
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
  install        Install one or all modules
  remove         Remove one or all modules
  verify         Verify one or all modules
  info           Show information about one or all modules
  init           Initialize environment from a workflow
  workflows      List available workflows
  --new-project  Create a new project from a scaffold
  --list-types   List available project types
  backup         Create backup of current environment
  restore        Restore from backup
  secrets        Manage secrets (wizard, show, set, reset, validate, export, import)

Options:
  --force              Force installation even if already installed
  --type <type>        Project type for --new-project (e.g. vfx, web:phaser)
  --location <path>    Target directory for --new-project (default: current dir)

Examples:
  $0 install                                    # Install all modules
  $0 install git --force                        # Force install git module
  $0 verify                                     # Verify all modules
  $0 workflows                                  # List available workflows
  $0 init vfx                                   # Initialize VFX workflow
  $0 --new-project my-tool --type vfx           # Scaffold a VFX C++ project
  $0 --new-project my-game --type web:phaser    # Scaffold a Phaser game
  $0 --list-types                               # Show project scaffold types
EOF
}

create_backup() {
    local specific_module="${1:-}"  # Default to empty string
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
        local platform_paths=()
        # Commented out to avoid potential errors if this value doesn't exist
        # platform_paths=($(get_module_config "$module" ".platforms.$PLATFORM.backup.paths[]" || echo ""))
        
        # Combine paths
        paths+=("${platform_paths[@]}")
        
        for path in "${paths[@]}"; do
            path=$(echo "$path" | expand_vars)  # Expand environment variables
            if [[ -e "$path" ]]; then
                backup_file "$path" "$module"
            fi
        done
    done
}

# Restore from backup
restore_backup() {
    local specific_module="${1:-}"
    local -a modules

    if [[ -n "$specific_module" ]]; then
        modules=("$specific_module")
    else
        readarray -t modules < <(get_ordered_modules)
    fi

    # Find latest backup directory
    local backup_base="$DEVENV_BACKUPS_DIR"
    local latest_backup=$(ls -td "$backup_base"/* 2>/dev/null | head -1)

    if [[ -z "$latest_backup" ]]; then
        log "ERROR" "No backup found in $backup_base"
        return 1
    fi

    log "INFO" "Restoring from backup: $latest_backup"

    for module in "${modules[@]}"; do
        if ! init_module "$module"; then
            log "ERROR" "Failed to initialize module: $module"
            continue
        fi

        log "INFO" "Restoring module: $module" "$module"

        # Get module backup paths
        local paths=($(get_module_config "$module" '.backup.paths[]' 2>/dev/null || echo ""))

        for path in "${paths[@]}"; do
            [[ -z "$path" ]] && continue
            path=$(echo "$path" | expand_vars)
            local filename=$(basename "$path")
            local backup_file="$latest_backup/$module/$filename.backup"

            if [[ -f "$backup_file" ]]; then
                # Create parent directory if needed
                mkdir -p "$(dirname "$path")"
                cp "$backup_file" "$path"
                log "INFO" "Restored: $path" "$module"
            elif [[ -d "$backup_file" ]]; then
                mkdir -p "$(dirname "$path")"
                cp -r "$backup_file" "$path"
                log "INFO" "Restored directory: $path" "$module"
            fi
        done
    done

    log "INFO" "Restore completed"
}

# Initialize from a template
init_template() {
    local template_name=$1
    local force="${2:-false}"

    if [[ -z "$template_name" ]]; then
        log "ERROR" "Template name required. Use 'workflows' to see available options."
        list_workflows
        return 1
    fi

    # Try workflow definitions first, then fall back to config.json templates
    local template_modules=""
    local resolved_name="$template_name"

    # Handle legacy template name aliases
    case "$template_name" in
        vfx_platform) resolved_name="vfx" ;;
        web_development) resolved_name="web" ;;
        game_development) resolved_name="game" ;;
    esac

    local workflow_file="$ROOT_DIR/workflows/$resolved_name/workflow.json"

    if [[ -f "$workflow_file" ]]; then
        template_modules=$(jq -r ".modules.$PLATFORM[]?" "$workflow_file" 2>/dev/null)
    fi

    # Fallback: check config.json templates (backward compatibility)
    if [[ -z "$template_modules" ]]; then
        template_modules=$(get_json_value "$CONFIG_FILE" ".templates.$template_name.modules.$PLATFORM[]" "" 2>/dev/null)
    fi

    if [[ -z "$template_modules" ]]; then
        log "ERROR" "Workflow '$template_name' not found or has no modules for platform '$PLATFORM'"
        return 1
    fi

    log "INFO" "Initializing workflow: $template_name (platform: $PLATFORM)"

    # Install each module in template order
    local exit_code=0
    for module in $template_modules; do
        log "INFO" "Installing module: $module"
        if ! execute_stage "install" "$module" "$force"; then
            log "ERROR" "Failed to install module: $module"
            exit_code=1
        fi
    done

    # Run post-init commands if defined in workflow
    if [[ -f "$workflow_file" ]]; then
        local post_init
        post_init=$(jq -r '.post_init[]?' "$workflow_file" 2>/dev/null)
        if [[ -n "$post_init" ]]; then
            log "INFO" "Running post-init commands..."
            while IFS= read -r cmd; do
                log "DEBUG" "Running: $cmd"
                eval "$cmd" || log "WARN" "Post-init command failed: $cmd"
            done <<< "$post_init"
        fi
    fi

    # Save template state
    local template_state_file="$DEVENV_STATE_DIR/template.state"
    mkdir -p "$(dirname "$template_state_file")"
    cat > "$template_state_file" << EOF
template:$template_name
platform:$PLATFORM
timestamp:$(date +%s)
modules:$(echo $template_modules | tr '\n' ',')
EOF

    if [[ $exit_code -eq 0 ]]; then
        log "INFO" "Workflow '$template_name' initialized successfully"
    else
        log "WARN" "Workflow '$template_name' initialized with errors"
    fi

    return $exit_code
}

# List available workflows
list_workflows() {
    log "INFO" "Available workflows:"
    local workflows_dir="$ROOT_DIR/workflows"

    if [[ -d "$workflows_dir" ]]; then
        for wf_dir in "$workflows_dir"/*/; do
            local wf_name
            wf_name=$(basename "$wf_dir")
            local wf_file="$wf_dir/workflow.json"
            if [[ -f "$wf_file" ]]; then
                local desc
                desc=$(jq -r '.description // "No description"' "$wf_file")
                local subtypes
                subtypes=$(jq -r '.subtypes | keys[]?' "$wf_file" 2>/dev/null)
                log "INFO" "  $wf_name - $desc"
                if [[ -n "$subtypes" ]]; then
                    while IFS= read -r st; do
                        local st_desc
                        st_desc=$(jq -r ".subtypes.\"$st\".description // \"\"" "$wf_file")
                        log "INFO" "    $wf_name:$st - $st_desc"
                    done <<< "$subtypes"
                fi
            fi
        done
    fi

    # Also show legacy templates from config.json
    local legacy_templates
    legacy_templates=$(get_json_value "$CONFIG_FILE" ".templates | keys[]" "" 2>/dev/null)
    if [[ -n "$legacy_templates" ]]; then
        for t in $legacy_templates; do
            # Skip if already shown as a workflow
            if [[ -f "$workflows_dir/$t/workflow.json" ]]; then
                continue
            fi
            local desc
            desc=$(get_json_value "$CONFIG_FILE" ".templates.$t.description" "$t")
            log "INFO" "  $t - $desc (legacy)"
        done
    fi
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
    local project_name=""
    local project_type=""
    local project_location="."
    local -a extra_args=()

    # Handle --new-project and --list-types as actions
    case "$action" in
        --new-project)
            action="new-project"
            if [[ $# -gt 0 && "$1" != --* ]]; then
                project_name="$1"
                shift
            fi
            ;;
        --list-types)
            action="list-types"
            ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force="true"
                shift
                ;;
            --type)
                project_type="${2:-}"
                shift 2
                ;;
            --location)
                project_location="${2:-}"
                shift 2
                ;;
            *)
                if [[ -z "$specific_module" ]]; then
                    specific_module="$1"
                else
                    extra_args+=("$1")
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
        init)
            if [[ -z "$specific_module" ]]; then
                log "ERROR" "Workflow name required: $0 init <workflow>"
                list_workflows
                exit 1
            fi
            init_template "$specific_module" "$force"
            ;;
        workflows)
            list_workflows
            ;;
        new-project)
            if [[ -z "$project_name" ]]; then
                log "ERROR" "Project name required: $0 --new-project <name> --type <type>"
                exit 1
            fi
            if [[ -z "$project_type" ]]; then
                log "ERROR" "Project type required: --type <vfx|web:phaser|web:vanilla>"
                list_project_types
                exit 1
            fi
            scaffold_project "$project_name" "$project_type" "$project_location"
            ;;
        list-types)
            list_project_types
            ;;
        backup)
            create_backup "$specific_module"
            ;;
        restore)
            restore_backup "$specific_module"
            ;;
        secrets)
            secrets_command "$specific_module" "${extra_args[@]+"${extra_args[@]}"}"
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