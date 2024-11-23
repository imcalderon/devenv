#!/bin/bash
set -euo pipefail

# Load common functions and variables
source "$(dirname "$0")/lib/common.sh"

usage() {
    echo "Usage: $0 {install|revert|health|heal|update}"
    exit 1
}

main() {
    check_requirements
    load_config

    case "${1:-install}" in
        "install")
            run_script "backup.sh"
            run_script "system.sh"
            run_script "tools.sh"
            run_script "docker.sh"
            run_script "vscode.sh"
            run_script "python.sh"
            run_script "node.sh"
            run_script "shell.sh"
            run_script "report.sh"
            ;;
        "revert")
            run_script "revert.sh"
            ;;
        "health")
            run_script "health.sh"
            ;;
        "heal")
            run_script "health.sh"
            if [ $? -gt 0 ]; then
                log "INFO" "Issues found, attempting to heal..."
                main "install"
            else
                log "INFO" "No issues found, system is healthy"
            fi
            ;;
        "update")
            run_script "update.sh"
            ;;
        *)
            usage
            ;;
    esac
}
