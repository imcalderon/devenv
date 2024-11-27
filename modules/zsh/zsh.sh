#!/bin/bash
# modules/zsh/zsh.sh - ZSH module implementation with state management

# Load required utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/alias.sh"    # For shell alias support

# Initialize module
init_module "zsh" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/zsh.state"

# Components list for module
COMPONENTS=(
    "core"          # Base ZSH installation
    "oh-my-zsh"     # Oh My ZSH framework
    "powerlevel10k" # Theme
    "plugins"       # ZSH plugins
    "fonts"         # Required fonts
    "config"        # ZSH configuration
)

# Display module information
show_module_info() {
    cat << 'EOF'

🛠️ ZSH Development Environment
===========================

Description:
-----------
Professional ZSH shell environment with Oh My ZSH framework, 
Powerlevel10k theme, and curated plugins for enhanced productivity.

Benefits:
--------
✓ Enhanced Productivity - Rich command line features and auto-completion
✓ Visual Appeal - Modern, informative Powerlevel10k theme
✓ Plugin Power - Git, docker, and development tool integrations
✓ Custom Aliases - Streamlined common operations
✓ Smart Completion - Context-aware command suggestions

Components:
----------
1. Core ZSH
   - Modern shell replacement for bash
   - Advanced command line editing
   - Improved tab completion

2. Oh My ZSH Framework
   - Plugin management
   - Theme support
   - Configuration organization

3. Powerlevel10k Theme
   - Git status integration
   - Command execution time
   - Directory context
   - Server status indicators

4. Essential Plugins
   - Git integration
   - Docker commands
   - Syntax highlighting
   - Auto-suggestions

Quick Start:
-----------
1. Reload shell configuration:
   $ source ~/.zshrc

2. Edit configuration:
   $ zshconfig

3. Update Oh My ZSH:
   $ omz update

Aliases:
-------
zshconfig : Edit ZSH configuration
ohmyzsh  : Open Oh My ZSH directory
reload   : Reload ZSH configuration

Configuration:
-------------
Location: ~/.zshrc
Key files:
- ~/.zshrc          : Main configuration
- ~/.p10k.zsh       : Theme configuration
- ~/.oh-my-zsh/     : Framework directory

Tips:
----
• Use 'Tab' for smart completion
• Press Up/Down for history search
• Use 'Alt+L' for ls after cd
• Right arrow accepts suggestions

Requirements:
------------
• MesloLGS NF Font - Required for icons
• Git - For repository features
• Terminal with Unicode support

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v zsh &>/dev/null; then
                        echo "  Version: $(zsh --version | cut -d' ' -f2)"
                    fi
                    ;;
                "oh-my-zsh")
                    local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
                    omz_path=$(eval echo "$omz_path")
                    if [[ -d "$omz_path" ]]; then
                        echo "  Location: $omz_path"
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
            command -v zsh &>/dev/null
            ;;
        "oh-my-zsh")
            local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
            omz_path=$(eval echo "$omz_path")
            [[ -d "$omz_path" ]]
            ;;
        "powerlevel10k")
            local themes_dir=$(get_module_config "zsh" ".shell.paths.themes_dir")
            themes_dir=$(eval echo "$themes_dir")
            [[ -d "$themes_dir/powerlevel10k" ]]
            ;;
        "plugins")
            verify_plugins
            ;;
        "fonts")
            verify_fonts
            ;;
        "config")
            [[ -f "$HOME/.zshrc" ]] && [[ -f "$HOME/.p10k.zsh" ]]
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verify plugins
verify_plugins() {
    local plugins_dir=$(get_module_config "zsh" ".shell.paths.plugins_dir")
    plugins_dir=$(eval echo "$plugins_dir")
    local plugins=($(get_module_config "zsh" ".shell.plugins[]"))
    
    for plugin in "${plugins[@]}"; do
        if [[ ! -d "$plugins_dir/$plugin" ]]; then
            return 1
        fi
    done
    return 0
}

# Verify fonts
verify_fonts() {
    local fonts_dir="$HOME/.local/share/fonts"
    local font_files=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )
    
    for font in "${font_files[@]}"; do
        if [[ ! -f "$fonts_dir/$font" ]]; then
            return 1
        fi
    done
    return 0
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "zsh"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_zsh_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "oh-my-zsh")
            if install_oh_my_zsh; then
                save_state "oh-my-zsh" "installed"
                return 0
            fi
            ;;
        "powerlevel10k")
            if install_powerlevel10k; then
                save_state "powerlevel10k" "installed"
                return 0
            fi
            ;;
        "plugins")
            if install_plugins; then
                save_state "plugins" "installed"
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
            if configure_zsh; then
                save_state "config" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Install core ZSH
install_zsh_core() {
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
    return 0
}

# Install Oh My ZSH
install_oh_my_zsh() {
    local omz_path=$(get_module_config "zsh" ".shell.paths.oh_my_zsh")
    omz_path=$(eval echo "$omz_path")

    if [[ ! -d "$omz_path" ]]; then
        log "INFO" "Installing oh-my-zsh..." "zsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    return 0
}

# Install Powerlevel10k
install_powerlevel10k() {
    local themes_dir=$(get_module_config "zsh" ".shell.paths.themes_dir")
    themes_dir=$(eval echo "$themes_dir")
    local p10k_dir="$themes_dir/powerlevel10k"

    if [[ ! -d "$p10k_dir" ]]; then
        log "INFO" "Installing Powerlevel10k theme..." "zsh"
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    fi

    if [[ ! -f "$HOME/.p10k.zsh" ]]; then
        curl -fsSL https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-rainbow.zsh -o "$HOME/.p10k.zsh"
    fi
    return 0
}

# Install plugins
install_plugins() {
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

# Install fonts
install_fonts() {
    log "INFO" "Installing Meslo Nerd Font..." "zsh"
    
    local fonts_dir="$HOME/.local/share/fonts"
    mkdir -p "$fonts_dir"
    
    local font_urls=(
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
        "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
    )
    
    for url in "${font_urls[@]}"; do
        local filename=$(basename "$url" | sed 's/%20/ /g')
        if [[ ! -f "$fonts_dir/$filename" ]]; then
            curl -fL "$url" -o "$fonts_dir/$filename"
        fi
    done
    
    fc-cache -f "$fonts_dir"
    return 0
}

# Grovel checks existence and basic functionality
grovel_zsh() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "zsh"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_zsh() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_zsh &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "zsh"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "zsh"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "zsh"
        fi
    done
    
    # Add zsh's own aliases
    add_module_aliases "zsh" "shell" || return 1
    
    # Show module information after successful installation
    show_module_info
    
    # Set zsh as default shell if it isn't already
    if [[ "$SHELL" != "/bin/zsh" ]]; then
        chsh -s "$(command -v zsh)"
        log "INFO" "Shell changed to zsh. Please log out and back in for changes to take effect." "zsh"
    fi
    
    return 0
}
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
# Remove ZSH configuration
remove_zsh() {
    log "INFO" "Removing ZSH configuration..." "zsh"
    
    # Backup existing configs before removal
    for file in "$HOME/.zshrc" "$HOME/.p10k.zsh"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" "zsh"
        fi
    done
    
    # Remove state file
    rm -f "$STATE_FILE"
    
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
    
    # Remove aliases
    remove_module_aliases "zsh" "shell"
    
    log "INFO" "ZSH configuration removed" "zsh"
    return 0
}

# Verify entire installation
verify_zsh() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "zsh"
            status=1
        fi
    done
    
    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_zsh
        ;;
    install)
        install_zsh "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_zsh
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_zsh
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "zsh"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac
