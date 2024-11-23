#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

BACKUP_DIR="$HOME/.devenv/backups"

get_latest_backup() {
    find "${BACKUP_DIR}" -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -n1
}

backup_configs() {
    local backup_path="${BACKUP_DIR}/${TIMESTAMP}"
    mkdir -p "${backup_path}"
    
    for config in ".gitconfig" ".zshrc" ".vscode/settings.json"; do
        if [ -f "$HOME/${config}" ]; then
            mkdir -p "${backup_path}/$(dirname ${config})"
            cp "$HOME/${config}" "${backup_path}/${config}"
            log "INFO" "Backed up ${config}"
        fi
    done
}

restore_from_backup() {
    local backup_dir=$1
    local target_file=$2
    local original_path=$3

    if [ -f "${backup_dir}/${target_file}" ]; then
        mkdir -p "$(dirname "${original_path}")"
        cp "${backup_dir}/${target_file}" "${original_path}"
        log "INFO" "Restored ${target_file} from backup"
        return 0
    else
        log "WARN" "No backup found for ${target_file}"
        return 1
    fi
}