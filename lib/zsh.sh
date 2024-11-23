#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

ZSH_CUSTOM_DIR="$HOME/.oh-my-zsh/custom"
ZSH_PLUGINS_DIR="$ZSH_CUSTOM_DIR/plugins"
ZSH_THEMES_DIR="$ZSH_CUSTOM_DIR/themes"
ZSH_COMPLETIONS_DIR="$ZSH_CUSTOM_DIR/completions"

setup_zsh() {
    log "INFO" "Setting up ZSH environment..."
    
    # Install ZSH if not present
    if ! command -v zsh &> /dev/null; then
        log "INFO" "Installing ZSH..."
        sudo dnf install -y zsh util-linux-user
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
    
    # List of custom plugins to install
    declare -A plugins=(
        ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
        ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
        ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
        ["conda-zsh-completion"]="https://github.com/esc/conda-zsh-completion"
        ["docker-zsh-completion"]="https://github.com/greymd/docker-zsh-completion"
    )
    
    # Clone or update each plugin
    for plugin in "${!plugins[@]}"; do
        local plugin_dir="${ZSH_PLUGINS_DIR}/${plugin}"
        if [ ! -d "$plugin_dir" ]; then
            log "INFO" "Installing plugin: $plugin"
            git clone --depth=1 "${plugins[$plugin]}" "$plugin_dir"
        else
            log "INFO" "Updating plugin: $plugin"
            cd "$plugin_dir" && git pull
        fi
    done
}

configure_zsh() {
    log "INFO" "Configuring ZSH..."
    
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
SAVEHIST=10000
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
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

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

# Development environment helper functions
create_project() {
    local name=$1
    local type=${2:-python}  # default to python
    
    if [ -z "$name" ]; then
        echo "Usage: create_project <name> [type]"
        return 1
    fi
    
    local project_dir="$DEV_HOME/projects/$name"
    
    case $type in
        python)
            mkcd "$project_dir"
            conda create -n "$name" python=3.11 -y
            conda activate "$name"
            mkdir -p src tests docs
            touch README.md requirements.txt
            git init
            ;;
        cpp)
            mkcd "$project_dir"
            conda create -n "$name" -y
            mkdir -p src include tests docs build
            touch README.md CMakeLists.txt
            git init
            ;;
        *)
            echo "Unknown project type: $type"
            return 1
            ;;
    esac
    
    echo "Project $name created with type $type"
}

# Powerlevel10k configuration
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
    
    # Create Powerlevel10k configuration
    cat > "$HOME/.p10k.zsh" << 'EOF'
# Generated by Powerlevel10k configuration wizard
# Basic configuration that can be customized by running 'p10k configure'
POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    os_icon
    dir
    vcs
    conda
    pyenv
    node_version
)
POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status
    command_execution_time
    background_jobs
    direnv
    asdf
    virtualenv
    pyenv
    nodenv
    nvm
    nodeenv
    rbenv
    rvm
    jenv
    plenv
    phpenv
    haskell_stack
    kubecontext
    context
    nordvpn
    ranger
    timewarrior
    time
    battery
)
POWERLEVEL9K_PROMPT_ON_NEWLINE=true
POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
EOF
    
    # Set permissions
    chmod 644 "$HOME/.zshrc"
    chmod 644 "$HOME/.p10k.zsh"
    
    log "INFO" "ZSH configuration complete"
}

# Function to update ZSH environment
update_zsh() {
    log "INFO" "Updating ZSH environment..."
    
    # Update Oh My ZSH
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Updating Oh My ZSH..."
        env ZSH="$HOME/.oh-my-zsh" sh "$HOME/.oh-my-zsh/tools/upgrade.sh"
    fi
    
    # Update Powerlevel10k
    if [ -d "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" ]; then
        log "INFO" "Updating Powerlevel10k..."
        cd "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" && git pull
    fi
    
    # Update custom plugins
    log "INFO" "Updating custom plugins..."
    for plugin_dir in "${ZSH_PLUGINS_DIR}"/*; do
        if [ -d "$plugin_dir/.git" ]; then
            log "INFO" "Updating plugin: $(basename "$plugin_dir")"
            cd "$plugin_dir" && git pull
        fi
    done
    
    log "INFO" "ZSH environment update complete"
}