#!/bin/bash
# modules/qtcreator/qtcreator.sh - Qt Creator module implementation

# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "qtcreator" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/qtcreator.state"

# Define module components
COMPONENTS=("core" "shell")

# Display module information
show_module_info() {
    echo
    echo "Qt Creator IDE"
    echo "=============="
    echo
    echo "Description:"
    echo "Qt Creator IDE for cross-platform C++, QML and Python development."
    echo
    echo "Status:"
    if check_state "core"; then
        echo "  [ok] core: Installed"
    else
        echo "  [--] core: Not installed"
    fi
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

# Detect platform package manager
detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            command -v qtcreator &>/dev/null || command -v qt-creator &>/dev/null
            ;;
        "shell")
            list_module_aliases "qtcreator" "qt" &>/dev/null
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
        log "INFO" "Component $component already installed and verified" "qtcreator"
        return 0
    fi

    case "$component" in
        "core")
            local pkg_manager
            pkg_manager=$(detect_pkg_manager)
            case "$pkg_manager" in
                "apt")
                    sudo apt-get update -qq && sudo apt-get install -y qtcreator
                    ;;
                "dnf")
                    sudo dnf install -y qt-creator
                    ;;
                "brew")
                    brew install --cask qt-creator
                    ;;
                *)
                    log "ERROR" "Unsupported package manager for qtcreator" "qtcreator"
                    return 1
                    ;;
            esac
            ;;
        "shell")
            add_module_aliases "qtcreator" "qt"
            ;;
    esac

    if [ $? -eq 0 ]; then
        save_state "$component" "installed"
        return 0
    fi
    return 1
}

# Install module
install_qtcreator() {
    local force=${1:-false}
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "qtcreator"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "qtcreator"
                return 1
            fi
        fi
    done
    return 0
}

# Remove module
remove_qtcreator() {
    log "INFO" "Removing qtcreator module configuration..." "qtcreator"
    remove_module_aliases "qtcreator" "qt"
    rm -f "$STATE_FILE"
    log "WARN" "Qt Creator application was preserved. Uninstall manually if desired." "qtcreator"
    return 0
}

# Execute requested action
case "${1:-}" in
    grovel)
        if verify_component "core"; then exit 0; else exit 1; fi
        ;;
    install)
        install_qtcreator "${2:-false}"
        ;;
    verify)
        if verify_component "core"; then exit 0; else exit 1; fi
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_qtcreator
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "qtcreator"
        exit 1
        ;;
esac
