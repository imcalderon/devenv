#!/bin/bash
# modules/vscode/vscode.sh - VSCode module implementation with state management

# Load required utilities
source "$SCRIPT_DIR/compat.sh"   # Cross-platform compatibility
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/alias.sh"    # For shell alias support

# Initialize module
init_module "vscode" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/vscode.state"

# Components list for module
COMPONENTS=(
    "core"          # Base VSCode installation
    "settings"      # VSCode settings configuration
    "extensions"    # VSCode extensions
    "fonts"         # Terminal fonts
    "config"        # Additional configurations
)

# Display module information
show_module_info() {
    cat << 'EOF'

💻 Visual Studio Code Development Environment
========================================

Description:
-----------
Professional VSCode setup with optimized settings, essential extensions,
and integrations for Python, Docker, and remote development.

Benefits:
--------
✓ Pre-configured Development Environment - Ready for Python, Docker, and remote work
✓ Integrated Debugging - Launch configurations for various scenarios
✓ Code Quality Tools - Linting, formatting, and type checking integration
✓ Remote Development - Container and SSH development support
✓ Source Control - Enhanced Git integration

Components:
----------
1. Core VSCode
   - Latest stable release
   - Automatic updates
   - Command-line integration

2. Extensions
   - Python development
   - Container development
   - Remote development
   - Code quality tools
   - Web development

3. Settings
   - Optimized editor configuration
   - Language-specific settings
   - Terminal integration
   - Debug configurations

Quick Start:
-----------
1. Open VSCode:
   $ code .

2. Open settings:
   $ code --settings

3. Install extension:
   $ code --install-extension <id>

Aliases:
-------
code.  : Open current directory
codei  : Open with insiders build
coder  : Open with remote extension

Configuration:
-------------
Location: ~/.config/Code/User/
Key files:
- settings.json    : User settings
- keybindings.json : Custom key bindings
- launch.json      : Debug configurations

Tips:
----
• Use Ctrl+Shift+P for command palette
• Ctrl+` toggles integrated terminal
• Ctrl+P for quick file opening
• F5 for debugging

For more information:
-------------------
Documentation: https://code.visualstudio.com/docs
Marketplace: https://marketplace.visualstudio.com

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v code &>/dev/null; then
                        echo "  Version: $(code --version | head -n1)"
                    fi
                    ;;
                "extensions")
                    local ext_count=$(code --list-extensions | wc -l)
                    echo "  Installed extensions: $ext_count"
                    ;;
                "fonts")
                    if fc-list | grep -i "MesloLGM Nerd Font" >/dev/null; then
                        echo "  Nerd Fonts: Installed and active"
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

install_fonts() {
    log "INFO" "Installing Nerd Fonts for VSCode terminal..." "vscode"
    
    local fonts_dir="$HOME/.local/share/fonts"
    mkdir -p "$fonts_dir"
    local temp_dir=$(mktemp -d)
    local status=0

    # Download and install Meslo Nerd Font
    if ! command -v wget &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y wget
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y wget
        else
            log "ERROR" "Package manager not found for wget installation" "vscode"
            return 1
        fi
    fi

    # Download and extract fonts
    log "INFO" "Downloading Meslo Nerd Font..." "vscode"
    if ! wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/Meslo.zip" -P "$temp_dir"; then
        log "ERROR" "Failed to download Meslo font" "vscode"
        rm -rf "$temp_dir"
        return 1
    fi

    # Extract fonts
    log "INFO" "Extracting fonts..." "vscode"
    if ! unzip -q "$temp_dir/Meslo.zip" -d "$fonts_dir"; then
        log "ERROR" "Failed to extract fonts" "vscode"
        rm -rf "$temp_dir"
        return 1
    fi

    # Remove Windows-specific font files
    rm -f "$fonts_dir/"*Windows*

    # Update font cache
    log "INFO" "Updating font cache..." "vscode"
    if ! fc-cache -f "$fonts_dir"; then
        log "ERROR" "Failed to update font cache" "vscode"
        status=1
    fi

    # Cleanup
    rm -rf "$temp_dir"

    if [ $status -eq 0 ]; then
        log "INFO" "Nerd Fonts installation completed successfully" "vscode"
        save_state "fonts" "installed"
    fi

    return $status
}

# Verify fonts installation
verify_fonts() {
    log "INFO" "Verifying font installation..." "vscode"
    
    local fonts_dir="$HOME/.local/share/fonts"
    local required_fonts=(
        "MesloLGMNerdFont-Regular.ttf"
        "MesloLGMNerdFontMono-Regular.ttf"
    )
    
    # Check if font files exist
    for font in "${required_fonts[@]}"; do
        if ! ls "$fonts_dir"/*"$font" >/dev/null 2>&1; then
            log "DEBUG" "Missing font: $font" "vscode"
            return 1
        fi
    done

    # Verify font is recognized by system
    if ! fc-list | grep -i "MesloLGM Nerd Font" >/dev/null; then
        log "DEBUG" "Font not recognized by system" "vscode"
        return 1
    fi

    return 0
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            command -v code &>/dev/null
            ;;
        "settings")
            local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
            config_dir=$(echo "$config_dir" | expand_vars)
            [[ -f "$config_dir/settings.json" ]]
            ;;
        "extensions")
            verify_required_extensions
            ;;
        "fonts")
            verify_fonts
            ;;
        "config")
            verify_additional_config
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verify required extensions
verify_required_extensions() {
    local installed_extensions=$(code --list-extensions 2>/dev/null)
    local status=0

    # Function to check category extensions
    check_category_extensions() {
        local category=$1
        local query=".vscode.extensions.$category[]"
        
        local extensions=($(get_module_config "vscode" "$query" || echo ""))
        for extension in "${extensions[@]}"; do
            # Skip empty extensions
            [ -z "$extension" ] && continue
            
            # For extensions that are objects with id and required fields
            if [[ "$extension" == *"{"* ]]; then
                local ext_id=$(echo "$extension" | jq -r '.id')
                local required=$(echo "$extension" | jq -r '.required')
                
                if [[ "$required" == "true" ]] && ! echo "$installed_extensions" | grep -qi "^${ext_id}$"; then
                    log "DEBUG" "Missing required extension: $ext_id" "vscode"
                    return 1
                fi
            # For simple extension strings
            else
                if ! echo "$installed_extensions" | grep -qi "^${extension}$"; then
                    log "DEBUG" "Missing extension: $extension" "vscode"
                    return 1
                fi
            fi
        done
        return 0
    }

    # Check each category
    local categories=(development build containers web python)
    for category in "${categories[@]}"; do
        if ! check_category_extensions "$category"; then
            status=1
            break
        fi
    done

    return $status
}

# Verify additional configurations
verify_additional_config() {
    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(echo "$config_dir" | expand_vars)
    [[ -f "$config_dir/settings.json" ]] && \
    [[ -d "$(get_module_config "vscode" ".shell.paths.extensions_dir")" ]]
}
configure_vscode_settings() {
    log "INFO" "Configuring VSCode settings..." "vscode"

    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(echo "$config_dir" | expand_vars)
    local settings_file="$config_dir/settings.json"

    # Backup existing settings
    [[ -f "$settings_file" ]] && backup_file "$settings_file" "vscode"

    # Create config directory
    mkdir -p "$config_dir"

    # Get settings from config and write to file
    local settings=$(get_module_config "vscode" ".vscode.settings")
    
    if [[ -n "$settings" ]]; then
        # Expand environment variables in settings
        settings=$(echo "$settings" | expand_vars)
        echo "$settings" > "$settings_file"

        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to write VSCode settings" "vscode"
            return 1
        fi
    else
        log "ERROR" "No VSCode settings found in configuration" "vscode"
        return 1
    fi

    # Add launch configuration if specified
    local launch_config=$(get_module_config "vscode" ".vscode.launch")
    if [[ -n "$launch_config" ]]; then
        echo "$launch_config" > "$config_dir/launch.json"
    fi

    # Add tasks configuration if specified
    local tasks_config=$(get_module_config "vscode" ".vscode.tasks")
    if [[ -n "$tasks_config" ]]; then
        echo "$tasks_config" > "$config_dir/tasks.json"
    fi

    return 0
}

verify_required_extensions() {
    local installed_extensions=$(code --list-extensions 2>/dev/null)
    local status=0

    # Get all required extensions from config
    local extensions=($(get_module_config "vscode" ".vscode.extensions[]"))
    
    for extension in "${extensions[@]}"; do
        # Skip empty extensions
        [ -z "$extension" ] && continue
        
        if ! echo "$installed_extensions" | grep -qi "^${extension}$"; then
            log "DEBUG" "Missing extension: $extension" "vscode"
            status=1
        fi
    done

    return $status
}

# Install VSCode extensions
install_vscode_extensions() {
    log "INFO" "Installing VSCode extensions..." "vscode"
    local install_failed=false

    # Function to install extension with retry
    install_extension() {
        local extension=$1
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

        log "ERROR" "Failed to install extension: $extension" "vscode"
        return 1
    }

    # Get all extensions from config
    local extensions=($(get_module_config "vscode" ".vscode.extensions[]"))
    
    for extension in "${extensions[@]}"; do
        # Skip empty extensions
        [ -z "$extension" ] && continue
        
        if ! install_extension "$extension"; then
            install_failed=true
        fi
    done

    if [ "$install_failed" = true ]; then
        log "ERROR" "Some extensions failed to install" "vscode"
        return 1
    fi

    return 0
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "vscode"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_vscode_package; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "settings")
            if configure_vscode_settings; then
                save_state "settings" "installed"
                return 0
            fi
            ;;
        "extensions")
            if install_vscode_extensions; then
                save_state "extensions" "installed"
                return 0
            fi
            ;;
        "fonts")
            if install_fonts; then
                save_state "fonts" "installed"
                return 0
            fi
            ;;
        "config")
            if configure_additional; then
                save_state "config" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Configure additional settings
configure_additional() {
    # Add VSCode aliases
    add_module_aliases "vscode" "editor" || return 1
    
    # Create required directories
    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    local extensions_dir=$(get_module_config "vscode" ".shell.paths.extensions_dir")
    config_dir=$(echo "$config_dir" | expand_vars)
    extensions_dir=$(echo "$extensions_dir" | expand_vars)

    mkdir -p "$config_dir" "$extensions_dir"
    
    return 0
}

# Install VSCode package
install_vscode_package() {
    log "INFO" "Installing VSCode..." "vscode"

    if command -v dnf &>/dev/null; then
        # RPM-based installation
        log "INFO" "Using Microsoft's repository for VSCode (RPM)" "vscode"

        # Import Microsoft GPG key
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

        # Add the repository
        printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
            sudo tee /etc/yum.repos.d/vscode.repo

        # Install VSCode
        if ! sudo dnf install -y code; then
            log "ERROR" "Failed to install VSCode via DNF" "vscode"
            return 1
        fi

        log "INFO" "VSCode installation completed successfully" "vscode"
    elif command -v apt-get &>/dev/null; then
        # DEB-based installation - Updated approach
        log "INFO" "Using Microsoft's repository for VSCode" "vscode"
        
        # Install dependencies
        sudo apt-get update
        sudo apt-get install -y curl wget gpg apt-transport-https
        
        # Import Microsoft GPG key
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        rm -f packages.microsoft.gpg
        
        # Add the repository
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
            sudo tee /etc/apt/sources.list.d/vscode.list
        
        # Update and install
        sudo apt-get update
        if ! sudo apt-get install -y code; then
            log "ERROR" "Failed to install VSCode via APT" "vscode"
            return 1
        fi
        
        log "INFO" "VSCode installation completed successfully" "vscode"
    else
        log "ERROR" "Unsupported package manager" "vscode"
        return 1
    fi

    return 0
}

# Grovel checks existence and basic functionality
grovel_vscode() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "vscode"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_vscode() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_vscode &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "vscode"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "vscode"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "vscode"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Verify entire installation
verify_vscode() {
    log "INFO" "Verifying VSCode installation..." "vscode"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "vscode"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "VSCode verification completed successfully" "vscode"
    else
        log "ERROR" "VSCode verification failed" "vscode"
    fi

    return $status
}

remove_vscode() {
    log "INFO" "Removing VSCode configuration..." "vscode"

    # Backup existing configurations
    for file in $(get_module_config "vscode" ".backup.paths[]"); do
        file=$(echo "$file" | expand_vars)
        [[ -f "$file" ]] && backup_file "$file" "vscode"
    done

    # Remove VSCode configuration files
    local config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    config_dir=$(echo "$config_dir" | expand_vars)
    rm -f "$config_dir/settings.json" "$config_dir/keybindings.json"

    # Remove aliases
    remove_module_aliases "vscode" "editor"

    # Note about fonts (we don't remove them as they might be used by other applications)
    log "WARN" "Nerd Fonts were preserved. Remove manually from ~/.local/share/fonts if needed." "vscode"

    # Remove state file
    rm -f "$STATE_FILE"

    log "WARN" "Extensions were preserved. Use 'code --uninstall-extension' to remove specific extensions." "vscode"

    return 0
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_vscode
        ;;
    install)
        install_vscode "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_vscode
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_vscode
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "vscode"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac