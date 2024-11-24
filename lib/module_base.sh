#!/bin/bash
# lib/module_base.sh - Base module template

# Base class for all modules
module_base() {
    local STAGE=$1
    local MODULE_NAME=$2
    
    case $STAGE in
        "grovel")
            if type grovel_${MODULE_NAME} &>/dev/null; then
                grovel_${MODULE_NAME}
            else
                log "WARN" "No grovel stage implemented for ${MODULE_NAME}"
            fi
            ;;
        "install")
            if type install_${MODULE_NAME} &>/dev/null; then
                install_${MODULE_NAME}
            else
                log "WARN" "No install stage implemented for ${MODULE_NAME}"
            fi
            ;;
        "remove")
            if type remove_${MODULE_NAME} &>/dev/null; then
                remove_${MODULE_NAME}
            else
                log "WARN" "No remove stage implemented for ${MODULE_NAME}"
            fi
            ;;
        "verify")
            if type verify_${MODULE_NAME} &>/dev/null; then
                verify_${MODULE_NAME}
            else
                log "WARN" "No verify stage implemented for ${MODULE_NAME}"
            fi
            ;;
        "update")
            if type update_${MODULE_NAME} &>/dev/null; then
                update_${MODULE_NAME}
            else
                log "WARN" "No update stage implemented for ${MODULE_NAME}"
            fi
            ;;
        *)
            log "ERROR" "Unknown stage: $STAGE"
            return 1
            ;;
    esac
}

# Helper function for backup
backup_file() {
    local file=$1
    local backup_dir="$HOME/.dev_env_backups/$(date +%Y%m%d_%H%M%S)"
    
    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        cp "$file" "$backup_dir/$(basename "$file").backup"
        log "INFO" "Backed up $file to $backup_dir"
    fi
}

# Helper function for restoring backups
restore_backup() {
    local file=$1
    local backup_dir=$(ls -td $HOME/.dev_env_backups/* | head -1)
    local backup_file="$backup_dir/$(basename "$file").backup"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$file"
        log "INFO" "Restored $file from backup"
    else
        log "WARN" "No backup found for $file"
    fi
}