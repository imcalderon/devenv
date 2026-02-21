#!/bin/bash
# modules/bazel/bazel.sh - Bazel module implementation

# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "bazel" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/bazel.state"

# Define module components
COMPONENTS=("core" "shell")

# Display module information
show_module_info() {
    echo
    echo "Bazel (via Bazelisk)"
    echo "===================="
    echo
    echo "Description:"
    echo "Hermetic build system with multi-language support."
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
    if command -v brew &>/dev/null; then
        echo "brew"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            command -v bazel &>/dev/null
            ;;
        "shell")
            list_module_aliases "bazel" "bazel" &>/dev/null
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
        log "INFO" "Component $component already installed and verified" "bazel"
        return 0
    fi

    case "$component" in
        "core")
            local pkg_manager
            pkg_manager=$(detect_pkg_manager)
            case "$pkg_manager" in
                "brew")
                    brew install bazelisk
                    ;;
                "apt"|"dnf"|"unknown")
                    # Install Bazelisk to /usr/local/bin
                    local url
                    url=$(get_module_config "bazel" ".platforms.linux.binary_url")
                    log "INFO" "Downloading Bazelisk from $url" "bazel"
                    sudo curl -L "$url" -o /usr/local/bin/bazel
                    sudo chmod +x /usr/local/bin/bazel
                    ;;
            esac
            ;;
        "shell")
            add_module_aliases "bazel" "bazel"
            ;;
    esac

    if [ $? -eq 0 ]; then
        save_state "$component" "installed"
        return 0
    fi
    return 1
}

# Install module
install_bazel() {
    local force=${1:-false}
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "bazel"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "bazel"
                return 1
            fi
        fi
    done
    return 0
}

# Remove module
remove_bazel() {
    log "INFO" "Removing bazel module configuration..." "bazel"
    remove_module_aliases "bazel" "bazel"
    rm -f "$STATE_FILE"
    log "WARN" "Bazelisk binary preserved at /usr/local/bin/bazel. Remove manually if desired." "bazel"
    return 0
}

# Execute requested action
case "${1:-}" in
    grovel)
        if verify_component "core"; then exit 0; else exit 1; fi
        ;;
    install)
        install_bazel "${2:-false}"
        ;;
    verify)
        if verify_component "core"; then exit 0; else exit 1; fi
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_bazel
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "bazel"
        exit 1
        ;;
esac
