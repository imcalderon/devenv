#!/bin/bash

set -euo pipefail

# Source all modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/backup.sh"
source "${SCRIPT_DIR}/lib/health.sh"
source "${SCRIPT_DIR}/lib/vscode.sh"
source "${SCRIPT_DIR}/lib/docker.sh"
source "${SCRIPT_DIR}/lib/conda.sh"
source "${SCRIPT_DIR}/lib/report.sh"
source "${SCRIPT_DIR}/lib/zsh.sh"

# Main installation function
main() {
    case "${1:-install}" in
        "install")
            log "INFO" "Starting development environment setup..."
            backup_configs
            
            # Enable EPEL repository
            heal_component "EPEL" "rpm -q epel-release" "sudo dnf install -y epel-release"
            
            # System update and tool installation
            log "INFO" "Updating system packages..."
            sudo dnf update -y
            heal_component "Development Tools" "rpm -q @development-tools" "sudo dnf groupinstall -y 'Development Tools'"
            
            # Install components
            setup_docker
            setup_vscode_settings
            setup_vscode_extensions
            setup_conda
            setup_zsh

            # Generate final report
            generate_system_report
            
            log "INFO" "Installation complete!"
            ;;
            
        "revert")
            source "${SCRIPT_DIR}/lib/revert.sh"
            revert_environment
            ;;
            
        "health")
            check_system_health
            ;;
            
        "heal")
            log "INFO" "Starting system healing..."
            check_system_health
            if [ $? -gt 0 ]; then
                log "INFO" "Issues found, attempting to heal..."
                main "install"
            else
                log "INFO" "No issues found, system is healthy"
            fi
            ;;
            
        *)
            echo "Usage: $0 {install|revert|health|heal}"
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"