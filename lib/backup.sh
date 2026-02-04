#!/bin/bash
# lib/utils/backup.sh - Backup utilities

# Detect platform (local copy to avoid dependency on devenv.sh)
detect_platform() {
    if [[ -n "${PLATFORM:-}" ]]; then
        echo "$PLATFORM"
        return
    fi

    local platform="unknown"
    case "$(uname -s)" in
        Linux*)     platform="linux";;
        Darwin*)    platform="darwin";;
        MINGW*|MSYS*|CYGWIN*) platform="windows";;
        *)          platform="unknown";;
    esac

    echo "$platform"
}

create_backup() {
    local module=${1:-}

    # Get backup directory from module config if available
    local backup_base="$HOME/.devenv/backups"
    if [[ -n "$module" && -f "$MODULES_DIR/$module/config.json" ]]; then
        backup_base=$(get_json_value "$MODULES_DIR/$module/config.json" '.backup.dir' "$backup_base" "$module")
    fi

    # Get backup paths from module config
    local backup_paths=()
    
    # First try global backup paths
    if [[ -n "$module" && -f "$MODULES_DIR/$module/config.json" ]]; then
        mapfile -t global_paths < <(get_json_value "$MODULES_DIR/$module/config.json" '.backup.paths[]' "" "$module" 2>/dev/null || echo "")
        backup_paths+=("${global_paths[@]}")
    fi
    
    # Then try platform-specific backup paths
    if [[ -n "$module" && -f "$MODULES_DIR/$module/config.json" ]]; then
        platform="$(detect_platform)"
        mapfile -t platform_paths < <(get_json_value "$MODULES_DIR/$module/config.json" ".platforms.$platform.backup.paths[]" "" "$module" 2>/dev/null || echo "")
        backup_paths+=("${platform_paths[@]}")
    fi

    for path in "${backup_paths[@]}"; do
        # Skip empty paths
        [[ -z "$path" ]] && continue
        
        path=$(echo "$path" | expand_vars)  # Expand environment variables
        if [[ -e "$path" ]]; then
            backup_file "$path" "$module"
        fi
    done

    return 0
}

# Backup a file with module context
backup_file() {
    local path=$1
    local module=${2:-}

    # Get backup directory from module config if available
    local backup_base="$HOME/.devenv/backups"
    if [[ -n "$module" && -f "$MODULES_DIR/$module/config.json" ]]; then
        backup_base=$(get_json_value "$MODULES_DIR/$module/config.json" '.backup.dir' "$backup_base" "$module")
    fi

    local backup_dir="$backup_base/$(date +%Y%m%d_%H%M%S)"
    local module_dir="$backup_dir/${module:+$module/}"

    if [[ -f "$path" ]]; then
        mkdir -p "$module_dir"
        cp "$path" "$module_dir/$(basename "$path").backup"
        log "INFO" "Backed up $path to $module_dir" "$module"
    elif [[ -d "$path" ]]; then
        mkdir -p "$module_dir"
        cp -r "$path" "$module_dir/$(basename "$path").backup"
        log "INFO" "Backed up directory $path to $module_dir" "$module"
    else
        log "WARN" "Path not found for backup: $path" "$module"
        return 1
    fi

    return 0
}

# Restore a file with module context
restore_file() {
    local file=$1
    local module=${2:-}
    
    # Get backup directory from module config
    local backup_base="$HOME/.devenv/backups"
    if [[ -n "$module" && -f "$MODULES_DIR/$module/config.json" ]]; then
        backup_base=$(get_json_value "$MODULES_DIR/$module/config.json" '.backup.dir' "$backup_base" "$module")
    fi
    
    # Find latest backup
    local latest_backup=$(ls -td "$backup_base"/* 2>/dev/null | head -1)
    if [[ -z "$latest_backup" ]]; then
        log "ERROR" "No backup directory found" "$module"
        return 1
    fi
    
    local module_path="${module:+$module/}"
    local backup_file="$latest_backup/$module_path$(basename "$file").backup"
    
    if [[ -f "$backup_file" ]]; then
        cp "$backup_file" "$file"
        log "INFO" "Restored $file from backup" "$module"
        return 0
    else
        log "ERROR" "No backup found for file: $file" "$module"
        return 1
    fi
}

# Cleanup old backups based on module retention policy
cleanup_backups() {
    local module=${1:-}
    
    # Get backup configuration
    local backup_base="$HOME/.devenv/backups"
    local retention_days=30
    
    if [[ -n "$module" && -f "$MODULES_DIR/$module/config.json" ]]; then
        backup_base=$(get_json_value "$MODULES_DIR/$module/config.json" '.backup.dir' "$backup_base" "$module")
        retention_days=$(get_json_value "$MODULES_DIR/$module/config.json" '.backup.retention_days' "30" "$module")
    fi
    
    # Find and remove old backups
    find "$backup_base" -type d -mtime +"$retention_days" -exec rm -rf {} +
    log "INFO" "Cleaned up backups older than $retention_days days" "$module"
}
