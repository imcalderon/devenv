#!/bin/bash
# bootstrap-wsl.sh - Minimal WSL bootstrap for AlmaLinux 10
# Creates user, sets up sudo, installs only what's needed to run devenv
# Run as root inside WSL: wsl -d AlmaLinux10 --user root -- bash bootstrap-wsl.sh

set -euo pipefail

echo "=== Minimal WSL Bootstrap for DevEnv (AlmaLinux 10) ==="

# --- Configuration ---
USERNAME="${1:-devuser}"
PASSWORD="${2:-devenv}"
TIMEZONE="${3:-America/Chicago}"

echo "User: $USERNAME"
echo "Timezone: $TIMEZONE"

# --- Timezone ---
echo "=== Setting timezone ==="
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime 2>/dev/null || true

# --- Enable EPEL and CRB repos ---
echo "=== Enabling EPEL and CRB repositories ==="
dnf install -y --setopt=install_weak_deps=False epel-release
dnf config-manager --set-enabled crb 2>/dev/null || \
    dnf config-manager --set-enabled powertools 2>/dev/null || true

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
    sudo \
    tar \
    gzip \
    which \
    findutils \
    procps-ng

# --- Install development tools (needed for VFX builds, conda, etc.) ---
echo "=== Installing development tools ==="
dnf group install -y "Development Tools" --setopt=install_weak_deps=False 2>/dev/null || \
    dnf install -y --setopt=install_weak_deps=False gcc gcc-c++ make cmake

# --- Install GitHub CLI ---
echo "=== Installing GitHub CLI ==="
dnf install -y 'dnf-command(config-manager)' 2>/dev/null || true
dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
dnf install -y gh --repo gh-cli

# --- Install Node.js (via nvm) and Claude Code ---
echo "=== Installing Node.js via nvm and Claude Code ==="
su - "$USERNAME" -c '
set -e
echo "Installing nvm..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "Installing Node.js LTS..."
nvm install --lts
nvm use --lts

echo "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code
'

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

[boot]
systemd=true
EOF

# --- Load secrets.local if available (mounted from Windows host) ---
# The PowerShell scripts pass the secrets.local path as $4 if it exists
SECRETS_LOCAL="${4:-}"
declare -A SEED_VALUES=()
if [[ -n "$SECRETS_LOCAL" && -f "$SECRETS_LOCAL" ]]; then
    echo "=== Loading seed values from secrets.local ==="
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        [[ -z "$key" || "$key" == \#* ]] && continue
        value=$(echo "$value" | xargs | sed 's/^["'\''"]//;s/["'\''"]$//')
        [[ -n "$value" ]] && SEED_VALUES["$key"]="$value"
    done < "$SECRETS_LOCAL"
fi

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

# Create secrets.env seeded with values from secrets.local (or empty from template)
if [[ ! -f "$SECRETS_DIR/secrets.env" ]]; then
    cp "$SECRETS_DIR/secrets.env.template" "$SECRETS_DIR/secrets.env"
fi

# Seed values from secrets.local into secrets.env
if [[ ${#SEED_VALUES[@]} -gt 0 ]]; then
    echo "Seeding secrets.env with values from secrets.local..."
    for key in GIT_USER_NAME GIT_USER_EMAIL GITHUB_TOKEN ANTHROPIC_API_KEY; do
        if [[ -n "${SEED_VALUES[$key]:-}" ]]; then
            # Replace the empty export line with the seeded value
            sed -i "s|^export ${key}=\"\"|export ${key}=\"${SEED_VALUES[$key]}\"|" "$SECRETS_DIR/secrets.env"
            echo "  Seeded: $key"
        fi
    done
fi
chmod 600 "$SECRETS_DIR/secrets.env" "$SECRETS_DIR/secrets.env.template"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.config"

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Installed: git, jq, curl, gh, dev tools"
echo "  Node.js: $(su - "$USERNAME" -c 'bash -lc "node --version"' 2>/dev/null || echo 'n/a')"
echo "  Claude:  $(su - "$USERNAME" -c 'bash -lc "claude --version"' 2>/dev/null || echo 'n/a')"
echo ""
echo "WSL will restart to apply wsl.conf settings."
echo ""
echo "User: $USERNAME"
echo "Password: $PASSWORD (change with 'passwd')"
