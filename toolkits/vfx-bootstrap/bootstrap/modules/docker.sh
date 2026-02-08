#!/usr/bin/env bash
# vfx-bootstrap - Docker setup module
# Provides functions for managing Docker/Podman for containerized builds

set -euo pipefail

#------------------------------------------------------------------------------
# Check if running in WSL
#------------------------------------------------------------------------------
is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

#------------------------------------------------------------------------------
# Check if Docker is installed
#------------------------------------------------------------------------------
is_docker_installed() {
    command -v docker &>/dev/null
}

#------------------------------------------------------------------------------
# Check if Docker daemon is running
#------------------------------------------------------------------------------
is_docker_running() {
    docker info &>/dev/null 2>&1
}

#------------------------------------------------------------------------------
# Get Docker version
#------------------------------------------------------------------------------
get_docker_version() {
    if is_docker_installed; then
        docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
    else
        echo ""
    fi
}

#------------------------------------------------------------------------------
# Install Docker
#------------------------------------------------------------------------------
install_docker() {
    if is_docker_installed; then
        echo "Docker already installed: $(get_docker_version)"
        return 0
    fi

    echo "Installing Docker..."

    if is_wsl; then
        echo "WSL detected. Docker should be installed via Docker Desktop for Windows."
        echo "Please install Docker Desktop and enable WSL integration."
        echo "See: https://docs.docker.com/desktop/wsl/"
        return 1
    fi

    if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # Set up repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v dnf &>/dev/null; then
        # Fedora/RHEL
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v brew &>/dev/null; then
        # macOS
        echo "On macOS, please install Docker Desktop:"
        echo "  brew install --cask docker"
        echo "Or download from: https://www.docker.com/products/docker-desktop"
        return 1

    else
        echo "Unable to determine package manager."
        echo "Please install Docker manually: https://docs.docker.com/engine/install/"
        return 1
    fi

    echo "Docker installed: $(get_docker_version)"
}

#------------------------------------------------------------------------------
# Configure Docker for non-root usage
#------------------------------------------------------------------------------
configure_docker_user() {
    echo "Configuring Docker for non-root usage..."

    # Create docker group if it doesn't exist
    if ! getent group docker &>/dev/null; then
        sudo groupadd docker
    fi

    # Add current user to docker group
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        sudo usermod -aG docker "$USER"
        echo "Added $USER to docker group"
        echo "NOTE: You may need to log out and back in for this to take effect"
    else
        echo "User $USER is already in docker group"
    fi
}

#------------------------------------------------------------------------------
# Start Docker service
#------------------------------------------------------------------------------
start_docker_service() {
    if is_wsl; then
        echo "In WSL, Docker is managed by Docker Desktop"
        echo "Please ensure Docker Desktop is running"
        return 0
    fi

    echo "Starting Docker service..."

    if command -v systemctl &>/dev/null; then
        sudo systemctl start docker
        sudo systemctl enable docker
        echo "Docker service started and enabled"
    else
        echo "Systemctl not available. Please start Docker manually."
        return 1
    fi
}

#------------------------------------------------------------------------------
# Check Docker Compose
#------------------------------------------------------------------------------
check_docker_compose() {
    if docker compose version &>/dev/null; then
        echo "Docker Compose (plugin): $(docker compose version --short)"
        return 0
    elif command -v docker-compose &>/dev/null; then
        echo "Docker Compose (standalone): $(docker-compose --version | awk '{print $4}')"
        return 0
    else
        echo "Docker Compose not installed"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Pull VFX build images
#------------------------------------------------------------------------------
pull_build_images() {
    echo "Pulling VFX build images..."

    local images=(
        "ubuntu:22.04"
        "rockylinux:8"
    )

    for image in "${images[@]}"; do
        echo "Pulling $image..."
        docker pull "$image" || echo "Failed to pull $image"
    done

    echo "Build images pulled"
}

#------------------------------------------------------------------------------
# Create VFX build container
#------------------------------------------------------------------------------
create_build_container() {
    local name="${1:-vfx-build}"
    local image="${2:-ubuntu:22.04}"

    echo "Creating VFX build container: $name (from $image)"

    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "Container $name already exists"
        return 0
    fi

    docker create \
        --name "$name" \
        --hostname "$name" \
        -v "$HOME/vfx-bootstrap:/vfx-bootstrap:rw" \
        -v "$HOME/.conda:/root/.conda:rw" \
        -it \
        "$image" \
        /bin/bash

    echo "Container $name created"
}

#------------------------------------------------------------------------------
# Print Docker info
#------------------------------------------------------------------------------
print_docker_info() {
    echo "Docker Installation Info:"
    echo "========================="

    if is_docker_installed; then
        echo "Version: $(get_docker_version)"

        if is_docker_running; then
            echo "Status: Running"
            echo ""
            echo "Docker info:"
            docker info --format '  Server Version: {{.ServerVersion}}'
            docker info --format '  Storage Driver: {{.Driver}}'
            docker info --format '  OS/Arch: {{.OSType}}/{{.Architecture}}'
            echo ""
            check_docker_compose
        else
            echo "Status: Not running"
            if is_wsl; then
                echo ""
                echo "In WSL, ensure Docker Desktop is running with WSL integration enabled."
            fi
        fi
    else
        echo "Docker not installed"
    fi
}

#------------------------------------------------------------------------------
# Main entry point
#------------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-info}" in
        install)
            install_docker
            ;;
        configure)
            configure_docker_user
            ;;
        start)
            start_docker_service
            ;;
        pull-images)
            pull_build_images
            ;;
        create-container)
            create_build_container "${2:-vfx-build}" "${3:-ubuntu:22.04}"
            ;;
        info)
            print_docker_info
            ;;
        *)
            echo "Usage: $0 {install|configure|start|pull-images|create-container|info}"
            exit 1
            ;;
    esac
fi
