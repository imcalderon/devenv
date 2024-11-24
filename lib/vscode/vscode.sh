#!/bin/bash
# lib/vscode/vscode.sh - VSCode module implementation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../logging.sh"
source "${SCRIPT_DIR}/../yaml_parser.sh"
source "${SCRIPT_DIR}/../module_base.sh"

grovel_vscode() {
    log "INFO" "Checking VSCode dependencies..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    if ! command -v ${config_modules_vscode_package_name} &> /dev/null; then
        log "INFO" "VSCode not found"
        return 1
    fi
}

install_vscode() {
    log "INFO" "Setting up VSCode environment..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Install VSCode if not present
    if ! command -v ${config_modules_vscode_package_name} &> /dev/null; then
        log "INFO" "Installing VSCode..."
        install_vscode_package
    fi
    
    # Configure VSCode settings
    configure_vscode_settings
    
    # Install extensions
    install_vscode_extensions
}

install_vscode_package() {
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    if command -v dnf &> /dev/null; then
        # RPM-based installation
        sudo rpm --import "${config_modules_vscode_repositories_rpm_key_url}"
        echo "${config_modules_vscode_repositories_rpm_repo_config}" | sudo tee /etc/yum.repos.d/vscode.repo
        sudo dnf install -y ${config_modules_vscode_package_name}
    elif command -v apt-get &> /dev/null; then
        # DEB-based installation
        wget -qO- "${config_modules_vscode_repositories_deb_key_url}" | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        echo "${config_modules_vscode_repositories_deb_repo_config}" | sudo tee /etc/apt/sources.list.d/vscode.list
        sudo apt-get update
        sudo apt-get install -y ${config_modules_vscode_package_name}
        rm packages.microsoft.gpg
    else
        log "ERROR" "Unsupported package manager"
        return 1
    fi
}

configure_vscode_settings() {
    log "INFO" "Configuring VSCode settings..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    local config_dir="$HOME/.config/Code/User"
    mkdir -p "$config_dir"
    
    # Backup existing settings
    backup_file "$config_dir/settings.json"
    
    # Build settings JSON dynamically
    local settings_json="{"
    local first=true
    
    # Loop through all settings in config
    for setting in "${config_modules_vscode_settings_editor[@]}"; do
        key="${setting[key]}"
        value="${setting[value]}"
        
        if [ "$first" = true ]; then
            first=false
        else
            settings_json+=","
        fi
        
        # Handle array values
        if [[ "$value" == \[* ]]; then
            settings_json+="\"$key\": $value"
        else
            settings_json+="\"$key\": \"$value\""
        fi
    done
    
    settings_json+="}"
    
    echo "$settings_json" > "$config_dir/settings.json"
    log "INFO" "VSCode settings configured"
}

install_vscode_extensions() {
    log "INFO" "Installing VSCode extensions..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    local installed_extensions=$(code --list-extensions 2>/dev/null)
    
    # Loop through extension categories
    for category in development build containers web python; do
        local extensions_array="config_modules_vscode_extensions_${category}[@]"
        
        for extension in "${!extensions_array}"; do
            local ext_id="${extension[id]}"
            local required="${extension[required]}"
            
            if ! echo "$installed_extensions" | grep -qi "^${ext_id}$"; then
                log "INFO" "Installing extension: ${ext_id}"
                code --install-extension "$ext_id" --force
            else
                log "INFO" "Extension already installed: ${ext_id}"
            fi
        done
    done
    
    code --update-extensions
}

remove_vscode() {
    log "INFO" "Removing VSCode configuration..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Restore settings backup
    restore_backup "$HOME/.config/Code/User/settings.json"
    
    # Remove extensions
    if command -v code >/dev/null; then
        for category in development build containers web python; do
            local extensions_array="config_modules_vscode_extensions_${category}[@]"
            
            for extension in "${!extensions_array}"; do
                local ext_id="${extension[id]}"
                log "INFO" "Removing extension: ${ext_id}"
                code --uninstall-extension "$ext_id"
            done
        done
    fi
}

verify_vscode() {
    log "INFO" "Verifying VSCode installation..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Check VSCode installation
    if ! command -v ${config_modules_vscode_package_name} &> /dev/null; then
        log "ERROR" "VSCode is not installed"
        return 1
    fi
    
    # Check settings file
    if [ ! -f "$HOME/.config/Code/User/settings.json" ]; then
        log "ERROR" "Settings file not found"
        return 1
    fi
    
    # Verify required extensions
    local installed_extensions=$(code --list-extensions 2>/dev/null)
    local verification_failed=false
    
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
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "VSCode verification complete"
    return 0
}

update_vscode() {
    log "INFO" "Updating VSCode environment..."
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Update VSCode package
    if command -v dnf &> /dev/null; then
        sudo dnf update -y ${config_modules_vscode_package_name}
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get upgrade -y ${config_modules_vscode_package_name}
    fi
    
    # Update extensions
    code --update-extensions
    
    # Reconfigure settings
    configure_vscode_settings
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update}"
        exit 1
    fi
    module_base "$1" "vscode"
fi