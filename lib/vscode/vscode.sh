#!/bin/bash
# lib/vscode/vscode.sh - VSCode module implementation

# Use environment variables set by devenv.sh, with fallback if running standalone
if [ -z "${ROOT_DIR:-}" ]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Source dependencies using SCRIPT_DIR
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/module_base.sh"

grovel_vscode() {
    log "INFO" "Checking VSCode dependencies..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    if ! command -v ${config_modules_vscode_package_name} &> /dev/null; then
        log "INFO" "VSCode not found"
        return 1
    fi
}

install_vscode() {
    log "INFO" "Setting up VSCode environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Install VSCode if not present
    if ! command -v ${config_modules_vscode_package_name} &> /dev/null; then
        log "INFO" "Installing VSCode..."
        if ! install_vscode_package; then
            return 1
        fi
    fi
    
    # Create required directories
    mkdir -p "${config_modules_vscode_paths_config_dir}"
    mkdir -p "${config_modules_vscode_paths_extensions_dir}"
    
    # Configure VSCode settings
    if ! configure_vscode_settings; then
        return 1
    fi
    
    # Configure keybindings
    if ! configure_vscode_keybindings; then
        return 1
    fi
    
    # Install extensions
    if ! install_vscode_extensions; then
        return 1
    fi
    
    return 0
}

install_vscode_package() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    if command -v dnf &> /dev/null; then
        # RPM-based installation
        log "INFO" "Installing VSCode via RPM..."
        sudo rpm --import "${config_modules_vscode_package_repositories_rpm_key_url}"
        echo "${config_modules_vscode_package_repositories_rpm_repo_config}" | \
            sudo tee "${config_modules_vscode_package_repositories_rpm_repo_file}" > /dev/null
        
        if ! sudo dnf install -y ${config_modules_vscode_package_name}; then
            log "ERROR" "Failed to install VSCode via DNF"
            return 1
        fi
    elif command -v apt-get &> /dev/null; then
        # DEB-based installation
        log "INFO" "Installing VSCode via APT..."
        wget -qO- "${config_modules_vscode_package_repositories_deb_key_url}" | \
            gpg --dearmor > packages.microsoft.gpg
        
        if ! sudo install -o root -g root -m 644 packages.microsoft.gpg "${config_modules_vscode_package_repositories_deb_key_path}"; then
            log "ERROR" "Failed to install Microsoft GPG key"
            rm packages.microsoft.gpg
            return 1
        fi
        
        echo "${config_modules_vscode_package_repositories_deb_repo_config}" | \
            sudo tee "${config_modules_vscode_package_repositories_deb_repo_file}" > /dev/null
        
        sudo apt-get update
        if ! sudo apt-get install -y ${config_modules_vscode_package_name}; then
            log "ERROR" "Failed to install VSCode via APT"
            return 1
        fi
        rm packages.microsoft.gpg
    else
        log "ERROR" "Unsupported package manager"
        return 1
    fi
    
    return 0
}

configure_vscode_settings() {
    log "INFO" "Configuring VSCode settings..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local settings_file="${config_modules_vscode_paths_config_dir}/settings.json"
    backup_file "$settings_file"
    
    # Build settings JSON
    local settings_json="{\n"
    local first=true
    
    # Process all editor settings
    for setting in "${config_modules_vscode_settings_editor[@]}"; do
        local key="${setting[key]}"
        local value="${setting[value]}"
        
        if [ "$first" = true ]; then
            first=false
        else
            settings_json+=",\n"
        fi
        
        # Handle array values
        if [[ "$value" == \[* ]]; then
            settings_json+="    \"$key\": $value"
        else
            settings_json+="    \"$key\": \"$value\""
        fi
    done
    
    settings_json+="\n}"
    
    echo -e "$settings_json" > "$settings_file"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to write VSCode settings"
        return 1
    fi
    
    log "INFO" "VSCode settings configured successfully"
    return 0
}

configure_vscode_keybindings() {
    log "INFO" "Configuring VSCode keybindings..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local keybindings_file="${config_modules_vscode_paths_config_dir}/keybindings.json"
    backup_file "$keybindings_file"
    
    # Create default keybindings if none exist
    if [ ! -f "$keybindings_file" ]; then
        echo "[]" > "$keybindings_file"
    fi
    
    log "INFO" "VSCode keybindings configured successfully"
    return 0
}

install_vscode_extensions() {
    log "INFO" "Installing VSCode extensions..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
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
                log "INFO" "Installed extension: $extension"
                return 0
            else
                log "WARN" "Failed to install extension $extension (attempt $attempt/$max_attempts)"
                ((attempt++))
                sleep 2
            fi
        done
        
        if [ "$required" = true ]; then
            log "ERROR" "Failed to install required extension: $extension"
            return 1
        else
            log "WARN" "Skipping optional extension: $extension"
            return 0
        fi
    }
    
    # Install extensions by category
    for category in development build containers web python; do
        log "INFO" "Installing $category extensions..."
        local extensions_array="config_modules_vscode_extensions_${category}[@]"
        
        for extension in "${!extensions_array}"; do
            local ext_id="${extension[id]}"
            local required="${extension[required]}"
            
            if ! echo "$installed_extensions" | grep -qi "^${ext_id}$"; then
                if ! install_extension "$ext_id" "$required"; then
                    [ "$required" = true ] && install_failed=true
                fi
            else
                log "INFO" "Extension already installed: ${ext_id}"
            fi
        done
    done
    
    if [ "$install_failed" = true ]; then
        log "ERROR" "Some required extensions failed to install"
        return 1
    fi
    
    # Update all extensions
    if ! code --update-extensions; then
        log "WARN" "Failed to update some extensions"
    fi
    
    return 0
}

remove_vscode() {
    log "INFO" "Removing VSCode configuration..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Restore configurations from backup
    restore_backup "${config_modules_vscode_paths_config_dir}/settings.json"
    restore_backup "${config_modules_vscode_paths_config_dir}/keybindings.json"
    
    # Remove extensions
    if command -v code >/dev/null; then
        for category in development build containers web python; do
            local extensions_array="config_modules_vscode_extensions_${category}[@]"
            
            for extension in "${!extensions_array}"; do
                local ext_id="${extension[id]}"
                log "INFO" "Removing extension: ${ext_id}"
                code --uninstall-extension "$ext_id" || true
            done
        done
    fi
    
    return 0
}

verify_vscode() {
    log "INFO" "Verifying VSCode installation..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local verification_failed=false
    
    # Check VSCode installation
    if ! command -v ${config_modules_vscode_package_name} &> /dev/null; then
        log "ERROR" "VSCode is not installed"
        verification_failed=true
    fi
    
    # Check configuration directory
    if [ ! -d "${config_modules_vscode_paths_config_dir}" ]; then
        log "ERROR" "VSCode configuration directory not found"
        verification_failed=true
    fi
    
    # Check settings file
    if [ ! -f "${config_modules_vscode_paths_config_dir}/settings.json" ]; then
        log "ERROR" "VSCode settings file not found"
        verification_failed=true
    fi
    
    # Check keybindings file
    if [ ! -f "${config_modules_vscode_paths_config_dir}/keybindings.json" ]; then
        log "ERROR" "VSCode keybindings file not found"
        verification_failed=true
    fi
    
    # Verify required extensions
    if command -v code >/dev/null; then
        local installed_extensions=$(code --list-extensions 2>/dev/null)
        
        for category in development build containers web python; do
            local extensions_array="config_modules_vscode_extensions_${category}[@]"
            
            for extension in "${!extensions_array}"; do
                local ext_id="${extension[id]}"
                local required="${extension[required]}"
                
                if [ "$required" = true ] && ! echo "$installed_extensions" | grep -qi "^${ext_id}$"; then
                    log "ERROR" "Required extension not installed: ${ext_id}"
                    verification_failed=true
                fi
            done
        done
    else
        log "ERROR" "VSCode command not found"
        verification_failed=true
    fi
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "VSCode verification complete"
    return 0
}

update_vscode() {
    log "INFO" "Updating VSCode environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Update VSCode package
    if command -v dnf &> /dev/null; then
        sudo dnf update -y ${config_modules_vscode_package_name}
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get upgrade -y ${config_modules_vscode_package_name}
    fi
    
    # Update extensions
    if ! code --update-extensions; then
        log "WARN" "Failed to update some extensions"
    fi
    
    # Reconfigure with latest settings
    configure_vscode_settings
    configure_vscode_keybindings
    
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update}"
        exit 1
    fi
    module_base "$1" "vscode"
fi