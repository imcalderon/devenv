#!/bin/bash
# bootstrap-wsl.sh - Minimal WSL bootstrap for devenv
# Creates user, sets up sudo, installs only what's needed to run devenv

set -e

echo "=== Minimal WSL Bootstrap for DevEnv ==="

# --- Configuration ---
USERNAME="${1:-imcalderon}"
PASSWORD="${2:-devenv}"
TIMEZONE="${3:-America/Chicago}"

echo "User: $USERNAME"
echo "Timezone: $TIMEZONE"

# --- Timezone ---
echo "=== Setting timezone ==="
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime 2>/dev/null || true

# --- Create user ---
echo "=== Creating user $USERNAME ==="
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -G wheel "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "User $USERNAME created"
else
    echo "User $USERNAME already exists"
fi

# --- Configure sudo (passwordless for dev environment) ---
echo "=== Configuring passwordless sudo ==="
# Create a dedicated sudoers drop-in file for clean passwordless sudo
cat > /etc/sudoers.d/99-devenv-nopasswd << 'SUDOERS'
# DevEnv: Allow wheel group passwordless sudo for development
%wheel ALL=(ALL) NOPASSWD: ALL
SUDOERS
chmod 440 /etc/sudoers.d/99-devenv-nopasswd

# Verify sudoers syntax
visudo -cf /etc/sudoers.d/99-devenv-nopasswd || rm -f /etc/sudoers.d/99-devenv-nopasswd

# --- Install minimal packages needed to run devenv ---
echo "=== Installing minimal bootstrap packages ==="
dnf install -y --setopt=install_weak_deps=False \
    git \
    jq \
    curl \
    sudo

# --- Install GitHub CLI ---
echo "=== Installing GitHub CLI ==="
dnf install -y 'dnf-command(config-manager)'
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh --repo gh-cli

# --- Configure WSL ---
echo "=== Configuring WSL ==="
cat > /etc/wsl.conf << EOF
[user]
default=$USERNAME

[interop]
enabled=true
appendWindowsPath=true

[network]
generateHosts=true
generateResolvConf=true
EOF

# --- Create secrets config template ---
echo "=== Creating secrets config template ==="
SECRETS_DIR="/home/$USERNAME/.config/devenv"
mkdir -p "$SECRETS_DIR"
cat > "$SECRETS_DIR/secrets.env.template" << 'SECRETS'
# DevEnv Secrets Configuration
# Copy this file to secrets.env and fill in your values
# This file should NEVER be committed to version control
#
# Usage: source ~/.config/devenv/secrets.env

# Git configuration
export GIT_USER_NAME=""
export GIT_USER_EMAIL=""

# GitHub
export GITHUB_TOKEN=""

# Anthropic (Claude)
export ANTHROPIC_API_KEY=""

# HashiCorp Vault (optional - for enterprise secrets management)
# export VAULT_ADDR=""
# export VAULT_TOKEN=""

# Custom secrets
# export MY_SECRET=""
SECRETS

# Create empty secrets.env if it doesn't exist
if [[ ! -f "$SECRETS_DIR/secrets.env" ]]; then
    cp "$SECRETS_DIR/secrets.env.template" "$SECRETS_DIR/secrets.env"
fi
chmod 600 "$SECRETS_DIR/secrets.env" "$SECRETS_DIR/secrets.env.template"
chown -R "$USERNAME:$USERNAME" "$SECRETS_DIR"

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "  1. Exit and restart WSL: wsl --shutdown && wsl -d <distro>"
echo "  2. Run full setup: /mnt/e/WSL/setup-devenv.sh"
echo "     Or manually:"
echo "       git clone --recurse-submodules https://github.com/imcalderon/vfx-devenv.git ~/vfx-devenv"
echo "       cd ~/vfx-devenv && ./vfx-devenv init vfx_platform"
echo "       npm install -g @anthropic-ai/claude-code"
echo ""
echo "User: $USERNAME"
echo "Password: $PASSWORD (change with 'passwd')"
