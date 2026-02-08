#!/usr/bin/env bash
# vfx-bootstrap - Git setup module
# Provides functions for managing git installations and configuration

set -euo pipefail

#------------------------------------------------------------------------------
# Check if git is installed
#------------------------------------------------------------------------------
is_git_installed() {
    command -v git &>/dev/null
}

#------------------------------------------------------------------------------
# Get git version
#------------------------------------------------------------------------------
get_git_version() {
    if is_git_installed; then
        git --version | awk '{print $3}'
    else
        echo ""
    fi
}

#------------------------------------------------------------------------------
# Install git
#------------------------------------------------------------------------------
install_git() {
    if is_git_installed; then
        echo "Git already installed: $(get_git_version)"
        return 0
    fi

    echo "Installing git..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y git
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
    elif command -v yum &>/dev/null; then
        sudo yum install -y git
    elif command -v brew &>/dev/null; then
        brew install git
    else
        echo "Unable to determine package manager. Please install git manually."
        return 1
    fi

    echo "Git installed: $(get_git_version)"
}

#------------------------------------------------------------------------------
# Configure git for development
#------------------------------------------------------------------------------
configure_git() {
    local name="${1:-}"
    local email="${2:-}"

    if [[ -z "$name" ]]; then
        read -p "Enter your name for git commits: " name
    fi

    if [[ -z "$email" ]]; then
        read -p "Enter your email for git commits: " email
    fi

    echo "Configuring git..."

    # User configuration
    git config --global user.name "$name"
    git config --global user.email "$email"

    # Default branch
    git config --global init.defaultBranch main

    # Push behavior
    git config --global push.default current
    git config --global push.autoSetupRemote true

    # Pull behavior
    git config --global pull.rebase false

    # Better diff
    git config --global diff.algorithm histogram

    # Auto-correct typos (with delay)
    git config --global help.autocorrect 10

    echo "Git configured for user: $name <$email>"
}

#------------------------------------------------------------------------------
# Setup SSH for GitHub
#------------------------------------------------------------------------------
setup_github_ssh() {
    local email="${1:-}"
    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/id_ed25519"

    if [[ -z "$email" ]]; then
        email=$(git config --global user.email 2>/dev/null || echo "")
        if [[ -z "$email" ]]; then
            read -p "Enter your email for SSH key: " email
        fi
    fi

    # Create SSH directory
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Generate key if it doesn't exist
    if [[ ! -f "$key_file" ]]; then
        echo "Generating SSH key..."
        ssh-keygen -t ed25519 -C "$email" -f "$key_file" -N ""
        echo "SSH key generated: $key_file"
    else
        echo "SSH key already exists: $key_file"
    fi

    # Configure SSH for GitHub
    local ssh_config="$ssh_dir/config"
    if ! grep -q "Host github.com" "$ssh_config" 2>/dev/null; then
        echo "Configuring SSH for GitHub..."
        cat >> "$ssh_config" << EOF

Host github.com
    User git
    IdentityFile $key_file
    IdentitiesOnly yes
EOF
        chmod 600 "$ssh_config"
    fi

    # Add GitHub to known hosts
    ssh-keyscan github.com >> "$ssh_dir/known_hosts" 2>/dev/null || true

    echo ""
    echo "Your SSH public key (add to GitHub):"
    echo "======================================"
    cat "${key_file}.pub"
    echo ""
    echo "Add this key at: https://github.com/settings/ssh/new"
}

#------------------------------------------------------------------------------
# Verify GitHub SSH connection
#------------------------------------------------------------------------------
verify_github_ssh() {
    echo "Testing GitHub SSH connection..."

    if ssh -T git@github.com -o BatchMode=yes -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
        echo "GitHub SSH connection successful!"
        return 0
    else
        echo "GitHub SSH connection failed."
        echo "Make sure you've added your SSH key to GitHub."
        return 1
    fi
}

#------------------------------------------------------------------------------
# Clone repository
#------------------------------------------------------------------------------
clone_repo() {
    local url="$1"
    local dest="${2:-}"

    if [[ -z "$url" ]]; then
        echo "Usage: clone_repo <url> [destination]"
        return 1
    fi

    if [[ -z "$dest" ]]; then
        dest=$(basename "$url" .git)
    fi

    if [[ -d "$dest/.git" ]]; then
        echo "Repository already exists at $dest"
        return 0
    fi

    echo "Cloning $url to $dest..."
    git clone "$url" "$dest"
    echo "Repository cloned successfully"
}

#------------------------------------------------------------------------------
# Print git info
#------------------------------------------------------------------------------
print_git_info() {
    echo "Git Installation Info:"
    echo "======================"

    if is_git_installed; then
        echo "Version: $(get_git_version)"
        echo ""
        echo "Configuration:"
        echo "  user.name: $(git config --global user.name 2>/dev/null || echo '<not set>')"
        echo "  user.email: $(git config --global user.email 2>/dev/null || echo '<not set>')"
        echo "  init.defaultBranch: $(git config --global init.defaultBranch 2>/dev/null || echo '<not set>')"
        echo ""
        echo "SSH key status:"
        if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
            echo "  Ed25519 key: present"
        elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
            echo "  RSA key: present"
        else
            echo "  No SSH key found"
        fi
    else
        echo "Git not installed"
    fi
}

#------------------------------------------------------------------------------
# Main entry point
#------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-info}" in
        install)
            install_git
            ;;
        configure)
            configure_git "${2:-}" "${3:-}"
            ;;
        setup-ssh)
            setup_github_ssh "${2:-}"
            ;;
        verify-ssh)
            verify_github_ssh
            ;;
        clone)
            clone_repo "${2:-}" "${3:-}"
            ;;
        info)
            print_git_info
            ;;
        *)
            echo "Usage: $0 {install|configure|setup-ssh|verify-ssh|clone|info}"
            exit 1
            ;;
    esac
fi
