#!/bin/bash
# modules/zsh/zsh.sh - ZSH module implementation

# Load required utilities
# Load utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # backup utilities
source "$SCRIPT_DIR/alias.sh"    # For add alias to shell support

# Initialize module
init_module "zsh" || exit 1

# Check for zsh and oh-my-zsh installation
grovel_zsh() {
    if ! command -v zsh &>/dev/null; then
        log "INFO" "zsh not found" "zsh"
        return 1
    fi

    local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
    omz_path=$(eval echo "$omz_path")
    
    if [[ ! -d "$omz_path" ]]; then
        log "INFO" "oh-my-zsh not found" "zsh"
        return 1
    fi

    return 0
}

# Install zsh and configure
install_zsh() {
    # Install zsh if needed
    if ! command -v zsh &>/dev/null; then
        log "INFO" "Installing zsh..." "zsh"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y zsh curl git fontconfig
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y zsh curl git fontconfig
        else
            log "ERROR" "Unsupported package manager" "zsh"
            return 1
        fi
    fi

    # Install fonts first
    install_fonts || return 1
    
    # Install oh-my-zsh 
    install_oh_my_zsh || return 1

    # Then configure zsh (which includes setting up the alias structure)
    configure_zsh || return 1

    # Finally install custom plugins
    install_custom_plugins || return 1
    
    
   # Set zsh as default shell if it isn't already
    if [[ "$SHELL" != "/bin/zsh" ]]; then
        log "INFO" "Setting zsh as default shell..." "zsh"
        local zsh_path=$(command -v zsh)
        if ! grep -q "$zsh_path" /etc/shells; then
            log "INFO" "Adding zsh to /etc/shells..." "zsh"
            echo "$zsh_path" | sudo tee -a /etc/shells
        fi
        chsh -s "$zsh_path"
        
        # Show setup instructions
        show_terminal_instructions

        # Notify user about shell change
        log "INFO" "Shell changed to zsh. Changes will take effect after restarting your terminal." "zsh"
        
        
        
        # If we're in an interactive shell, offer to switch now
        if [[ -t 0 && -t 1 ]]; then
            log "INFO" "Would you like to switch to zsh now? (y/n)" "zsh"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                log "INFO" "Launching zsh..." "zsh"
                exec zsh -l
            else
                log "INFO" "Please restart your terminal to use zsh" "zsh"
            fi
        fi
    fi
    return 0
}


# Install oh-my-zsh
install_oh_my_zsh() {
    local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
    omz_path=$(eval echo "$omz_path")

    if [[ ! -d "$omz_path" ]]; then
        log "INFO" "Installing oh-my-zsh..." "zsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # Install Powerlevel10k theme
    local themes_dir=$(get_module_config "zsh" ".shell.paths.themes_dir")
    themes_dir=$(eval echo "$themes_dir")
    local p10k_dir="$themes_dir/powerlevel10k"

    if [[ ! -d "$p10k_dir" ]]; then
        log "INFO" "Installing Powerlevel10k theme..." "zsh"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi

    # Download p10k config if it doesn't exist
    if [[ ! -f "$HOME/.p10k.zsh" ]]; then
        log "INFO" "Setting up default p10k configuration..." "zsh"
        curl -fsSL https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-rainbow.zsh -o "$HOME/.p10k.zsh"
    fi

    return 0
}
install_fonts() {
    log "INFO" "Installing Meslo Nerd Font..." "zsh"
    
    # Create fonts directory
    local fonts_dir="$HOME/.local/share/fonts"
    mkdir -p "$fonts_dir"
    
    # Font files to download
    local font_urls=(
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    )
    
    # Download and install fonts
    for url in "${font_urls[@]}"; do
        local filename=$(basename "$url" | sed 's/%20/ /g')
        if [[ ! -f "$fonts_dir/$filename" ]]; then
            log "INFO" "Downloading font: $filename" "zsh"
            curl -fL "$url" -o "$fonts_dir/$filename"
        fi
    done
    
    # Update font cache
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$fonts_dir"
    fi
    
    log "INFO" "Font installation complete. Please configure your terminal to use 'MesloLGS NF' font" "zsh"
    return 0
}
# Configure zsh
configure_zsh() {
    log "INFO" "Configuring zsh..." "zsh"

    # Backup existing config
    backup_file "$HOME/.zshrc" "zsh"

    # Create custom directories
    local custom_dir=$(get_module_config "zsh" ".shell.paths.custom_dir")
    local modules_dir=$(get_module_config "zsh" ".shell.paths.modules_dir")
    custom_dir=$(eval echo "$custom_dir")
    modules_dir=$(eval echo "$modules_dir")

    mkdir -p "$custom_dir" "$modules_dir"

    # Create base zshrc
    cat > "$HOME/.zshrc" << 'EOF'
# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme configuration
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugin configuration
plugins=(
EOF

    # Add plugins from config
    local plugins=($(get_module_config "zsh" ".shell.plugins[]"))
    for plugin in "${plugins[@]}"; do
        echo "    $plugin" >> "$HOME/.zshrc"
    done

    # Complete zshrc
    cat >> "$HOME/.zshrc" << 'EOF'
)

# Load oh-my-zsh
source $ZSH/oh-my-zsh.sh

# Load module configurations
for config_file in $ZSH/custom/modules/*.zsh; do
    [ -f "$config_file" ] && source "$config_file"
done

# Load Powerlevel10k configuration
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# User configuration
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
EOF

    # Create modules directory for other modules to add their configs
    mkdir -p "$modules_dir"
    touch "$modules_dir/aliases.zsh"
    touch "$modules_dir/functions.zsh"

    # Add zsh's own aliases
    log "INFO" "Setting up zsh aliases..." "zsh"
    add_module_aliases "zsh" "shell"

    return 0
}
# Install custom plugins
install_custom_plugins() {
    log "INFO" "Installing custom plugins..." "zsh"

    local plugins_dir=$(get_module_config "zsh" ".shell.paths.plugins_dir")
    plugins_dir=$(eval echo "$plugins_dir")
    mkdir -p "$plugins_dir"

    local custom_plugins=($(get_module_config "zsh" ".shell.custom_plugins | keys[]"))
    for plugin in "${custom_plugins[@]}"; do
        local repo=$(get_module_config "zsh" ".shell.custom_plugins[\"$plugin\"]")
        local plugin_dir="$plugins_dir/$plugin"

        if [[ ! -d "$plugin_dir" ]]; then
            git clone --depth 1 "$repo" "$plugin_dir"
        fi
    done

    return 0
}
show_terminal_instructions() {
    cat << 'EOF'

🎨 Terminal Font Configuration Instructions
=========================================

To see all Powerlevel10k icons correctly, configure your terminal to use the
newly installed 'MesloLGS NF' font:

GNOME Terminal (Default on Ubuntu/Fedora):
  1. Edit → Preferences → Profile
  2. Check "Custom font" under Text Appearance
  3. Click font button and search for "MesloLGS NF"
  4. Select "MesloLGS NF Regular"

Konsole (KDE):
  1. Settings → Edit Current Profile
  2. Click "Appearance" tab
  3. Select "MesloLGS NF" from Font dropdown

VSCode Terminal:
  1. Open Settings (Ctrl+,)
  2. Search for "terminal font"
  3. Set "Terminal › Integrated: Font Family" to "MesloLGS NF"

Other Terminal Tips:
  - If icons still look wrong after font change, restart your terminal
  - Make sure antialiasing is enabled in your terminal settings
  - For other terminals, look for "Font" or "Appearance" in preferences
  - "MesloLGS NF" to vscode terminal too
Next Steps:
  1. Restart your terminal or run: exec zsh
  2. Configure Powerlevel10k when prompted

EOF
}

# Remove zsh configuration
remove_zsh() {
    log "INFO" "Removing zsh configuration..." "zsh"
    
    # Backup existing configs before removal
    for file in "$HOME/.zshrc" "$HOME/.p10k.zsh"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" "zsh"
        fi
    done
    
    # Get oh-my-zsh path from config
    local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
    omz_path=$(eval echo "$omz_path")
    
    # Remove all zsh-related files and directories
    local files_to_remove=(
        "$HOME/.zshrc"
        "$HOME/.p10k.zsh"
        "$omz_path"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            log "INFO" "Removing $file" "zsh"
            rm -rf "$file"
        fi
    done
    
    log "INFO" "zsh configuration removed" "zsh"
    return 0
}


# Verify zsh configuration
verify_zsh() {
    log "INFO" "Verifying zsh installation..." "zsh"
    
    if ! command -v zsh &>/dev/null; then
        log "ERROR" "zsh is not installed" "zsh"
        return 1
    fi
    
    local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
    omz_path=$(eval echo "$omz_path")
    
    if [[ ! -d "$omz_path" ]]; then
        log "ERROR" "oh-my-zsh is not installed" "zsh"
        return 1
    fi
    
    if [[ ! -f "$HOME/.zshrc" ]]; then
        log "ERROR" "zshrc configuration not found" "zsh"
        return 1
    fi
    
    local modules_dir=$(get_module_config "zsh" ".shell.paths.modules_dir")
    modules_dir=$(eval echo "$modules_dir")
    
    if [[ ! -d "$modules_dir" ]]; then
        log "ERROR" "modules directory not found" "zsh"
        return 1
    fi
    
    local aliases_dir=$(get_aliases_dir)
    if [[ ! -f "$aliases_dir/aliases.zsh" ]]; then
        log "ERROR" "Aliases file not found" "zsh"
        return 1
    fi  

    return 0
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_zsh
        ;;
    install)
        install_zsh
        ;;
    remove)
        remove_zsh
        ;;
    verify)
        verify_zsh
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "zsh"
        exit 1
        ;;
esac
