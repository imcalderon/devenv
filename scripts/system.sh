#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

# System package installation and configuration
load_config

# Install system packages
log "INFO" "Installing system packages..."
sudo dnf update -y
sudo dnf groupinstall -y 'Development Tools'

for package in "${packages[system]}"; do
    if ! rpm -q "$package" &>/dev/null; then
        sudo dnf install -y "$package"
    fi
done

# Install MacBook utilities
for package in "${packages[macbook]}"; do
    if ! rpm -q "$package" &>/dev/null; then
        sudo dnf install -y "$package"
    fi
done
