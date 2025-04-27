#!/bin/bash
# modules/git/git.sh - Git module implementation with ZSH integration

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "git" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/git.state"

# Define module components
COMPONENTS=(
    "core"          # Base Git installation
    "ssh"           # SSH key configuration
    "config"        # Git configuration
    "aliases"       # Git aliases
    "zsh_integration" # ZSH completion and prompt integration
)

# Display module information
show_module_info() {
    cat << 'EOF'

🔄 Git Development Environment
==========================

Description:
-----------
Professional Git environment with SSH key management, 
optimized configurations, ZSH integration, and productivity-enhancing aliases.

Benefits:
--------
✓ Secure Setup - Automated SSH key generation and management
✓ Best Practices - Pre-configured Git settings for optimal workflow
✓ ZSH Integration - Enhanced completion, prompts and aliases
✓ Enhanced Productivity - Curated aliases for common operations
✓ GitHub Ready - Automated GitHub SSH configuration

Components:
----------
1. Core Git
   - Latest Git version
   - SSH client
   - GitHub integration

2. SSH Configuration
   - ED25519 key generation
   - GitHub SSH setup
   - Secure permissions

3. Git Configuration
   - Global settings
   - Default branch config
   - Push/pull behaviors
   - Editor preferences

4. ZSH Integration
   - Advanced completion
   - VCS info in prompt
   - Git status indicators
   - Git keyboard shortcuts

Quick Start:
-----------
1. Check status:
   $ g st

2. Stage and commit:
   $ g a file.txt
   $ g c -m "commit message"

3. Push/pull changes:
   $ g p   # push
   $ g pl  # pull

4. Use ZSH autocompletion:
   $ git che<TAB>   # expands to checkout

Aliases:
-------
g    : git
ga   : git add
gaa  : git add --all
gst  : git status
gc   : git commit -v
gc!  : git commit -v --amend
gp   : git push
gpl  : git pull

Configuration:
-------------
Location: ~/.gitconfig
Key files:
- ~/.gitconfig    : Git configuration
- ~/.ssh/config   : SSH configuration
- ~/.ssh/id_ed25519* : SSH keys
- ~/.config/zsh/git.zsh : ZSH git integration

Tips:
----
• Use gaa to stage all changes
• gc! to amend last commit
• gst for quick status check
• In ZSH, use tab completion for branches
• View status in prompt with ZSH integration

Security Note:
------------
SSH keys are generated with best practices:
• ED25519 algorithm
• Proper permissions
• Passphrase protection (optional)

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v git &>/dev/null; then
                        echo "  Version: $(git --version)"
                    fi
                    ;;
                "ssh")
                    local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
                    ssh_dir=$(eval echo "$ssh_dir")
                    if [[ -f "${ssh_dir}/id_ed25519" ]]; then
                        echo "  SSH Key: Present"
                    fi
                    ;;
                "zsh_integration")
                    if [[ -f "$HOME/.config/zsh/git.zsh" ]]; then
                        echo "  ZSH Integration: Active"
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
            command -v git &>/dev/null
            ;;
        "ssh")
            local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
            ssh_dir=$(eval echo "$ssh_dir")
            [[ -f "${ssh_dir}/id_ed25519" ]] && [[ -f "${ssh_dir}/config" ]]
            ;;
        "config")
            git config --global user.name &>/dev/null && \
            git config --global user.email &>/dev/null
            ;;
        "aliases")
            list_module_aliases "git" "git" &>/dev/null
            ;;
        "zsh_integration")
            [[ -f "$HOME/.config/zsh/git.zsh" ]]
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "git"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_git_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "ssh")
            if configure_ssh; then
                save_state "ssh" "installed"
                return 0
            fi
            ;;
        "config")
            if configure_git; then
                save_state "config" "installed"
                return 0
            fi
            ;;
        "aliases")
            if configure_aliases; then
                save_state "aliases" "installed"
                return 0
            fi
            ;;
        "zsh_integration")
            if configure_zsh_integration; then
                save_state "zsh_integration" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Install core Git
install_git_core() {
    if ! command -v git &>/dev/null; then
        log "INFO" "Installing git..." "git"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y git openssh-client
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git openssh-clients
        else
            log "ERROR" "Unsupported package manager" "git"
            return 1
        fi
    fi
    return 0
}

# Configure ZSH integration for Git
configure_zsh_integration() {
    log "INFO" "Configuring ZSH integration for Git..." "git"
    
    # Check if ZSH is installed
    if ! command -v zsh &>/dev/null; then
        log "WARN" "ZSH not installed, skipping ZSH integration" "git"
        return 0
    fi
    
    # Create ZSH config directory if it doesn't exist
    local zsh_config_dir="$HOME/.config/zsh"
    mkdir -p "$zsh_config_dir"
    
    # Create Git ZSH integration file
    cat > "$zsh_config_dir/git.zsh" << 'EOF'
# Git integration for ZSH

# Load the git plugin if using zsh
# Make sure the fpath includes git's completion functions
fpath=(${fpath[@]} /usr/share/zsh/functions/Completion/Unix)

# Enable and configure vcs_info for git prompt
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' stagedstr '%F{green}●%f'
zstyle ':vcs_info:*' unstagedstr '%F{red}●%f'
zstyle ':vcs_info:*' formats ' %F{blue}[%F{cyan}%b%F{blue}]%f %c%u'
zstyle ':vcs_info:*' actionformats ' %F{blue}[%F{cyan}%b%F{blue}|%F{red}%a%F{blue}]%f %c%u'
zstyle ':vcs_info:git*+set-message:*' hooks git-untracked

# Check for untracked files
+vi-git-untracked() {
  if [[ $(git rev-parse --is-inside-work-tree 2> /dev/null) == 'true' ]] && \
     git status --porcelain | grep -q '^?? ' 2> /dev/null ; then
    hook_com[staged]+='%F{yellow}●%f'
  fi
}

# Update vcs_info before each prompt
precmd() { vcs_info }

# Enable prompt substitution to show vcs_info
setopt prompt_subst

# Git keyboard shortcuts and improvements
function _git_current_branch() {
  local ref
  ref=$(git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # not a git repo
    ref=$(git rev-parse --short HEAD 2> /dev/null) || return
    echo "$ref"
  else
    echo "${ref#refs/heads/}"
  fi
}

# Enhanced git status - shows branch and status in a compact format
alias gst='git status -sb'

# Push the current branch
function gpsh() {
  if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
    echo "Usage: gpsh [remote] [options]"
    echo "Push the current branch to a remote."
    echo "If no remote is specified, 'origin' is used."
    return 0
  fi
  
  local remote="${1:-origin}"
  local branch="$(_git_current_branch)"
  
  if [[ -z "$branch" ]]; then
    echo "Error: Not in a git repository or no current branch."
    return 1
  fi
  
  if [[ "$#" -gt 1 ]]; then
    shift
    git push "$remote" "$branch" "$@"
  else
    git push "$remote" "$branch"
  fi
}

# Pull the current branch
function gpl() {
  if [[ "${1}" == "-h" || "${1}" == "--help" ]]; then
    echo "Usage: gpl [remote] [options]"
    echo "Pull the current branch from a remote."
    echo "If no remote is specified, 'origin' is used."
    return 0
  fi
  
  local remote="${1:-origin}"
  local branch="$(_git_current_branch)"
  
  if [[ -z "$branch" ]]; then
    echo "Error: Not in a git repository or no current branch."
    return 1
  fi
  
  if [[ "$#" -gt 1 ]]; then
    shift
    git pull "$remote" "$branch" "$@"
  else
    git pull "$remote" "$branch"
  fi
}

# Git log with branch graph
alias glg='git log --graph --decorate --oneline'

# Open GitHub repository in browser
if command -v xdg-open &>/dev/null; then
  function ghb() {
    local remote_url=$(git config --get remote.origin.url)
    if [[ -z "$remote_url" ]]; then
      echo "Error: No remote 'origin' found"
      return 1
    fi
    
    # Convert SSH URL to HTTPS URL if needed
    if [[ "$remote_url" =~ ^git@ ]]; then
      remote_url=${remote_url/git@github.com:/https:\/\/github.com\/}
    fi
    
    # Remove .git suffix if present
    remote_url=${remote_url%.git}
    
    xdg-open "$remote_url"
  }
elif command -v open &>/dev/null; then
  # For macOS
  function ghb() {
    local remote_url=$(git config --get remote.origin.url)
    if [[ -z "$remote_url" ]]; then
      echo "Error: No remote 'origin' found"
      return 1
    fi
    
    # Convert SSH URL to HTTPS URL if needed
    if [[ "$remote_url" =~ ^git@ ]]; then
      remote_url=${remote_url/git@github.com:/https:\/\/github.com\/}
    fi
    
    # Remove .git suffix if present
    remote_url=${remote_url%.git}
    
    open "$remote_url"
  }
fi
EOF
    
    # Check if git.zsh is already sourced in .zshrc
    if ! grep -q "source.*git.zsh" "$zsh_config_dir/.zshrc" 2>/dev/null; then
        # Add sourcing directive to .zshrc if it's not already there
        echo -e "\n# Load Git integration\n[[ -f \"\$ZDOTDIR/git.zsh\" ]] && source \"\$ZDOTDIR/git.zsh\"" >> "$zsh_config_dir/.zshrc"
    fi
    
    return 0
}

# Configure SSH
configure_ssh() {
    log "INFO" "Configuring SSH..." "git"

    local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
    ssh_dir=$(eval echo "$ssh_dir")

    # Create SSH directory with proper permissions
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Generate SSH key if it doesn't exist
    if [[ ! -f "${ssh_dir}/id_ed25519" ]]; then
        log "INFO" "Generating SSH key..." "git"
        
        local git_email=$(get_module_config "git" ".git.config[\"user.email\"]")
        if [[ -z "$git_email" ]]; then
            read -p "Enter your email for SSH key: " git_email
        fi

        ssh-keygen -t ed25519 -C "$git_email" -f "${ssh_dir}/id_ed25519" -N ""
    fi

    # Configure SSH config file
    configure_ssh_config || return 1

    return 0
}

# Configure Git
configure_git() {
    log "INFO" "Configuring Git..." "git"

    local configs=($(get_module_config "git" ".git.config | keys[]"))
    
    for key in "${configs[@]}"; do
        local value=$(get_module_config "git" ".git.config[\"$key\"]")
        
        if [[ -z "$value" ]]; then
            case "$key" in
                "user.name")
                    read -p "Enter your Git name: " value
                    ;;
                "user.email")
                    read -p "Enter your Git email: " value
                    ;;
            esac
        fi

        if [[ -n "$value" ]]; then
            git config --global "$key" "$value"
            log "INFO" "Set git config $key = $value" "git"
        fi
    done

    return 0
}

# Configure aliases
configure_aliases() {
    add_module_aliases "git" "git" || return 1
    return 0
}

# Configure SSH config file
configure_ssh_config() {
    local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
    ssh_dir=$(eval echo "$ssh_dir")
    local ssh_config="${ssh_dir}/config"

    [[ -f "$ssh_config" ]] && backup_file "$ssh_config" "git"

    {
        echo "# SSH configuration managed by devenv"
        echo ""

        local hosts=($(get_module_config "git" ".git.ssh.hosts[].host"))
        for host in "${hosts[@]}"; do
            local user=$(get_module_config "git" ".git.ssh.hosts[] | select(.host == \"$host\") | .user")
            local identity=$(get_module_config "git" ".git.ssh.hosts[] | select(.host == \"$host\") | .identity_file")
            identity=$(eval echo "$identity")

            echo "Host $host"
            echo "    User $user"
            echo "    IdentityFile $identity"
            echo "    IdentitiesOnly yes"
            echo ""
        done
    } > "$ssh_config"

    chmod 600 "$ssh_config"
    ssh-keyscan github.com >> "${ssh_dir}/known_hosts" 2>/dev/null

    return 0
}

# Grovel checks existence and basic functionality
grovel_git() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "git"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_git() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_git &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "git"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "git"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "git"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Remove Git configuration
remove_git() {
    log "INFO" "Removing Git configuration..." "git"

    # Backup existing configurations
    local git_config=$(get_module_config "git" ".shell.paths.git_config")
    git_config=$(eval echo "$git_config")
    [[ -f "$git_config" ]] && backup_file "$git_config" "git"
    
    local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
    ssh_dir=$(eval echo "$ssh_dir")
    [[ -f "${ssh_dir}/config" ]] && backup_file "${ssh_dir}/config" "git"

    # Remove git config
    rm -f "$git_config"

    # Remove SSH config but preserve keys
    rm -f "${ssh_dir}/config"

    # Remove ZSH integration
    rm -f "$HOME/.config/zsh/git.zsh"
    
    # Edit .zshrc to remove git.zsh source line
    if [[ -f "$HOME/.config/zsh/.zshrc" ]]; then
        sed -i '/# Load Git integration/d' "$HOME/.config/zsh/.zshrc"
        sed -i '/source.*git.zsh/d' "$HOME/.config/zsh/.zshrc"
    fi

    # Remove git aliases
    remove_module_aliases "git" "git"

    # Remove state file
    rm -f "$STATE_FILE"

    log "INFO" "Git configuration removed" "git"
    log "WARN" "SSH keys were preserved for safety. Remove manually if needed." "git"

    return 0
}

# Verify entire installation
verify_git() {
    log "INFO" "Verifying Git installation..." "git"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "git"
            status=1
        fi
    done

    # Additional GitHub SSH verification
    if [ $status -eq 0 ]; then
        log "INFO" "Testing GitHub SSH connection..." "git"
        if ! ssh -T git@github.com -o BatchMode=yes -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
            log "WARN" "GitHub SSH authentication failed" "git"
            status=1
        else
            log "INFO" "GitHub SSH connection successful" "git"
        fi
    fi
    
    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_git
        ;;
    install)
        install_git "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_git
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_git
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "git"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac