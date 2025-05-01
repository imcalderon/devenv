#!/bin/bash
# modules/zsh/zsh.sh - Minimal ZSH module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "zsh" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/zsh.state"

# Components list for module
COMPONENTS=(
    "core"          # Base ZSH installation
    "config"        # ZSH configuration files (.zshenv, .zshrc, etc)
    "prompt"        # Custom prompt
    "keybindings"   # Vi mode and keybindings
    "completion"    # ZSH completion system
    "plugins"       # Minimal essential plugins
)

# Display module information
show_module_info() {
    cat << 'EOF'

🛠️ ZSH Shell Environment
=======================

Description:
-----------
Minimal, efficient ZSH shell environment focused on productivity 
with sane defaults and essential features.

Benefits:
--------
✓ Fast Startup - Minimal dependencies for quick shell startup
✓ Powerful Completion - Context-aware tab completion
✓ Vi Mode - Vim-like editing capabilities
✓ Directory Navigation - Enhanced directory stack and navigation
✓ Custom Prompt - Clean, informative prompt with git information

Components:
----------
1. Core ZSH
   - Modern shell replacement for bash
   - Advanced command line editing
   - Improved tab completion

2. Configuration
   - Organized XDG-compliant config
   - History management
   - Directory navigation

3. Custom Prompt
   - Git status integration
   - Clean, minimal design
   - Command execution status

4. Keybindings
   - Vi mode with visual indicators
   - Familiar vim motions and text objects
   - Command-line editing with $EDITOR

5. Essential Plugins
   - Syntax highlighting
   - History substring search
   - Directory jumping

Quick Start:
-----------
1. Reload shell configuration:
   $ source ~/.zshrc

2. Edit configuration:
   $ zshconfig

3. Navigate with directory stack:
   $ d        (show directory stack)
   $ 1-9      (jump to stack position)

Aliases:
-------
zshconfig  : Edit ZSH configuration
reload     : Reload ZSH configuration

Configuration:
-------------
Location: ~/.config/zsh
Key files:
- ~/.zshenv         : Environment variables
- ~/.config/zsh/.zshrc    : Main configuration
- ~/.config/zsh/aliases   : All aliases
- ~/.config/zsh/prompt    : Prompt configuration
- ~/.config/zsh/completion : Completion settings

Tips:
----
- Use 'Tab' for smart completion
- Press 'v' in normal mode to edit command in $EDITOR
- Press 'Esc' to enter vi command mode
- Use 'Alt+.' to insert last argument

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
                "completion")
                    echo "  Completion system: Active"
                    ;;
                "plugins")
                    echo "  Essential plugins: Active"
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
        "config")
            [[ -f "$HOME/.zshenv" ]] && [[ -f "$HOME/.config/zsh/.zshrc" ]]
            ;;
        "prompt")
            [[ -f "$HOME/.config/zsh/prompt.zsh" ]]
            ;;
        "keybindings")
            [[ -f "$HOME/.config/zsh/keybindings.zsh" ]]
            ;;
        "completion")
            [[ -f "$HOME/.config/zsh/completion.zsh" ]]
            ;;
        "plugins")
            verify_plugins
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verify plugins
verify_plugins() {
    local plugins_dir="$HOME/.config/zsh/plugins"
    
    # Check essential plugins
    [[ -d "$plugins_dir/zsh-syntax-highlighting" ]] && \
    [[ -d "$plugins_dir/zsh-history-substring-search" ]]
}

# Install core ZSH
install_zsh_core() {
    if ! command -v zsh &>/dev/null; then
        log "INFO" "Installing zsh..." "zsh"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y zsh curl git
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y zsh curl git
        else
            log "ERROR" "Unsupported package manager" "zsh"
            return 1
        fi
    fi
    return 0
}

# Create XDG-compliant directory structure
create_zsh_dirs() {
    log "INFO" "Creating ZSH directories..." "zsh"
    
    local config_dir="$HOME/.config/zsh"
    local cache_dir="$HOME/.cache/zsh"
    local data_dir="$HOME/.local/share/zsh"
    local plugins_dir="$config_dir/plugins"
    local modules_dir="$config_dir/modules"  # Add this line for the modules directory
    
    mkdir -p "$config_dir" "$cache_dir" "$data_dir" "$plugins_dir" "$modules_dir"
    
    # Explicitly set module directory path in configuration
    # This is needed for alias.sh to find the correct location
    if [[ -f "$HOME/.config/zsh/config.json" ]]; then
        # Update existing config file
        log "INFO" "Updating modules_dir in ZSH configuration..." "zsh"
        # This would require jq manipulation - simplified here
    else
        # Create a minimal config file if it doesn't exist
        log "INFO" "Creating minimal ZSH config file with modules_dir..." "zsh"
        mkdir -p "$HOME/.config/zsh"
        echo '{
            "shell": {
                "paths": {
                    "modules_dir": "$HOME/.config/zsh/modules",
                    "config_dir": "$HOME/.config/zsh",
                    "cache_dir": "$HOME/.cache/zsh",
                    "data_dir": "$HOME/.local/share/zsh"
                }
            }
        }' > "$HOME/.config/zsh/config.json"
    fi
    
    return 0
}

# Configure zsh with .zshenv
configure_zshenv() {
    log "INFO" "Configuring .zshenv..." "zsh"
    
    # Backup existing config
    [[ -f "$HOME/.zshenv" ]] && backup_file "$HOME/.zshenv" "zsh"
    
    # Create .zshenv in $HOME
    cat > "$HOME/.zshenv" << 'EOF'
# ZSH Environment Variables
# This file should only contain environment variables

# XDG Base Directory
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"

# Set ZSH config location
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# History configuration
export HISTFILE="$ZDOTDIR/.zhistory"
export HISTSIZE=10000
export SAVEHIST=10000

# Default programs
export EDITOR="vim"
export VISUAL="vim"
export PAGER="less"

# Ensure path arrays don't contain duplicates
typeset -U path PATH
path=(
  $HOME/.local/bin
  $path
)
export PATH
EOF

    return 0
}

# Configure .zshrc
configure_zshrc() {
    log "INFO" "Configuring .zshrc..." "zsh"
    
    local config_dir="$HOME/.config/zsh"
    
    # Ensure directory exists
    mkdir -p "$config_dir"
    
    # Backup existing config
    [[ -f "$config_dir/.zshrc" ]] && backup_file "$config_dir/.zshrc" "zsh"
    
    # Create base zshrc
    cat > "$config_dir/.zshrc" << 'EOF'
# ZSH Main Configuration

# Options
setopt AUTO_CD              # Change directory without typing cd
setopt AUTO_PUSHD           # Push the current directory onto the dirstack
setopt PUSHD_IGNORE_DUPS    # Do not store duplicates in the stack
setopt PUSHD_SILENT         # Do not print the directory stack after pushd or popd
setopt HIST_VERIFY          # Show command with history expansion before running it
setopt HIST_IGNORE_DUPS     # Do not record a command that just run
setopt HIST_IGNORE_ALL_DUPS # Delete old entry if new entry is a duplicate
setopt HIST_FIND_NO_DUPS    # Do not display a line previously found
setopt HIST_SAVE_NO_DUPS    # Don't write duplicate entries in the history file
setopt SHARE_HISTORY        # Share history between all sessions
setopt EXTENDED_HISTORY     # Record timestamp of command in HISTFILE

# Load completion system
source "$ZDOTDIR/completion.zsh"

# Load custom prompt
source "$ZDOTDIR/prompt.zsh"

# Load keybindings (vi-mode)
source "$ZDOTDIR/keybindings.zsh"

# Directory stack aliases
alias d='dirs -v'
for index ({1..9}) alias "$index"="cd +${index}"; unset index

# Load essential plugins
source "$ZDOTDIR/plugins.zsh"

# Load aliases
[[ -f "$ZDOTDIR/aliases" ]] && source "$ZDOTDIR/aliases"

# Load modules aliases (added for devenv support)
[[ -d "$ZDOTDIR/modules" ]] && for module_file in "$ZDOTDIR/modules"/*.zsh; do
    [[ -f "$module_file" ]] && source "$module_file"
done

# Load any local customizations
[[ -f "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"
EOF

    # Create aliases file
    cat > "$config_dir/aliases" << 'EOF'
# ZSH Aliases

# General aliases
alias zshconfig="$EDITOR $ZDOTDIR/.zshrc"
alias reload="source $ZDOTDIR/.zshrc"

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# List files
alias ls='ls --color=auto'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Filesystem operations
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# System information
alias df='df -h'
alias du='du -h'
alias free='free -m'
EOF

    return 0
}

# Configure completion system
configure_completion() {
    log "INFO" "Configuring ZSH completion system..." "zsh"
    
    local config_dir="$HOME/.config/zsh"
    local completions_dir="$config_dir/completions"
    
    # Create completions directory
    mkdir -p "$completions_dir"
    
    # Create completion config
    cat > "$config_dir/completion.zsh" << 'EOF'
# ZSH Completion Configuration

# Initialize completion system
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"

# Add completions directory to fpath
fpath=("$ZDOTDIR/completions" $fpath)

# Basic completion options
setopt COMPLETE_IN_WORD    # Complete from both ends of a word
setopt ALWAYS_TO_END       # Move cursor to the end of a completed word
setopt PATH_DIRS           # Perform path search even on command names with slashes
setopt AUTO_MENU           # Show completion menu on a successive tab press
setopt COMPLETE_ALIASES    # Complete aliases

# Completion styling
zstyle ':completion:*' menu select                  # Select completions with arrow keys
zstyle ':completion:*' group-name ''                # Group results by category
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive completion
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %d --%f'
zstyle ':completion:*:*:*:*:corrections' format '%F{yellow}!- %d (errors: %e) -!%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'

# Speed up completions
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"

# Don't complete uninteresting users
zstyle ':completion:*:*:*:users' ignored-patterns \
        adm amanda apache at avahi avahi-autoipd beaglidx bin colord \
        daemon dbus distcache dnsmasq dovecot fax ftp games gdm \
        gkrellmd gopher hacluster haldaemon halt hsqldb ident junkbust \
        ldap lp mail mailman mailnull man messagebus mldonkey mysql \
        nagios named netdump news nfsnobody nobody nscd ntp nut nx \
        openldap operator pcap polkitd postfix postgres privoxy pulse \
        pvm quagga radvd rpc rpcuser rpm rtkit scard shutdown squid \
        sshd statd svn sync tftp usbmux uucp vcsa wwwrun xfs '_*'

# Complete hidden files
_comp_options+=(globdots)
EOF

    return 0
}

# Configure custom prompt
configure_prompt() {
    log "INFO" "Configuring ZSH prompt..." "zsh"
    
    local config_dir="$HOME/.config/zsh"
    
    # Create prompt config
    cat > "$config_dir/prompt.zsh" << 'EOF'
# ZSH Custom Prompt Configuration

# Load version control information
autoload -Uz vcs_info
precmd() { vcs_info }

# Format the vcs_info_msg_0_ variable
zstyle ':vcs_info:git:*' formats ' on %F{magenta}%b%f%c%u'
zstyle ':vcs_info:*' enable git

# Set up the prompt
setopt prompt_subst

# Define prompt styling
PROMPT='%F{cyan}%~%f${vcs_info_msg_0_} %F{yellow}❯%f '
RPROMPT='%(?..%F{red}✗%f)'

# Show if in vi mode (NORMAL/INSERT)
function zle-line-init zle-keymap-select {
    case $KEYMAP in
        vicmd) echo -ne '\e[2 q';; # Block cursor for NORMAL mode
        viins|main) echo -ne '\e[6 q';; # Beam cursor for INSERT mode
    esac
    zle reset-prompt
}

zle -N zle-line-init
zle -N zle-keymap-select
EOF

    return 0
}

# Configure vi mode and keybindings
configure_keybindings() {
    log "INFO" "Configuring ZSH keybindings..." "zsh"
    
    local config_dir="$HOME/.config/zsh"
    
    # Create keybindings config
    cat > "$config_dir/keybindings.zsh" << 'EOF'
# ZSH Keybindings Configuration

# Use vi key bindings
bindkey -v

# Make Vi mode transitions faster (KEYTIMEOUT is in hundredths of a second)
export KEYTIMEOUT=1

# Use vim keys in tab complete menu
zmodload zsh/complist
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history

# Edit command in editor
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# Add text objects for brackets and quotes
autoload -Uz select-bracketed select-quoted
zle -N select-quoted
zle -N select-bracketed
for km in viopp visual; do
  bindkey -M $km -- '-' vi-up-line-or-history
  for c in {a,i}${(s..)^:-\'\"\`\|,./:;=+@}; do
    bindkey -M $km $c select-quoted
  done
  for c in {a,i}${(s..)^:-'()[]{}<>bB'}; do
    bindkey -M $km $c select-bracketed
  done
done

# Add surround capability (similar to vim-surround)
autoload -Uz surround
zle -N delete-surround surround
zle -N add-surround surround
zle -N change-surround surround
bindkey -M vicmd cs change-surround
bindkey -M vicmd ds delete-surround
bindkey -M vicmd ys add-surround
bindkey -M visual S add-surround

# Common keybindings
bindkey '^R' history-incremental-search-backward   # Ctrl+R for backward search
bindkey '^S' history-incremental-search-forward    # Ctrl+S for forward search
bindkey '^P' up-history                          # Ctrl+P for previous command
bindkey '^N' down-history                        # Ctrl+N for next command
bindkey '^A' beginning-of-line                   # Ctrl+A go to beginning of line
bindkey '^E' end-of-line                         # Ctrl+E go to end of line
bindkey '\e.' insert-last-word                   # Alt+. insert last argument
EOF

    return 0
}

# Install and configure essential plugins
configure_plugins() {
    log "INFO" "Configuring ZSH plugins..." "zsh"
    
    local config_dir="$HOME/.config/zsh"
    local plugins_dir="$config_dir/plugins"
    
    # Create plugins directory
    mkdir -p "$plugins_dir"
    
    # Install essential plugins if not already installed
    local plugins=(
        "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
        "zsh-history-substring-search|https://github.com/zsh-users/zsh-history-substring-search.git"
    )
    
    for plugin_info in "${plugins[@]}"; do
        local plugin_name="${plugin_info%%|*}"
        local plugin_url="${plugin_info#*|}"
        
        if [[ ! -d "$plugins_dir/$plugin_name" ]]; then
            log "INFO" "Installing plugin: $plugin_name" "zsh"
            git clone --depth 1 "$plugin_url" "$plugins_dir/$plugin_name"
        fi
    done
    
    # Create plugins loader
    cat > "$config_dir/plugins.zsh" << 'EOF'
# ZSH Plugins Configuration

# Load syntax highlighting (must be before history-substring-search)
source "$ZDOTDIR/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# Load history substring search
source "$ZDOTDIR/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh"

# Configure history substring search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down
EOF

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
            if install_zsh_core && create_zsh_dirs; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "config")
            if configure_zshenv && configure_zshrc; then
                save_state "config" "installed"
                return 0
            fi
            ;;
        "prompt")
            if configure_prompt; then
                save_state "prompt" "installed"
                return 0
            fi
            ;;
        "keybindings")
            if configure_keybindings; then
                save_state "keybindings" "installed"
                return 0
            fi
            ;;
        "completion")
            if configure_completion; then
                save_state "completion" "installed"
                return 0
            fi
            ;;
        "plugins")
            if configure_plugins; then
                save_state "plugins" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Check if ZSH is already installed and configured
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

# Install ZSH with all components
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
    
    # Add shell aliases directly to the aliases file instead of using add_module_aliases
    log "INFO" "Adding shell aliases..." "zsh"
    local config_dir="$HOME/.config/zsh"
    local aliases=$(get_module_config "zsh" ".shell.aliases.shell")
    
    if [[ -n "$aliases" ]]; then
        # Add shell aliases section to the aliases file
        echo -e "\n# Shell aliases managed by devenv" >> "$config_dir/aliases"
        
        # Get keys from the shell aliases object and add each one
        local alias_keys=($(get_module_config "zsh" ".shell.aliases.shell | keys[]"))
        for key in "${alias_keys[@]}"; do
            local cmd=$(get_module_config "zsh" ".shell.aliases.shell[\"$key\"]")
            echo "alias $key='$cmd'" >> "$config_dir/aliases"
        done
    fi
    
    # Setup ZSH environment without changing login shell
    if [[ "$SHELL" != *"zsh"* ]]; then
        # Set a global flag to indicate ZSH was installed but login shell not changed
        export ZSH_INSTALLED=1
        export ZSH_LOGIN_SHELL_PENDING=1
        
        # Create a zsh executor script in bin directory
        local bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir"
        
        cat > "$bin_dir/zsh-exec" << 'EOF'
#!/bin/bash
# ZSH executor for DevEnv
zsh_bin=$(command -v zsh)
if [ -n "$zsh_bin" ]; then
    $zsh_bin -c "$*"
else
    echo "Error: ZSH not found"
    exit 1
fi
EOF
        chmod +x "$bin_dir/zsh-exec"
        
        # Add this to PATH if needed
        if ! echo "$PATH" | grep -q "$bin_dir"; then
            export PATH="$bin_dir:$PATH"
        fi
        
        log "INFO" "ZSH installed but login shell will be changed after all modules are installed." "zsh"
        log "INFO" "Created zsh-exec helper script for other modules to use." "zsh"
        
        # If this is the end of all module installations, change login shell
        if [[ "${DEVENV_FINAL_MODULE:-}" == "zsh" || "$force" == "true" ]]; then
            log "INFO" "Changing login shell to ZSH..." "zsh"
            chsh -s "$(command -v zsh)"
            log "INFO" "Shell changed to zsh. Please log out and back in for changes to take effect." "zsh"
        fi
    fi
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Verify ZSH installation
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

# Remove ZSH configuration
remove_zsh() {
    log "INFO" "Removing ZSH configuration..." "zsh"
    
    # Backup existing configs before removal
    for file in "$HOME/.zshenv" "$HOME/.config/zsh/.zshrc"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" "zsh"
        fi
    done
    
    # Remove all zsh-related files and directories
    rm -f "$HOME/.zshenv"
    rm -rf "$HOME/.config/zsh"
    
    # Remove state file
    rm -f "$STATE_FILE"
    
    log "INFO" "ZSH configuration removed" "zsh"
    return 0
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
    finalize)
        # This is a new action to handle final shell change after all other modules
        if [[ "${ZSH_LOGIN_SHELL_PENDING:-0}" -eq 1 ]]; then
            log "INFO" "Finalizing ZSH installation by changing login shell..." "zsh"
            chsh -s "$(command -v zsh)"
            log "INFO" "Shell changed to zsh. Please log out and back in for changes to take effect." "zsh"
        fi
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "zsh"
        log "ERROR" "Usage: $0 {install|remove|verify|info|finalize} [--force]"
        exit 1
        ;;
esac