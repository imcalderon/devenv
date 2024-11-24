#!/bin/bash
# lib/zsh/zsh.sh - ZSH module implementation

# Use environment variables set by devenv.sh, with fallback if running standalone
if [ -z "${ROOT_DIR:-}" ]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Source dependencies using SCRIPT_DIR
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/module_base.sh"

grovel_zsh() {
    log "INFO" "Checking ZSH dependencies..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local verification_failed=false
    
    # Check ZSH installation
    if ! command -v zsh &> /dev/null; then
        log "INFO" "ZSH not found"
        verification_failed=true
    fi
    
    # Check Oh My ZSH installation
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Oh My ZSH not found"
        verification_failed=true
    fi
    
    # Check custom directories
    local custom_dirs=(
        "${config_modules_zsh_paths_custom_dir}"
        "${config_modules_zsh_paths_plugins_dir}"
        "${config_modules_zsh_paths_themes_dir}"
        "${config_modules_zsh_paths_completions_dir}"
    )
    
    for dir in "${custom_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log "INFO" "Custom directory not found: $dir"
            verification_failed=true
        fi
    done
    
    [ "$verification_failed" = true ] && return 1
    return 0
}

install_zsh() {
    log "INFO" "Setting up ZSH environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Install ZSH if not present
    if ! command -v zsh &> /dev/null; then
        install_zsh_package || return 1
    fi
    
    # Install Oh My ZSH if not present
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        install_oh_my_zsh || return 1
    fi
    
    # Create custom directories
    create_custom_directories || return 1
    
    # Install Powerlevel10k theme
    install_powerlevel10k || return 1
    
    # Install custom plugins
    install_custom_plugins || return 1
    
    # Configure ZSH
    configure_zsh || return 1
    
    # Set ZSH as default shell if it isn't already
    if [[ $SHELL != *"zsh"* ]]; then
        log "INFO" "Setting ZSH as default shell..."
        chsh -s "$(which zsh)" "$(whoami)" || {
            log "ERROR" "Failed to set ZSH as default shell"
            return 1
        }
    fi
    
    return 0
}

install_zsh_package() {
    log "INFO" "Installing ZSH..."
    
    if command -v dnf &> /dev/null; then
        sudo dnf install -y zsh util-linux-user || return 1
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zsh || return 1
    else
        log "ERROR" "Unsupported package manager"
        return 1
    fi
    
    log "INFO" "ZSH installed successfully"
    return 0
}

install_oh_my_zsh() {
    log "INFO" "Installing Oh My ZSH..."
    
    # Download and install Oh My ZSH
    if ! sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
        log "ERROR" "Failed to install Oh My ZSH"
        return 1
    fi
    
    return 0
}

create_custom_directories() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local custom_dirs=(
        "${config_modules_zsh_paths_custom_dir}"
        "${config_modules_zsh_paths_plugins_dir}"
        "${config_modules_zsh_paths_themes_dir}"
        "${config_modules_zsh_paths_completions_dir}"
    )
    
    for dir in "${custom_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log "ERROR" "Failed to create directory: $dir"
            return 1
        fi
    done
    
    return 0
}

install_powerlevel10k() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    log "INFO" "Installing Powerlevel10k theme..."
    
    local theme_dir="${config_modules_zsh_paths_themes_dir}/powerlevel10k"
    
    # Clone or update Powerlevel10k
    if [ ! -d "$theme_dir" ]; then
        if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"; then
            log "ERROR" "Failed to clone Powerlevel10k"
            return 1
        fi
    else
        log "INFO" "Updating Powerlevel10k..."
        if ! (cd "$theme_dir" && git pull); then
            log "ERROR" "Failed to update Powerlevel10k"
            return 1
        fi
    fi
    
    # Install recommended fonts
    install_fonts || return 1
    
    return 0
}

install_fonts() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    log "INFO" "Installing custom fonts..."
    
    local font_dir="${config_modules_zsh_fonts_install_path}"
    mkdir -p "$font_dir"
    
    # Download and install each font
    for font in "${config_modules_zsh_fonts_names[@]}"; do
        if [ ! -f "$font_dir/$font" ]; then
            log "INFO" "Downloading font: $font"
            if ! wget -P "$font_dir" "${config_modules_zsh_fonts_source}/$font"; then
                log "ERROR" "Failed to download font: $font"
                return 1
            fi
        fi
    done
    
    # Update font cache
    if command -v fc-cache &> /dev/null; then
        fc-cache -f "$font_dir"
    fi
    
    return 0
}

install_custom_plugins() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    log "INFO" "Installing ZSH plugins..."
    
    # Install each custom plugin
    for plugin in "${!config_modules_zsh_custom_plugins[@]}"; do
        local plugin_dir="${config_modules_zsh_paths_plugins_dir}/${plugin}"
        local plugin_url="${config_modules_zsh_custom_plugins[$plugin]}"
        
        if [ ! -d "$plugin_dir" ]; then
            log "INFO" "Installing plugin: $plugin"
            if ! git clone --depth=1 "$plugin_url" "$plugin_dir"; then
                log "ERROR" "Failed to install plugin: $plugin"
                return 1
            fi
        else
            log "INFO" "Updating plugin: $plugin"
            if ! (cd "$plugin_dir" && git pull); then
                log "ERROR" "Failed to update plugin: $plugin"
                return 1
            fi
        fi
    done
    
    return 0
}

configure_zsh() {
    log "INFO" "Configuring ZSH..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Backup existing configurations
    backup_file "$HOME/.zshrc"
    backup_file "$HOME/.p10k.zsh"
    
    # Generate main ZSH configuration
    generate_zshrc || return 1
    
    # Generate Powerlevel10k configuration
    generate_p10k || return 1
    
    # Set proper permissions
    chmod 644 "$HOME/.zshrc"
    chmod 644 "$HOME/.p10k.zsh"
    
    return 0
}

generate_zshrc() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    local zshrc="$HOME/.zshrc"
    
    # Create base configuration
    cat > "$zshrc" << 'EOF'
# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Oh My ZSH configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# History configuration
HISTSIZE=10000
SAVEHIST=100000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
EOF

    # Add configured plugins
    echo -n "plugins=(" >> "$zshrc"
    for plugin in "${config_modules_zsh_plugins[@]}"; do
        echo -n " $plugin" >> "$zshrc"
    done
    echo ")" >> "$zshrc"

    # Add remaining configuration
    cat >> "$zshrc" << 'EOF'

# Source Oh My ZSH
source $ZSH/oh-my-zsh.sh

# Environment configuration
export EDITOR='nano'
export VISUAL='code'
export PAGER='less'

# PATH configuration
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/Development/scripts:$PATH"

# Load Powerlevel10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF

    # Add module-specific aliases
    for category in "${!config_modules_zsh_aliases[@]}"; do
        local aliases_array="config_modules_zsh_aliases_${category}[@]"
        
        echo -e "\n# ${category^} aliases" >> "$zshrc"
        for alias_data in "${!aliases_array}"; do
            local name="${alias_data[name]}"
            local command="${alias_data[command]}"
            echo "alias ${name}='${command}'" >> "$zshrc"
        done
    done

    return 0
}

generate_p10k() {
    cat > "$HOME/.p10k.zsh" << 'EOF'
# Generated by Powerlevel10k configuration wizard
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs conda pyenv node_version)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs)
POWERLEVEL9K_PROMPT_ON_NEWLINE=true
POWERLEVEL9K_PROMPT_ADD_NEWLINE=true

# VCS configuration
POWERLEVEL9K_VCS_CLEAN_BACKGROUND='green'
POWERLEVEL9K_VCS_UNTRACKED_BACKGROUND='yellow'
POWERLEVEL9K_VCS_MODIFIED_BACKGROUND='red'

# Directory configuration
POWERLEVEL9K_DIR_HOME_BACKGROUND='blue'
POWERLEVEL9K_DIR_HOME_SUBFOLDER_BACKGROUND='blue'
POWERLEVEL9K_DIR_ETC_BACKGROUND='blue'
POWERLEVEL9K_DIR_DEFAULT_BACKGROUND='blue'

# Status configuration
POWERLEVEL9K_STATUS_OK=false
POWERLEVEL9K_STATUS_CROSS=true

# Command execution time configuration
POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=0
POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=2
EOF

    return 0
}

remove_zsh() {
    log "INFO" "Removing ZSH configuration..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Restore original configs from backup
    restore_backup "$HOME/.zshrc"
    restore_backup "$HOME/.p10k.zsh"
    
    # Remove Oh My ZSH and custom components
    if [ -d "$HOME/.oh-my-zsh" ]; then
        rm -rf "$HOME/.oh-my-zsh"
    fi
    
    # Remove custom fonts
    local font_dir="${config_modules_zsh_fonts_install_path}"
    for font in "${config_modules_zsh_fonts_names[@]}"; do
        rm -f "$font_dir/$font"
    done
    
    # Update font cache
    if command -v fc-cache &> /dev/null; then
        fc-cache -f "$font_dir"
    fi
    
    log "INFO" "ZSH configuration removed"
    return 0
}

verify_zsh() {
    log "INFO" "Verifying ZSH installation..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local verification_failed=false
    
    # Check ZSH installation
    if ! command -v zsh &> /dev/null; then
        log "ERROR" "ZSH is not installed"
        verification_failed=true
    fi
    
    # Check Oh My ZSH installation
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "ERROR" "Oh My ZSH is not installed"
        verification_failed=true
    fi
    
    # Check Powerlevel10k
    if [ ! -d "${config_modules_zsh_paths_themes_dir}/powerlevel10k" ]; then
        log "ERROR" "Powerlevel10k theme is not installed"
        verification_failed=true
    fi
    
    # Check custom plugins
    for plugin in "${!config_modules_zsh_custom_plugins[@]}"; do
        if [ ! -d "${config_modules_zsh_paths_plugins_dir}/${plugin}" ]; then
            log "ERROR" "Plugin not installed: $plugin"
            verification_failed=true
        fi
    done
    
    # Check configuration files
    local config_files=(
        "$HOME/.zshrc"
        "$HOME/.p10k.zsh"
    )
    
    for file in "${config_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "ERROR" "Configuration file not found: $file"
            verification_failed=true
        fi
    done
    
    # Check custom fonts
    local font_dir="${config_modules_zsh_fonts_install_path}"
    for font in "${config_modules_zsh_fonts_names[@]}"; do
        if [ ! -f "$font_dir/$font" ]; then
            log "ERROR" "Font not installed: $font"
            verification_failed=true
        fi
    done
    
    # Check if ZSH is the default shell
    if [[ $SHELL != *"zsh"* ]]; then
        log "WARN" "ZSH is not the default shell"
    fi
    
    # Verify aliases
    local aliases_verified=true

    for category in "${!config_modules_zsh_aliases[@]}"; do
        local aliases_array="config_modules_zsh_aliases_${category}[@]"
        for alias_data in "${!aliases_array}"; do
            local name="${alias_data[name]}"
            local command="${alias_data[command]}"
            if ! grep -q "alias ${name}='${command}'" "$HOME/.zshrc"; then
                log "ERROR" "Alias not found: ${name}='${command}'"
                aliases_verified=false
            fi
        done
    done
    [ "$aliases_verified" = false ] && verification_failed=true
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "ZSH verification complete"
    return 0
}

update_zsh() {
    log "INFO" "Updating ZSH environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Update ZSH package if installed via package manager
    if command -v dnf &> /dev/null; then
        sudo dnf update -y zsh
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get upgrade -y zsh
    fi
    
    # Update Oh My ZSH
    if [ -d "$HOME/.oh-my-zsh" ]; then
        env ZSH="$HOME/.oh-my-zsh" sh "$HOME/.oh-my-zsh/tools/upgrade.sh"
    fi
    
    # Update Powerlevel10k theme
    local theme_dir="${config_modules_zsh_paths_themes_dir}/powerlevel10k"
    if [ -d "$theme_dir" ]; then
        log "INFO" "Updating Powerlevel10k..."
        if ! (cd "$theme_dir" && git pull); then
            log "ERROR" "Failed to update Powerlevel10k"
            return 1
        fi
    fi
    
    # Update custom plugins
    log "INFO" "Updating custom plugins..."
    if ! install_custom_plugins; then
        log "ERROR" "Failed to update custom plugins"
        return 1
    fi
    
    # Update fonts
    log "INFO" "Checking for font updates..."
    if ! install_fonts; then
        log "ERROR" "Failed to update fonts"
        return 1
    fi
    
    # Reconfigure with latest settings
    if ! configure_zsh; then
        log "ERROR" "Failed to update ZSH configuration"
        return 1
    fi
    
    log "INFO" "ZSH environment update complete"
    return 0
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update}"
        exit 1
    fi
    module_base "$1" "zsh"
fi