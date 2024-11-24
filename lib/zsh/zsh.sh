#!/bin/bash
# lib/zsh/zsh.sh - ZSH module implementation

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../logging.sh"
source "${SCRIPT_DIR}/../yaml_parser.sh"
source "${SCRIPT_DIR}/../module_base.sh"

ZSH_CUSTOM_DIR="$HOME/.oh-my-zsh/custom"
ZSH_PLUGINS_DIR="$ZSH_CUSTOM_DIR/plugins"
ZSH_THEMES_DIR="$ZSH_CUSTOM_DIR/themes"
ZSH_COMPLETIONS_DIR="$ZSH_CUSTOM_DIR/completions"

grovel_zsh() {
    log "INFO" "Checking ZSH dependencies..."
    if ! command -v zsh &> /dev/null; then
        log "INFO" "ZSH not found"
        return 1
    fi
    
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Oh My ZSH not found"
        return 1
    fi
}

install_zsh() {
    log "INFO" "Setting up ZSH environment..."
    
    # Install ZSH if not present
    if ! command -v zsh &> /dev/null; then
        log "INFO" "Installing ZSH..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y zsh util-linux-user
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zsh
        else
            log "ERROR" "Unsupported package manager"
            return 1
        fi
    fi
    
    # Install Oh My ZSH if not present
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Installing Oh My ZSH..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    
    # Create custom directories
    mkdir -p "$ZSH_CUSTOM_DIR"/{plugins,themes,completions,lib}
    
    # Install Powerlevel10k theme
    install_powerlevel10k
    
    # Install custom plugins
    install_custom_plugins
    
    # Configure ZSH
    configure_zsh
    
    # Set ZSH as default shell if it isn't already
    if [[ $SHELL != *"zsh"* ]]; then
        log "INFO" "Setting ZSH as default shell..."
        chsh -s "$(which zsh)" "$(whoami)"
    fi
}

install_powerlevel10k() {
    log "INFO" "Installing Powerlevel10k theme..."
    
    # Clone Powerlevel10k if not present
    if [ ! -d "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM_DIR}/themes/powerlevel10k"
    else
        log "INFO" "Updating Powerlevel10k..."
        cd "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" && git pull
    fi
    
    # Download recommended font
    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"
    
    local fonts=(
        "MesloLGS NF Regular.ttf"
        "MesloLGS NF Bold.ttf"
        "MesloLGS NF Italic.ttf"
        "MesloLGS NF Bold Italic.ttf"
    )
    
    for font in "${fonts[@]}"; do
        if [ ! -f "$font_dir/$font" ]; then
            wget -P "$font_dir" "https://github.com/romkatv/powerlevel10k-media/raw/master/$font"
        fi
    done
    
    # Update font cache
    fc-cache -f "$font_dir"
}

install_custom_plugins() {
    log "INFO" "Installing ZSH plugins..."
    
    # Get plugins from config
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    
    # Install each custom plugin
    for plugin in "${!config_modules_zsh_custom_plugins[@]}"; do
        local plugin_dir="${ZSH_PLUGINS_DIR}/${plugin}"
        local plugin_url="${config_modules_zsh_custom_plugins[$plugin]}"
        
        if [ ! -d "$plugin_dir" ]; then
            log "INFO" "Installing plugin: $plugin"
            git clone --depth=1 "$plugin_url" "$plugin_dir"
        else
            log "INFO" "Updating plugin: $plugin"
            cd "$plugin_dir" && git pull
        fi
    done
}

configure_zsh() {
    log "INFO" "Configuring ZSH..."
    
    # Backup existing config
    backup_file "$HOME/.zshrc"
    backup_file "$HOME/.p10k.zsh"
    
    # Create main zshrc configuration
    cat > "$HOME/.zshrc" << 'EOF'
# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Oh My ZSH configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# History configuration
HISTSIZE=10000
SAVEHIST=100000000
HISTFILE=~/.zsh_history
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY

# Plugin configuration
plugins=(
    git
    docker
    kubectl
    conda-zsh-completion
    docker-zsh-completion
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
    python
    pip
    node
    npm
    colored-man-pages
    command-not-found
    history-substring-search
    dirhistory
)

# Source Oh My ZSH
source $ZSH/oh-my-zsh.sh

# Custom aliases
alias ll='ls -lah'
alias l='ls -lh'
alias zshconfig="code ~/.zshrc"
alias ohmyzsh="code ~/.oh-my-zsh"

# Development aliases
alias dc='docker-compose'
alias k='kubectl'
alias py='python'
alias pip='pip3'
alias activate='source activate'
alias deactivate='conda deactivate'
alias jupynb='jupyter notebook'
alias jupylab='jupyter lab'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias gf='git fetch'
alias grb='git rebase'
alias gst='git stash'
alias glg='git log --graph --oneline --decorate'

# Project navigation
export DEV_HOME="$HOME/Development"
alias cddev='cd $DEV_HOME'
alias cdproj='cd $DEV_HOME/projects'
alias cddock='cd $DEV_HOME/docker'
alias cdpkg='cd $DEV_HOME/packages'

# Environment configuration
export EDITOR='nano'
export VISUAL='code'
export PAGER='less'

# PATH configuration
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/Development/scripts:$PATH"

# Node Version Manager
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Conda configuration
[ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ] && source "$HOME/miniconda3/etc/profile.d/conda.sh"

# Custom functions
mkcd() {
    mkdir -p "$1" && cd "$1"
}

extract() {
    if [ -f $1 ] ; then
        case $1 in
            *.tar.bz2)   tar xjf $1     ;;
            *.tar.gz)    tar xzf $1     ;;
            *.bz2)       bunzip2 $1     ;;
            *.rar)       unrar x $1     ;;
            *.gz)        gunzip $1      ;;
            *.tar)       tar xf $1      ;;
            *.tbz2)      tar xjf $1     ;;
            *.tgz)       tar xzf $1     ;;
            *.zip)       unzip $1       ;;
            *.Z)         uncompress $1  ;;
            *.7z)        7z x $1        ;;
            *)          echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Powerlevel10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
    
    # Create Powerlevel10k configuration
    cat > "$HOME/.p10k.zsh" << 'EOF'
# Generated by Powerlevel10k configuration wizard
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(os_icon dir vcs conda pyenv node_version)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status command_execution_time background_jobs)
POWERLEVEL9K_PROMPT_ON_NEWLINE=true
POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
EOF
    
    # Set permissions
    chmod 644 "$HOME/.zshrc"
    chmod 644 "$HOME/.p10k.zsh"
    
    log "INFO" "ZSH configuration complete"
}

remove_zsh() {
    log "INFO" "Removing ZSH configuration..."
    
    # Restore original configs from backup
    restore_backup "$HOME/.zshrc"
    restore_backup "$HOME/.p10k.zsh"
    
    # Remove Oh My ZSH
    if [ -d "$HOME/.oh-my-zsh" ]; then
        rm -rf "$HOME/.oh-my-zsh"
    fi
    
    # Remove custom fonts
    rm -f "$HOME/.local/share/fonts/MesloLGS NF"*
    fc-cache -f
    
    log "INFO" "ZSH configuration removed"
}

verify_zsh() {
    log "INFO" "Verifying ZSH installation..."
    
    # Check ZSH
    if ! command -v zsh &> /dev/null; then
        log "ERROR" "ZSH is not installed"
        return 1
    fi
    
    # Check Oh My ZSH
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "ERROR" "Oh My ZSH is not installed"
        return 1
    fi
    
    # Check Powerlevel10k
    if [ ! -d "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" ]; then
        log "ERROR" "Powerlevel10k theme is not installed"
        return 1
    fi
    
    # Check custom plugins
    eval $(parse_yaml "$SCRIPT_DIR/../../config.yaml" "config_")
    for plugin in "${!config_modules_zsh_custom_plugins[@]}"; do
        if [ ! -d "${ZSH_PLUGINS_DIR}/${plugin}" ]; then
            log "ERROR" "Plugin not installed: $plugin"
            return 1
        fi
    done
    
    log "INFO" "ZSH verification complete"
    return 0
}

update_zsh() {
    log "INFO" "Updating ZSH environment..."
    
    # Update Oh My ZSH
    if [ -d "$HOME/.oh-my-zsh" ]; then
        env ZSH="$HOME/.oh-my-zsh" sh "$HOME/.oh-my-zsh/tools/upgrade.sh"
    fi
    
    # Update Powerlevel10k
    if [ -d "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" ]; then
        cd "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" && git pull
    fi
    
    # Update custom plugins
    install_custom_plugins
    
    log "INFO" "ZSH environment update complete"
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update}"
        exit 1
    fi
    module_base "$1" "zsh"
fi