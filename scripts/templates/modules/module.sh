#!/bin/bash
# Template for new modules
# Replace "example" with your module name throughout this template

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "example" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/example.state"

# Display module information
show_module_info() {
    cat << 'EOF'

📦 Module: Example
================

Description:
-----------
Detailed description of what this module does and its primary purpose.

Benefits:
--------
✓ Benefit 1 - Detail about the first benefit
✓ Benefit 2 - Detail about the second benefit
✓ Benefit 3 - Detail about the third benefit

Components:
----------
1. Core System
   - What the core system provides
   - Dependencies and requirements

2. Configuration
   - What configurations are managed
   - Where configs are stored

Integrations:
-----------
• Integration 1 - How it works with other system X
• Integration 2 - How it works with other system Y

Quick Start:
-----------
1. Initial setup:
   $ devenv install example

2. Common operations:
   $ command1 arg    - What this does
   $ command2 arg    - What this does

Aliases:
-------
alias1  : Description of alias1
alias2  : Description of alias2

Configuration:
-------------
Location: ~/.config/example
Key files:
- config.json   : Main configuration
- settings.yml  : Additional settings

Tips:
----
• Tip 1 - Helpful usage tip
• Tip 2 - Another helpful tip

For more information:
-------------------
Documentation: https://docs.example.com
Support: https://support.example.com

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "core" "config"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            # Show version if applicable
            case "$component" in
                "core")
                    if command -v example &>/dev/null; then
                        echo "  Version: $(example --version 2>/dev/null || echo 'unknown')"
                    fi
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
    echo
}

# Save component state
save_state() {
    local component=$1
    local status=$2
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$component:$status:$(date +%s)" >> "$STATE_FILE"
}

# Check component state
check_state() {
    local component=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep -q "^$component:installed:" "$STATE_FILE"
        return $?
    fi
    return 1
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            command -v example &>/dev/null
            ;;
        "config")
            [[ -f "$CONFIG_FILE" ]] && validate_json "$CONFIG_FILE"
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "example"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "config")
            if install_config; then
                save_state "config" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Grovel checks existence and basic functionality
grovel_example() {
    local status=0
    
    for component in "core" "config"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "example"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_example() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_example &>/dev/null; then
        create_backup
    fi
    
    for component in "core" "config"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "example"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "example"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "example"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Verify entire installation
verify_example() {
    local status=0
    
    for component in "core" "config"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "example"
            status=1
        fi
    done
    
    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_example
        ;;
    install)
        install_example "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_example
        ;;
    info)
        show_module_info
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "example"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac