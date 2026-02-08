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

DEVENV_DIR="$HOME/devenv"
SECRETS_FILE="$HOME/.config/devenv/secrets.env"

# --- Load secrets if available ---
if [[ -f "$SECRETS_FILE" ]]; then
    echo "Loading secrets from $SECRETS_FILE"
    source "$SECRETS_FILE"
fi

# --- Clone or update devenv ---
echo "=== Setting up devenv ==="
if [[ -d "$DEVENV_DIR" ]]; then
    echo "devenv already exists, pulling latest..."
    cd "$DEVENV_DIR"
    git pull origin main
else
    echo "Cloning devenv..."
    git clone https://github.com/imcalderon/devenv.git "$DEVENV_DIR"
fi

# --- Run devenv init ---
echo ""
echo "=== Running devenv init ==="
cd "$DEVENV_DIR"
./devenv init vfx_platform

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
echo "  - devenv: $DEVENV_DIR"
command -v claude &>/dev/null && echo "  - Claude Code: $(claude --version 2>/dev/null || echo 'installed')"
command -v gh &>/dev/null && echo "  - GitHub CLI: $(gh --version | head -1)"
echo ""
echo "Secrets:"
echo "  Edit ~/.config/devenv/secrets.env to add:"
echo "  - GIT_USER_NAME, GIT_USER_EMAIL"
echo "  - GITHUB_TOKEN, ANTHROPIC_API_KEY"
echo "  (Never commit this file!)"
echo ""
echo "To start working:"
echo "  cd ~/devenv"
echo "  gh auth login                    # One-time auth"
echo "  gh issue list                    # View issues"
echo "  claude                           # Start Claude Code"
echo ""
