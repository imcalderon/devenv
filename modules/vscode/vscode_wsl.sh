#!/bin/bash
# modules/vscode/vscode_wsl.sh - VS Code WSL integration helper

# Check if running in WSL
if ! grep -q "microsoft" /proc/version 2>/dev/null; then
    echo "This script is intended to be run in WSL only."
    exit 1
fi

# Function to install VS Code Server components in WSL
install_vscode_server() {
    echo "Installing VS Code Server components in WSL..."
    
    # Create ~/.vscode-server directory if it doesn't exist
    mkdir -p ~/.vscode-server
    
    # Create bin directory
    mkdir -p ~/.local/bin
    
    # Check if VS Code CLI is already installed
    if command -v code &>/dev/null; then
        echo "VS Code CLI is already installed."
        code --version
        return 0
    fi
    
    # Download VS Code CLI
    echo "Downloading VS Code CLI..."
    curl -L "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64" -o /tmp/vscode-cli.tar.gz
    
    if [ $? -ne 0 ]; then
        echo "Failed to download VS Code CLI."
        return 1
    fi
    
    # Extract VS Code CLI
    echo "Extracting VS Code CLI..."
    tar -xf /tmp/vscode-cli.tar.gz -C ~/.local/bin
    chmod +x ~/.local/bin/code
    
    # Clean up
    rm /tmp/vscode-cli.tar.gz
    
    # Add to PATH if not already there
    if ! echo $PATH | grep -q ~/.local/bin; then
        echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
        export PATH="$PATH:$HOME/.local/bin"
    fi
    
    # Verify installation
    if command -v code &>/dev/null; then
        echo "VS Code CLI installed successfully."
        code --version
        return 0
    else
        echo "Failed to install VS Code CLI."
        return 1
    fi
}

# Function to check if VS Code is installed in Windows
check_vscode_windows() {
    echo "Checking if VS Code is installed in Windows..."
    
    # Check standard installation locations
    local install_paths=(
        "/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd"
        "/mnt/c/Program Files (x86)/Microsoft VS Code/bin/code.cmd"
        "/mnt/c/Users/$USER/AppData/Local/Programs/Microsoft VS Code/bin/code.cmd"
    )
    
    for path in "${install_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "VS Code found at: $path"
            return 0
        fi
    done
    
    # Check if code.cmd is available via Windows PATH
    if powershell.exe "Get-Command code.exe -ErrorAction SilentlyContinue" 2>/dev/null | grep -q "code.exe"; then
        echo "VS Code found in Windows PATH."
        return 0
    fi
    
    echo "VS Code not found in Windows."
    return 1
}

# Function to install Remote-WSL extension in Windows VS Code
install_remote_wsl_extension() {
    echo "Installing Remote-WSL extension in Windows VS Code..."
    
    # Try standard installation locations
    local install_paths=(
        "/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd"
        "/mnt/c/Program Files (x86)/Microsoft VS Code/bin/code.cmd"
        "/mnt/c/Users/$USER/AppData/Local/Programs/Microsoft VS Code/bin/code.cmd"
    )
    
    for path in "${install_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "Using VS Code at: $path"
            powershell.exe "& '$path' --install-extension ms-vscode-remote.remote-wsl"
            return $?
        fi
    done
    
    # Try using code.cmd from PATH
    if powershell.exe "Get-Command code.exe -ErrorAction SilentlyContinue" 2>/dev/null | grep -q "code.exe"; then
        echo "Using VS Code from Windows PATH."
        powershell.exe "code --install-extension ms-vscode-remote.remote-wsl"
        return $?
    fi
    
    echo "VS Code not found in Windows. Cannot install Remote-WSL extension."
    return 1
}

# Function to set up VS Code configuration
setup_vscode_config() {
    echo "Setting up VS Code configuration..."
    
    # Create settings directory if it doesn't exist
    local settings_dir="$HOME/.vscode-server/data/Machine"
    mkdir -p "$settings_dir"
    
    # Create settings.json if it doesn't exist or backup if it does
    local settings_file="$settings_dir/settings.json"
    if [ -f "$settings_file" ]; then
        echo "Backing up existing settings.json..."
        cp "$settings_file" "$settings_file.bak"
    fi
    
    # Create or update settings.json
    echo "Creating/updating settings.json..."
    cat > "$settings_file" << EOF
{
    "terminal.integrated.defaultProfile.linux": "bash",
    "terminal.integrated.profiles.linux": {
        "bash": {
            "path": "bash",
            "icon": "terminal-bash"
        }
    },
    "terminal.integrated.fontFamily": "MesloLGM Nerd Font",
    "terminal.integrated.fontSize": 14,
    "telemetry.telemetryLevel": "off",
    "update.mode": "none",
    "remote.WSL.fileWatcher.polling": true,
    "remote.WSL.fileWatcher.pollingInterval": 5000
}
EOF
    
    echo "VS Code configuration updated successfully."
    return 0
}

# Function to create helpful shell aliases
create_vscode_aliases() {
    echo "Creating VS Code aliases..."
    
    # Create ~/.bashrc.d directory if it doesn't exist
    mkdir -p ~/.bashrc.d
    
    # Create vscode.sh in ~/.bashrc.d
    local aliases_file=~/.bashrc.d/vscode.sh
    cat > "$aliases_file" << 'EOF'
# VS Code aliases
alias code-wsl="code"
alias code-win="powershell.exe code"
alias code-here="code ."
alias code-proj="code ~/Projects"
EOF
    
    # Make the file executable
    chmod +x "$aliases_file"
    
    # Source the file from .bashrc if not already
    if ! grep -q "source ~/.bashrc.d/vscode.sh" ~/.bashrc; then
        echo "Adding VS Code aliases to .bashrc..."
        echo "" >> ~/.bashrc
        echo "# VS Code aliases" >> ~/.bashrc
        echo "if [ -f ~/.bashrc.d/vscode.sh ]; then" >> ~/.bashrc
        echo "    source ~/.bashrc.d/vscode.sh" >> ~/.bashrc
        echo "fi" >> ~/.bashrc
    fi
    
    # Also source immediately for current session
    source "$aliases_file"
    
    echo "VS Code aliases created successfully."
    return 0
}

# Parse command line arguments
case "${1:-}" in
    install-server)
        install_vscode_server
        ;;
    check-windows)
        check_vscode_windows
        ;;
    install-extension)
        install_remote_wsl_extension
        ;;
    setup-config)
        setup_vscode_config
        ;;
    create-aliases)
        create_vscode_aliases
        ;;
    setup)
        install_vscode_server && \
        check_vscode_windows && \
        install_remote_wsl_extension && \
        setup_vscode_config && \
        create_vscode_aliases
        ;;
    *)
        echo "Usage: $0 {install-server|check-windows|install-extension|setup-config|create-aliases|setup}"
        echo
        echo "Commands:"
        echo "  install-server    Install VS Code server components in WSL"
        echo "  check-windows     Check if VS Code is installed in Windows"
        echo "  install-extension Install Remote-WSL extension in Windows VS Code"
        echo "  setup-config      Set up VS Code configuration"
        echo "  create-aliases    Create helpful shell aliases"
        echo "  setup             Perform complete setup"
        exit 1
        ;;
esac