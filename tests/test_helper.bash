#!/bin/bash
# tests/test_helper.bash - Common test setup

# Set up test environment variables
export DEVENV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVENV_DATA_DIR="$(mktemp -d)"
export DEVENV_STATE_DIR="$DEVENV_DATA_DIR/state"
export DEVENV_LOGS_DIR="$DEVENV_DATA_DIR/logs"
export DEVENV_BACKUPS_DIR="$DEVENV_DATA_DIR/backups"
export MODULES_DIR="$DEVENV_ROOT/modules"
export SCRIPT_DIR="$DEVENV_ROOT/lib"
export CONFIG_FILE="$DEVENV_ROOT/config.json"
export HOME="$(mktemp -d)"
export LOG_LEVEL="ERROR"

# Create required directories
mkdir -p "$DEVENV_STATE_DIR" "$DEVENV_LOGS_DIR" "$DEVENV_BACKUPS_DIR"
mkdir -p "$HOME/.devenv/logs"

# Source libraries
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"

# Cleanup on exit
teardown() {
    rm -rf "$DEVENV_DATA_DIR"
}
