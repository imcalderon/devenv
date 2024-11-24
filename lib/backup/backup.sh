#!/bin/bash
# lib/backup/backup.sh - Backup module implementation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../logging.sh"
source "${SCRIPT_DIR}/../yaml_parser.sh"
source "${SCRIPT_DIR}/../module_base.sh"

grovel_backup() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Check backup directory exists/can be created
    if ! mkdir -p "${config_modules_backup_paths_root}" 2>/dev/null; then
        log "INFO" "Cannot create backup directory"
        return 1
    fi
}

install_backup() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Create backup directory structure
    mkdir -p "${config_modules_backup_paths_root}"
    
    # Perform initial backup
    create_backup
}

create_backup() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${config_modules_backup_paths_root}/${timestamp}"
    
    mkdir -p "${backup_path}"
    
    # Backup each configured file
    for module in "${config_modules_backup_items[@]}"; do
        local module_name="${module%%:*}"
        local paths="${module#*:}"
        
        log "INFO" "Backing up ${module_name} configurations..."
        
        IFS=',' read -ra files <<< "$paths"
        for file in "${files[@]}"; do
            # Expand environment variables in path
            file=$(eval echo "$file")
            
            if [ -f "$file" ]; then
                # Create target directory structure
                local rel_path="${file#$HOME/}"
                mkdir -p "${backup_path}/$(dirname ${rel_path})"
                
                # Copy file with preserved attributes
                cp -p "$file" "${backup_path}/${rel_path}"
                log "INFO" "Backed up ${file}"
            else
                log "WARN" "File not found: ${file}"
            fi
        done
    done
    
    # Create backup manifest
    create_backup_manifest "${backup_path}" "${timestamp}"
    
    # Cleanup old backups if configured
    cleanup_old_backups
    
    log "INFO" "Backup completed at ${backup_path}"
}

create_backup_manifest() {
    local backup_path=$1
    local timestamp=$2
    
    cat > "${backup_path}/manifest.txt" << EOF
Backup created: $(date -d "@$(( ${timestamp%_*} ))" "+%Y-%m-%d %H:%M:%S")
User: $USER
Hostname: $(hostname)
System: $(uname -a)

Files:
$(find "${backup_path}" -type f ! -name "manifest.txt" -printf "%P\n" | sort)
EOF
}

get_latest_backup() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    find "${config_modules_backup_paths_root}" -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -n1
}

restore_backup() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    local backup_source=$1
    if [ -z "$backup_source" ]; then
        backup_source=$(get_latest_backup)
    fi
    
    if [ ! -d "$backup_source" ]; then
        log "ERROR" "Backup directory not found: ${backup_source}"
        return 1
    fi
    
    # Restore each configured file
    for module in "${config_modules_backup_items[@]}"; do
        local module_name="${module%%:*}"
        local paths="${module#*:}"
        
        log "INFO" "Restoring ${module_name} configurations..."
        
        IFS=',' read -ra files <<< "$paths"
        for file in "${files[@]}"; do
            # Expand environment variables in path
            file=$(eval echo "$file")
            local rel_path="${file#$HOME/}"
            
            restore_from_backup "$backup_source" "$rel_path" "$file"
        done
    done
}

restore_from_backup() {
    local backup_dir=$1
    local rel_path=$2
    local target_path=$3
    
    if [ -f "${backup_dir}/${rel_path}" ]; then
        mkdir -p "$(dirname "${target_path}")"
        cp -p "${backup_dir}/${rel_path}" "${target_path}"
        log "INFO" "Restored ${rel_path} to ${target_path}"
        return 0
    else
        log "WARN" "No backup found for ${rel_path}"
        return 1
    fi
}

cleanup_old_backups() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    if [ -n "${config_modules_backup_retention_days}" ]; then
        find "${config_modules_backup_paths_root}" -maxdepth 1 -type d -name "[0-9]*" -mtime "+${config_modules_backup_retention_days}" -exec rm -rf {} \;
    fi
}

remove_backup() {
    log "INFO" "Backup module doesn't require removal"
    return 0
}

verify_backup() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    local verification_failed=false
    
    # Check backup directory exists
    if [ ! -d "${config_modules_backup_paths_root}" ]; then
        log "ERROR" "Backup directory not found"
        verification_failed=true
    fi
    
    # Verify latest backup if it exists
    local latest_backup=$(get_latest_backup)
    if [ -n "$latest_backup" ]; then
        if [ ! -f "${latest_backup}/manifest.txt" ]; then
            log "ERROR" "Latest backup manifest not found"
            verification_failed=true
        fi
        
        # Check all configured files were backed up
        for module in "${config_modules_backup_items[@]}"; do
            local paths="${module#*:}"
            IFS=',' read -ra files <<< "$paths"
            for file in "${files[@]}"; do
                file=$(eval echo "$file")
                local rel_path="${file#$HOME/}"
                if [ -f "$file" ] && [ ! -f "${latest_backup}/${rel_path}" ]; then
                    log "ERROR" "File not found in latest backup: ${rel_path}"
                    verification_failed=true
                fi
            done
        done
    fi
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "Backup verification complete"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify}"
        exit 1
    fi
    module_base "$1" "backup"
fi