#!/bin/bash
# lib/backup/backup.sh - Backup module implementation
# Use environment variables set by devenv.sh, with fallback if running standalone
if [ -z "${ROOT_DIR:-}" ]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Source dependencies using SCRIPT_DIR
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/module_base.sh"

grovel_backup() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    log "INFO" "Checking backup module dependencies..."
    
    # Check if backup directory exists or can be created
    if ! mkdir -p "${config_modules_backup_paths_root}" 2>/dev/null; then
        log "ERROR" "Cannot create backup directory at ${config_modules_backup_paths_root}"
        return 1
    fi
    
    # Check if we have write permissions
    if ! touch "${config_modules_backup_paths_root}/.test" 2>/dev/null; then
        log "ERROR" "No write permissions in backup directory"
        return 1
    fi
    rm -f "${config_modules_backup_paths_root}/.test"
    
    return 0
}

install_backup() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    log "INFO" "Setting up backup environment..."
    
    # Create backup directory structure with proper permissions
    local backup_dirs=(
        "${config_modules_backup_paths_root}"
        "${config_modules_backup_paths_root}/daily"
        "${config_modules_backup_paths_root}/weekly"
        "${config_modules_backup_paths_root}/monthly"
    )
    
    for dir in "${backup_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log "ERROR" "Failed to create backup directory: $dir"
            return 1
        fi
    done
    
    # Setup backup rotation script
    setup_backup_rotation || return 1
    
    # Perform initial backup
    create_backup || return 1
    
    return 0
}

setup_backup_rotation() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    local cron_file="/etc/cron.d/devenv-backup"
    
    # Create backup rotation script
    local rotation_script="${config_modules_backup_paths_root}/rotate-backups.sh"
    cat > "$rotation_script" << 'EOF'
#!/bin/bash

backup_root="$1"
retention_days="$2"

# Clean old backups
find "$backup_root/daily" -type d -mtime +"$retention_days" -exec rm -rf {} \;

# Move older daily backups to weekly (keep last 4 weeks)
find "$backup_root/daily" -type d -mtime +7 -exec mv {} "$backup_root/weekly/" \;
ls -t "$backup_root/weekly" | tail -n +5 | xargs -I {} rm -rf "$backup_root/weekly/{}"

# Move older weekly backups to monthly (keep last 12 months)
find "$backup_root/weekly" -type d -mtime +28 -exec mv {} "$backup_root/monthly/" \;
ls -t "$backup_root/monthly" | tail -n +13 | xargs -I {} rm -rf "$backup_root/monthly/{}"
EOF

    chmod +x "$rotation_script"
    
    # Setup cron job for rotation if sudo available
    if command -v sudo >/dev/null 2>&1; then
        echo "0 0 * * * root ${rotation_script} ${config_modules_backup_paths_root} ${config_modules_backup_retention_days}" | \
            sudo tee "$cron_file" > /dev/null
        sudo chmod 644 "$cron_file"
    else
        log "WARN" "Sudo not available, skipping cron setup. Manual rotation will be required."
    fi
    
    return 0
}

create_backup() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${config_modules_backup_paths_root}/daily/${timestamp}"
    
    mkdir -p "${backup_path}"
    
    # Backup each configured item
    for item_config in "${config_modules_backup_items[@]}"; do
        local module_name="${item_config%%:*}"
        local paths="${item_config#*:}"
        
        log "INFO" "Backing up ${module_name} configurations..."
        
        IFS=',' read -ra files <<< "$paths"
        for file in "${files[@]}"; do
            # Expand environment variables in path
            file=$(eval echo "$file")
            
            if [ -f "$file" ]; then
                # Create target directory structure
                local rel_path="${file#$HOME/}"
                local target_dir="${backup_path}/$(dirname ${rel_path})"
                mkdir -p "$target_dir"
                
                # Copy file with preserved attributes
                if ! cp -p "$file" "${backup_path}/${rel_path}"; then
                    log "ERROR" "Failed to backup file: ${file}"
                    return 1
                fi
                log "INFO" "Backed up ${file}"
            else
                log "WARN" "File not found: ${file}"
            fi
        done
    done
    
    # Create backup manifest
    create_backup_manifest "${backup_path}" "${timestamp}" || return 1
    
    # Create symlink to latest backup
    ln -sf "$backup_path" "${config_modules_backup_paths_root}/latest"
    
    log "INFO" "Backup completed at ${backup_path}"
    return 0
}

create_backup_manifest() {
    local backup_path=$1
    local timestamp=$2
    
    cat > "${backup_path}/manifest.txt" << EOF
Backup Information:
------------------
Created: $(date -d "@$(( ${timestamp%_*} ))" "+%Y-%m-%d %H:%M:%S")
User: $USER
Hostname: $(hostname)
System: $(uname -a)

Files:
------
$(find "${backup_path}" -type f ! -name "manifest.txt" -printf "%P\n" | sort)

Checksums:
---------
$(cd "${backup_path}" && find . -type f ! -name "manifest.txt" -exec sha256sum {} \;)
EOF
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create backup manifest"
        return 1
    fi
    
    return 0
}

restore_backup() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local backup_source=${1:-"${config_modules_backup_paths_root}/latest"}
    
    if [ ! -d "$backup_source" ]; then
        log "ERROR" "Backup directory not found: ${backup_source}"
        return 1
    fi
    
    # Verify backup integrity
    if ! verify_backup_integrity "$backup_source"; then
        log "ERROR" "Backup integrity check failed"
        return 1
    fi
    
    # Restore each configured item
    for item_config in "${config_modules_backup_items[@]}"; do
        local module_name="${item_config%%:*}"
        local paths="${item_config#*:}"
        
        log "INFO" "Restoring ${module_name} configurations..."
        
        IFS=',' read -ra files <<< "$paths"
        for file in "${files[@]}"; do
            file=$(eval echo "$file")
            local rel_path="${file#$HOME/}"
            
            if [ -f "${backup_source}/${rel_path}" ]; then
                # Create target directory
                mkdir -p "$(dirname "$file")"
                
                # Backup existing file if it exists
                [ -f "$file" ] && cp -p "$file" "${file}.bak"
                
                # Restore file
                if ! cp -p "${backup_source}/${rel_path}" "$file"; then
                    log "ERROR" "Failed to restore file: ${file}"
                    return 1
                fi
                log "INFO" "Restored ${file}"
            else
                log "WARN" "No backup found for ${file}"
            fi
        done
    done
    
    log "INFO" "Restore completed from ${backup_source}"
    return 0
}

verify_backup_integrity() {
    local backup_dir=$1
    
    if [ ! -f "${backup_dir}/manifest.txt" ]; then
        log "ERROR" "Manifest file not found"
        return 1
    fi
    
    # Verify checksums
    local current_dir=$(pwd)
    cd "${backup_dir}"
    local verification_failed=false
    
    while read -r line; do
        if ! echo "$line" | sha256sum --check --quiet; then
            log "ERROR" "Checksum verification failed for: $(echo $line | cut -d' ' -f2)"
            verification_failed=true
        fi
    done < <(grep -v '^Backup\|^Files:\|^Checksums:\|^$' manifest.txt | grep "^[0-9a-f]")
    
    cd "$current_dir"
    
    [ "$verification_failed" = true ] && return 1
    return 0
}

remove_backup() {
    # Backup module doesn't need removal since it's just storing backups
    log "INFO" "Backup module doesn't require removal"
    return 0
}

verify_backup() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local verification_failed=false
    
    # Check backup directories
    local required_dirs=(
        "${config_modules_backup_paths_root}"
        "${config_modules_backup_paths_root}/daily"
        "${config_modules_backup_paths_root}/weekly"
        "${config_modules_backup_paths_root}/monthly"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "ERROR" "Required directory not found: $dir"
            verification_failed=true
        fi
    done
    
    # Check rotation script
    local rotation_script="${config_modules_backup_paths_root}/rotate-backups.sh"
    if [ ! -x "$rotation_script" ]; then
        log "ERROR" "Backup rotation script not found or not executable"
        verification_failed=true
    fi
    
    # Verify latest backup if it exists
    if [ -L "${config_modules_backup_paths_root}/latest" ]; then
        if ! verify_backup_integrity "$(readlink -f ${config_modules_backup_paths_root}/latest)"; then
            log "ERROR" "Latest backup integrity check failed"
            verification_failed=true
        fi
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