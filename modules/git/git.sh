#!/bin/bash
# modules/git/git.sh - Git module implementation

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
)

# Display module information
show_module_info() {
    cat << 'EOF'

🔄 Git Development Environment
==========================

Description:
-----------
Professional Git environment with SSH key management, 
optimized configurations, and productivity-enhancing aliases.

Benefits:
--------
✓ Secure Setup - Automated SSH key generation and management
✓ Best Practices - Pre-configured Git settings for optimal workflow
✓ Enhanced Productivity - Curated aliases for common operations
✓ GitHub Ready - Automated GitHub SSH configuration
✓ Backup Support - Automated backup of all configurations

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

Quick Start:
-----------
1. Check status:
   $ gst

2. Stage and commit:
   $ ga file.txt
   $ gc -m "commit message"

3. Push/pull changes:
   $ gp   # push
   $ gpl  # pull

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

Tips:
----
• Use gaa to stage all changes
• gc! to amend last commit
• gst for quick status check
• Always pull before pushing

Security Note:
------------
SSH keys are generated with best practices:
• ED25519 algorithm
• Proper permissions
• Passphrase protection (optional)

For more information:
-------------------
Documentation: https://git-scm.com/doc
GitHub Guide: https://docs.github.com/authentication

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
            log "ERROR" "GitHub SSH authentication failed" "git"
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