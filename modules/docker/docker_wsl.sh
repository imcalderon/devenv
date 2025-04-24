#!/bin/bash
# modules/docker/docker_wsl.sh - Docker WSL integration helper

# Check if running in WSL
if ! grep -q "microsoft" /proc/version 2>/dev/null; then
    echo "This script is intended to be run in WSL only."
    exit 1
fi

# Check if Docker Desktop is installed on Windows
if ! command -v docker.exe &>/dev/null; then
    echo "Docker Desktop for Windows is not installed or not in PATH."
    echo "Please install Docker Desktop for Windows first."
    exit 1
fi

# Function to check Docker Desktop status
check_docker_desktop() {
    # Check if Docker Desktop is running using PowerShell
    local status=$(powershell.exe -Command "Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue | Select-Object -Property Name | Measure-Object | Select-Object -ExpandProperty Count")
    
    if [[ "$status" -gt 0 ]]; then
        echo "Docker Desktop is running."
        return 0
    else
        echo "Docker Desktop is not running."
        return 1
    fi
}

# Function to start Docker Desktop
start_docker_desktop() {
    echo "Starting Docker Desktop..."
    
    # Use PowerShell to start Docker Desktop
    powershell.exe -Command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'"
    
    # Wait for Docker Desktop to start
    local timeout=60
    local elapsed=0
    
    while ! check_docker_desktop && [[ $elapsed -lt $timeout ]]; do
        echo "Waiting for Docker Desktop to start... ($elapsed seconds)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    if check_docker_desktop; then
        echo "Docker Desktop started successfully."
        return 0
    else
        echo "Failed to start Docker Desktop within timeout."
        return 1
    fi
}

# Function to configure Docker for WSL
configure_docker() {
    # Check if Docker is already configured for WSL
    if docker info &>/dev/null; then
        echo "Docker is already configured for WSL."
        return 0
    fi
    
    # Check if Docker Desktop is running
    if ! check_docker_desktop; then
        start_docker_desktop || return 1
    fi
    
    # Give Docker a moment to set up
    sleep 5
    
    # Check if docker client can connect
    if ! docker info &>/dev/null; then
        echo "Configuring Docker for WSL..."
        
        # Create .docker directory if it doesn't exist
        mkdir -p ~/.docker
        
        # Check if docker-credential-desktop.exe exists
        if [ -e "/mnt/c/Program Files/Docker/Docker/resources/bin/docker-credential-desktop.exe" ]; then
            echo "Configuring Docker credentials helper..."
            cat > ~/.docker/config.json << EOF
{
  "credsStore": "desktop.exe"
}
EOF
        fi
        
        # Set Docker environment variables in .bashrc or .zshrc
        local shell_rc=~/.bashrc
        if [ -f ~/.zshrc ]; then
            shell_rc=~/.zshrc
        fi
        
        # Check if Docker environment variables are already set
        if ! grep -q "DOCKER_HOST" "$shell_rc"; then
            echo "Setting Docker environment variables in $shell_rc..."
            cat >> "$shell_rc" << 'EOF'

# Docker Desktop for Windows configuration
export DOCKER_HOST=tcp://localhost:2375
export DOCKER_BUILDKIT=1
EOF
        fi
        
        # Set environment variables for current session
        export DOCKER_HOST=tcp://localhost:2375
        export DOCKER_BUILDKIT=1
        
        echo "Docker configured for WSL."
    fi
    
    return 0
}

# Function to check Docker configuration
check_docker_config() {
    echo "Checking Docker configuration..."
    
    # Check Docker Desktop status
    check_docker_desktop
    
    # Check Docker connection
    echo "Testing Docker connection..."
    if docker info &>/dev/null; then
        echo "Docker connection successful."
        docker version
    else
        echo "Docker connection failed."
        return 1
    fi
    
    return 0
}

# Function to install Docker CLI in WSL
install_docker_cli() {
    echo "Installing Docker CLI in WSL..."
    
    # Update package lists
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up the stable repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker CLI
    sudo apt-get update
    sudo apt-get install -y docker-ce-cli
    
    echo "Docker CLI installed successfully."
    return 0
}

# Parse command line arguments
case "${1:-}" in
    check)
        check_docker_config
        ;;
    start)
        start_docker_desktop
        ;;
    configure)
        configure_docker
        ;;
    install-cli)
        install_docker_cli
        ;;
    setup)
        install_docker_cli && configure_docker && check_docker_config
        ;;
    *)
        echo "Usage: $0 {check|start|configure|install-cli|setup}"
        echo
        echo "Commands:"
        echo "  check        Check Docker Desktop status and configuration"
        echo "  start        Start Docker Desktop"
        echo "  configure    Configure Docker for WSL"
        echo "  install-cli  Install Docker CLI in WSL"
        echo "  setup        Perform complete setup (install CLI, configure, check)"
        exit 1
        ;;
esac