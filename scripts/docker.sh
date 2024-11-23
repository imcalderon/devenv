#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

load_config

install_docker() {
    if ! command -v docker &> /dev/null; then
        log "INFO" "Installing Docker..."
        sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    fi

    # Configure Docker daemon
    sudo mkdir -p /etc/docker
    yq eval -j "${docker[daemon_config]}" | sudo tee /etc/docker/daemon.json

    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
}

install_docker
