#!/bin/bash
# setup-devenv.sh - Run inside WSL after bootstrap to set up devenv development environment
# Usage: /mnt/e/WSL/setup-devenv.sh

set -e

echo "=== DevEnv Development Setup ==="
echo ""

# Ensure we're not root
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Run this as your normal user, not root"
    exit 1
fi

DEVENV_DIR="$HOME/vfx-devenv"
SECRETS_FILE="$HOME/.config/devenv/secrets.env"

# --- Load secrets if available ---
if [[ -f "$SECRETS_FILE" ]]; then
    echo "Loading secrets from $SECRETS_FILE"
    source "$SECRETS_FILE"
fi

# --- Clone or update vfx-devenv ---
echo "=== Setting up vfx-devenv ==="
if [[ -d "$DEVENV_DIR" ]]; then
    echo "vfx-devenv already exists, pulling latest..."
    cd "$DEVENV_DIR"
    git pull origin main
    git submodule update --init --recursive
else
    echo "Cloning vfx-devenv..."
    git clone --recurse-submodules https://github.com/imcalderon/vfx-devenv.git "$DEVENV_DIR"
fi

# --- Run vfx-devenv init ---
echo ""
echo "=== Running vfx-devenv init ==="
cd "$DEVENV_DIR"
./vfx-devenv init vfx_platform

# --- Install Claude Code ---
echo ""
echo "=== Installing Claude Code ==="
if command -v npm &>/dev/null; then
    npm install -g @anthropic-ai/claude-code
    echo "Claude Code installed"
else
    echo "WARNING: npm not found. Run 'devenv install nodejs' first, then:"
    echo "  npm install -g @anthropic-ai/claude-code"
fi

# --- Install GitHub CLI if not present ---
echo ""
echo "=== Installing GitHub CLI ==="
if ! command -v gh &>/dev/null; then
    if command -v dnf &>/dev/null; then
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
        sudo dnf install -y gh --repo gh-cli
    fi
fi

if command -v gh &>/dev/null; then
    echo "GitHub CLI version: $(gh --version | head -1)"
    if ! gh auth status &>/dev/null 2>&1; then
        echo ""
        echo "NOTE: Run 'gh auth login' to authenticate with GitHub"
    fi
fi

# --- Summary ---
echo ""
echo "=========================================="
echo "=== Setup Complete ==="
echo "=========================================="
echo ""
echo "Installed:"
echo "  - vfx-devenv: $DEVENV_DIR"
command -v claude &>/dev/null && echo "  - Claude Code: $(claude --version 2>/dev/null || echo 'installed')"
command -v gh &>/dev/null && echo "  - GitHub CLI: $(gh --version | head -1)"
echo ""
echo "DevEnv Open Issues:"
echo "  #28 - Add configuration validation and schema"
echo "  #24 - Implement automatic rollback on failure"
echo "  #29 - Add environment templates/profiles"
echo "  #27 - Complete macOS platform support"
echo "  #23 - Add module README documentation"
echo ""
echo "Secrets:"
echo "  Edit ~/.config/devenv/secrets.env to add:"
echo "  - GIT_USER_NAME, GIT_USER_EMAIL"
echo "  - GITHUB_TOKEN, ANTHROPIC_API_KEY"
echo "  (Never commit this file!)"
echo ""
echo "To start working:"
echo "  cd ~/vfx-devenv"
echo "  gh auth login                    # One-time auth"
echo "  gh issue list                    # View issues"
echo "  claude                           # Start Claude Code"
echo ""
echo "Future: HashiCorp Vault module planned for enterprise secrets"
echo ""
