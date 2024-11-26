#!/bin/bash
# modules/git/git.sh - Git module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/alias.sh"    # For shell alias support

# Initialize module
init_module "git" || exit 1

# Check for git installation and configuration
grovel_git() {
    if ! command -v git &>/dev/null; then
        log "INFO" "Git not found" "git"
        return 1
    fi

    # Check for SSH directory and keys
    local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
    ssh_dir=$(eval echo "$ssh_dir")
    
    if [[ ! -f "${ssh_dir}/id_ed25519" ]]; then
        log "INFO" "SSH key not found" "git"
        return 1
    fi

    # Verify git configuration
    if ! git config --global user.name &>/dev/null || ! git config --global user.email &>/dev/null; then
        log "INFO" "Git user configuration incomplete" "git"
        return 1
    fi

    return 0
}

# Install and configure git
install_git() {
    log "INFO" "Setting up Git environment..." "git"

    # Install git if needed
    if ! command -v git &>/dev/null; then
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

    # Configure SSH
    configure_ssh || return 1

    # Configure git
    configure_git || return 1

    # Add git aliases
    add_module_aliases "git" "git" || return 1

    return 0
}

# Configure SSH for git
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
        
        # Get user input for key generation
        local git_email=$(get_module_config "git" ".git.config[\"user.email\"]")
        if [[ -z "$git_email" ]]; then
            read -p "Enter your email for SSH key: " git_email
        fi

        ssh-keygen -t ed25519 -C "$git_email" -f "${ssh_dir}/id_ed25519" -N ""
    fi

    # Configure SSH config file
    local ssh_config="${ssh_dir}/config"

    # Backup existing config if it exists
    [[ -f "$ssh_config" ]] && backup_file "$ssh_config" "git"

    # Create new config
    {
        echo "# SSH configuration managed by devenv"
        echo ""

        # Add host configurations from config
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

    # Add GitHub to known hosts
    ssh-keyscan github.com >> "${ssh_dir}/known_hosts" 2>/dev/null

    # Start ssh-agent and add key
    eval "$(ssh-agent -s)"
    ssh-add "${ssh_dir}/id_ed25519"

    # Display public key for GitHub setup
    log "INFO" "Your public SSH key (add this to GitHub):" "git"
    cat "${ssh_dir}/id_ed25519.pub"

    return 0
}

# Configure git global settings
configure_git() {
    log "INFO" "Configuring Git..." "git"

    # Get configurations from config file
    local configs=($(get_module_config "git" ".git.config | keys[]"))
    
    for key in "${configs[@]}"; do
        local value=$(get_module_config "git" ".git.config[\"$key\"]")
        
        # If value is empty and it's a required field, prompt user
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

# Remove git configuration
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

    log "INFO" "Git configuration removed" "git"
    log "WARN" "SSH keys were preserved for safety. Remove manually if needed." "git"

    return 0
}

# Verify git installation and configuration
verify_git() {
    log "INFO" "Verifying Git installation..." "git"
    local status=0

    # Check git installation
    if ! command -v git &>/dev/null; then
        log "ERROR" "Git is not installed" "git"
        status=1
    fi

    # Verify git configuration
    local required_configs=("user.name" "user.email")
    for config in "${required_configs[@]}"; do
        if ! git config --global --get "$config" &>/dev/null; then
            log "ERROR" "Git $config is not configured" "git"
            status=1
        fi
    done

    # Check SSH configuration
    local ssh_dir=$(get_module_config "git" ".shell.paths.ssh_dir")
    ssh_dir=$(eval echo "$ssh_dir")
    
    if [[ ! -f "${ssh_dir}/id_ed25519" ]]; then
        log "ERROR" "SSH key not found" "git"
        status=1
    fi

    # Test GitHub SSH connection with more detailed error handling
    log "DEBUG" "Testing GitHub SSH connection..." "git"
    if ! ssh -T git@github.com -o BatchMode=yes -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
        # Check specific SSH issues
        if ! ssh-add -l &>/dev/null; then
            log "ERROR" "SSH agent has no keys loaded. Running ssh-add..." "git"
            eval "$(ssh-agent -s)" >/dev/null
            ssh-add "${ssh_dir}/id_ed25519" || {
                log "ERROR" "Failed to add SSH key to agent" "git"
                status=1
            }
        fi
        
        # Test connection again after loading key
        if ! ssh -T git@github.com -o BatchMode=yes -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
            log "ERROR" "GitHub SSH authentication failed. Please ensure your key is added to GitHub" "git"
            log "INFO" "Your public key for GitHub:" "git"
            cat "${ssh_dir}/id_ed25519.pub"
            status=1
        fi
    else
        log "INFO" "GitHub SSH connection successful" "git"
    fi

    # Verify aliases
    if ! list_module_aliases "git" "git" &>/dev/null; then
        log "ERROR" "Git aliases not configured" "git"
        status=1
    fi

    if [ $status -eq 0 ]; then
        log "INFO" "Git verification completed successfully" "git"
    else
        log "ERROR" "Git verification failed" "git"
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_git
        ;;
    install)
        install_git
        ;;
    remove)
        remove_git
        ;;
    verify)
        verify_git
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "git"
        exit 1
        ;;
esac
