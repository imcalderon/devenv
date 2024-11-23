#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

setup_docker() {
    if ! command -v docker &> /dev/null; then
        log "INFO" "Installing Docker..."
        sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    fi
    
    if [ ! -f "/etc/docker/daemon.json" ]; then
        sudo mkdir -p /etc/docker
        cat << EOF | sudo tee /etc/docker/daemon.json
{
    "default-memory-swap": "1G",
    "memory": "8G",
    "cpu-shares": 1024,
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
    fi
    
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
}
