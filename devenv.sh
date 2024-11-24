#!/bin/bash
# main.sh - Main entry point for development environment setup

set -euo pipefail

# Load yaml parser
source ./lib/yaml_parser.sh

# Constants
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
BACKUP_DIR="$HOME/.dev_env_backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$SCRIPT_DIR/setup.log"

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# Function to load and parse config
load_config() {
    parse_yaml "$CONFIG_FILE"
}

# Function to execute a stage for all enabled modules
execute_stage() {
    local stage=$1
    local modules=($(get_enabled_modules))
    
    echo "Executing stage: $stage"
    for module in "${modules[@]}"; do
        if [[ -f "$SCRIPT_DIR/lib/$module/$module.sh" ]]; then
            echo "Running $stage for module: $module"
            bash "$SCRIPT_DIR/lib/$module/$module.sh" "$stage"
        fi
    done
}

# Function to create backup
create_backup() {
    mkdir -p "$BACKUP_DIR"
    if [[ -f "$HOME/.zshrc" ]]; then
        cp "$HOME/.zshrc" "$BACKUP_DIR/.zshrc.backup"
    fi
    echo "Created backup at: $BACKUP_DIR"
}

# Main execution
main() {
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
        *)
            echo "Usage: $0 {install|remove|verify}"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 {install|remove|verify}"
        exit 1
    fi
    main "$1"
fi