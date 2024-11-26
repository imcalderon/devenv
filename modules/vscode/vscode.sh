#!/bin/bash
# modules/vscode/vscode.sh - VSCode module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/alias.sh"    # For shell alias support

# Initialize module
init_module "vscode" || exit 1

# Check for VSCode installation and configuration
grovel_vscode() {
    if ! command -v code &>/dev/null; then
        log "INFO" "VSCode not found" "vscode"
        return 1
    fi

    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    if [[ ! -d "$config_dir" ]]; then
        log "INFO" "VSCode configuration directory not found" "vscode"
        return 1
    fi

    return 0
}

# Install and configure VSCode
install_vscode() {
    log "INFO" "Setting up VSCode environment..." "vscode"

    # Install VSCode if needed
    if ! command -v code &>/dev/null; then
        if ! install_vscode_package; then
            return 1
        fi
    fi

    # Create required directories
    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    local extensions_dir=$(get_module_config "vscode" ".shell.paths.extensions_dir")
    config_dir=$(eval echo "$config_dir")
    extensions_dir=$(eval echo "$extensions_dir")

    mkdir -p "$config_dir"
    mkdir -p "$extensions_dir"

    # Configure VSCode
    if ! configure_vscode_settings; then
        return 1
    fi

    # Install extensions
    if ! install_vscode_extensions; then
        return 1
    fi

    # Add VSCode aliases
    add_module_aliases "vscode" "editor" || return 1

    return 0
}

# Install VSCode package based on system package manager
install_vscode_package() {
    log "INFO" "Installing VSCode..." "vscode"

    if command -v dnf &>/dev/null; then
        # RPM-based installation
        local key_url=$(get_module_config "vscode" ".vscode.package.repositories.rpm.key_url")
        local repo_file=$(get_module_config "vscode" ".vscode.package.repositories.rpm.repo_file")
        local repo_config=$(get_module_config "vscode" ".vscode.package.repositories.rpm.repo_config")

        sudo rpm --import "$key_url"
        echo -e "$repo_config" | sudo tee "$repo_file" > /dev/null
        
        if ! sudo dnf install -y code; then
            log "ERROR" "Failed to install VSCode via DNF" "vscode"
            return 1
        fi
    elif command -v apt-get &>/dev/null; then
        # DEB-based installation
        local key_url=$(get_module_config "vscode" ".vscode.package.repositories.deb.key_url")
        local key_path=$(get_module_config "vscode" ".vscode.package.repositories.deb.key_path")
        local repo_file=$(get_module_config "vscode" ".vscode.package.repositories.deb.repo_file")
        local repo_config=$(get_module_config "vscode" ".vscode.package.repositories.deb.repo_config")

        wget -qO- "$key_url" | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg "$key_path"
        rm packages.microsoft.gpg

        echo "$repo_config" | sudo tee "$repo_file" > /dev/null
        sudo apt-get update
        
        if ! sudo apt-get install -y code; then
            log "ERROR" "Failed to install VSCode via APT" "vscode"
            return 1
        fi
    else
        log "ERROR" "Unsupported package manager" "vscode"
        return 1
    fi

    return 0
}

# Configure VSCode settings
configure_vscode_settings() {
    log "INFO" "Configuring VSCode settings..." "vscode"

    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    local settings_file="$config_dir/settings.json"

    # Backup existing settings
    [[ -f "$settings_file" ]] && backup_file "$settings_file" "vscode"

    # Get settings from config and write to file
    local settings=$(get_module_config "vscode" ".vscode.settings")
    echo "$settings" > "$settings_file"

    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to write VSCode settings" "vscode"
        return 1
    fi

    return 0
}

# Install VSCode extensions
install_vscode_extensions() {
    log "INFO" "Installing VSCode extensions..." "vscode"

    local installed_extensions=$(code --list-extensions 2>/dev/null)
    local install_failed=false

    # Function to install extension with retry
    install_extension() {
        local extension=$1
        local required=$2
        local max_attempts=3
        local attempt=1

        while [ $attempt -le $max_attempts ]; do
            if code --install-extension "$extension" --force; then
                log "INFO" "Installed extension: $extension" "vscode"
                return 0
            else
                log "WARN" "Failed to install extension $extension (attempt $attempt/$max_attempts)" "vscode"
                ((attempt++))
                sleep 2
            fi
        done

        if [ "$required" = true ]; then
            log "ERROR" "Failed to install required extension: $extension" "vscode"
            return 1
        else
            log "WARN" "Skipping optional extension: $extension" "vscode"
            return 0
        fi
    }

    # Install extensions by category
    local categories=(development build containers web python)
    for category in "${categories[@]}"; do
        log "INFO" "Installing $category extensions..." "vscode"
        
        local extensions=($(get_module_config "vscode" ".vscode.extensions.$category[].id"))
        for ext_id in "${extensions[@]}"; do
            local required=$(get_module_config "vscode" ".vscode.extensions.$category[] | select(.id == \"$ext_id\") | .required")

            if ! echo "$installed_extensions" | grep -qi "^${ext_id}$"; then
                if ! install_extension "$ext_id" "$required"; then
                    [ "$required" = true ] && install_failed=true
                fi
            else
                log "INFO" "Extension already installed: $ext_id" "vscode"
            fi
        done
    done

    if [ "$install_failed" = true ]; then
        log "ERROR" "Some required extensions failed to install" "vscode"
        return 1
    fi

    return 0
}

# Remove VSCode configuration
remove_vscode() {
    log "INFO" "Removing VSCode configuration..." "vscode"

    # Backup existing configurations
    for file in $(get_module_config "vscode" ".backup.paths[]"); do
        file=$(eval echo "$file")
        [[ -f "$file" ]] && backup_file "$file" "vscode"
    done

    # Remove VSCode configuration files
    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    rm -f "$config_dir/settings.json" "$config_dir/keybindings.json"

    # Remove aliases
    remove_module_aliases "vscode" "editor"

    # Optionally uninstall extensions
    log "WARN" "Extensions were preserved. Use 'code --uninstall-extension' to remove specific extensions." "vscode"

    return 0
}

# Verify VSCode installation and configuration
verify_vscode() {
    log "INFO" "Verifying VSCode installation..." "vscode"
    local status=0

    # Check VSCode installation
    if ! command -v code &>/dev/null; then
        log "ERROR" "VSCode is not installed" "vscode"
        status=1
    fi

    # Check configuration directory and files
    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")

    if [[ ! -d "$config_dir" ]]; then
        log "ERROR" "VSCode configuration directory not found" "vscode"
        status=1
    fi

    if [[ ! -f "$config_dir/settings.json" ]]; then
        log "ERROR" "VSCode settings file not found" "vscode"
        status=1
    fi

    # Verify required extensions
    if command -v code &>/dev/null; then
        local installed_extensions=$(code --list-extensions 2>/dev/null)
        local categories=(development build containers web python)

        for category in "${categories[@]}"; do
            local extensions=($(get_module_config "vscode" ".vscode.extensions.$category[].id"))
            for ext_id in "${extensions[@]}"; do
                local required=$(get_module_config "vscode" ".vscode.extensions.$category[] | select(.id == \"$ext_id\") | .required")
                
                if [[ "$required" == "true" ]] && ! echo "$installed_extensions" | grep -qi "^${ext_id}$"; then
                    log "ERROR" "Required extension not installed: $ext_id" "vscode"
                    status=1
                fi
            done
        done
    fi

    # Verify aliases
    if ! list_module_aliases "vscode" "editor" &>/dev/null; then
        log "ERROR" "VSCode aliases not configured" "vscode"
        status=1
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_vscode
        ;;
    install)
        install_vscode
        ;;
    remove)
        remove_vscode
        ;;
    verify)
        verify_vscode
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "vscode"
        exit 1
        ;;
esac
