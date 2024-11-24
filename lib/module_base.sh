#!/bin/bash
# lib/module_base.sh - Base module template

# Root and script directories should be set by devenv.sh
# If not set, derive them (though this shouldn't happen)
if [ -z "${ROOT_DIR:-}" ]; then
    export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Base class for all modules
module_base() {
    local STAGE=$1
    local MODULE_NAME=$2
    
    # Load module configuration from root config.yaml
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Construct proper module path
    local MODULE_SCRIPT="$SCRIPT_DIR/$MODULE_NAME/$MODULE_NAME.sh"
    
    if [ ! -f "$MODULE_SCRIPT" ]; then
        log "ERROR" "Module script not found: $MODULE_SCRIPT"
        return 1
    fi
    
    case $STAGE in
        "grovel")
            if type grovel_${MODULE_NAME} &>/dev/null; then
                grovel_${MODULE_NAME} || true  # Don't propagate failure
            else
                log "WARN" "No grovel stage implemented for ${MODULE_NAME}"
                return 0
            fi
            ;;
        "install")
            if type install_${MODULE_NAME} &>/dev/null; then
                install_${MODULE_NAME} && configure_module_aliases "${MODULE_NAME}"
            else
                log "ERROR" "No install stage implemented for ${MODULE_NAME}"
                return 1
            fi
            ;;
        "remove")
            if type remove_${MODULE_NAME} &>/dev/null; then
                remove_${MODULE_NAME} && remove_module_aliases "${MODULE_NAME}"
            else
                log "WARN" "No remove stage implemented for ${MODULE_NAME}"
                return 0
            fi
            ;;
        "verify")
            if type verify_${MODULE_NAME} &>/dev/null; then
                verify_${MODULE_NAME} && verify_module_aliases "${MODULE_NAME}"
            else
                log "ERROR" "No verify stage implemented for ${MODULE_NAME}"
                return 1
            fi
            ;;
        "update")
            if type update_${MODULE_NAME} &>/dev/null; then
                update_${MODULE_NAME} && configure_module_aliases "${MODULE_NAME}"
            else
                log "WARN" "No update stage implemented for ${MODULE_NAME}"
                return 0
            fi
            ;;
        *)
            log "ERROR" "Unknown stage: $STAGE"
            return 1
            ;;
    esac
}

# Configure aliases for a module
configure_module_aliases() {
    local MODULE_NAME=$1
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local zshrc="$HOME/.zshrc"
    local alias_block="# ${MODULE_NAME} aliases - managed by devenv"
    
    # Remove existing alias block if it exists
    sed -i "/# ${MODULE_NAME} aliases - managed by devenv/,/# End ${MODULE_NAME} aliases/d" "$zshrc"
    
    # Get all alias categories for this module
    local prefix="config_modules_${MODULE_NAME}_aliases_"
    local categories=($(compgen -A variable | grep "^$prefix" | sed "s/^$prefix//" | cut -d_ -f1 | sort -u))
    
    if [ ${#categories[@]} -gt 0 ]; then
        {
            echo "$alias_block"
            
            # Add aliases for each category
            for category in "${categories[@]}"; do
                local var_name="config_modules_${MODULE_NAME}_aliases_${category}[@]"
                local aliases=("${!var_name}")
                
                echo "# ${category} aliases"
                for alias_data in "${aliases[@]}"; do
                    local name="${alias_data[name]}"
                    local cmd="${alias_data[command]}"
                    echo "alias $name='$cmd'"
                done
                echo ""
            done
            
            echo "# End ${MODULE_NAME} aliases"
        } >> "$zshrc"
        
        log "INFO" "Configured aliases for ${MODULE_NAME}"
    fi
}

# Remove aliases for a module
remove_module_aliases() {
    local MODULE_NAME=$1
    local zshrc="$HOME/.zshrc"
    
    sed -i "/# ${MODULE_NAME} aliases - managed by devenv/,/# End ${MODULE_NAME} aliases/d" "$zshrc"
    log "INFO" "Removed aliases for ${MODULE_NAME}"
}

# Verify aliases for a module
verify_module_aliases() {
    local MODULE_NAME=$1
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local zshrc="$HOME/.zshrc"
    local verification_failed=false
    
    # Get all alias categories for this module
    local prefix="config_modules_${MODULE_NAME}_aliases_"
    local categories=($(compgen -A variable | grep "^$prefix" | sed "s/^$prefix//" | cut -d_ -f1 | sort -u))
    
    if [ ${#categories[@]} -gt 0 ]; then
        # Check for alias block markers
        if ! grep -q "# ${MODULE_NAME} aliases - managed by devenv" "$zshrc"; then
            log "ERROR" "Alias block not found for ${MODULE_NAME}"
            verification_failed=true
        fi
        
        # Verify each alias is present
        for category in "${categories[@]}"; do
            local var_name="config_modules_${MODULE_NAME}_aliases_${category}[@]"
            local aliases=("${!var_name}")
            
            for alias_data in "${aliases[@]}"; do
                local name="${alias_data[name]}"
                local cmd="${alias_data[command]}"
                if ! grep -q "alias ${name}='${cmd}'" "$zshrc"; then
                    log "ERROR" "Alias not found: ${name}='${cmd}'"
                    verification_failed=true
                fi
            done
        done
    fi
    
    [ "$verification_failed" = true ] && return 1
    return 0
}

# Helper function for backup
backup_file() {
    local file=$1
    local backup_dir="$HOME/.devenv/backups/$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        cp "$file" "$backup_dir/$(basename "$file").backup"
        log "INFO" "Backed up $file to $backup_dir"
    fi
}

# Helper function for restoring backups
restore_backup() {
    local file=$1
    local backup_dir=$(ls -td $HOME/.devenv/backups/* | head -1)
    local backup_file="$backup_dir/$(basename "$file").backup"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$file"
        log "INFO" "Restored $file from backup"
    else
        log "WARN" "No backup found for $file"
    fi
}

# Get module runlevel
get_module_runlevel() {
    local MODULE_NAME=$1
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local var_name="config_modules_${MODULE_NAME}_runlevel"
    echo "${!var_name:-999}"  # Default to high number if not set
}