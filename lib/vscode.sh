#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

VSCODE_CONFIG_DIR="$HOME/.config/Code/User"

setup_vscode_settings() {
    mkdir -p "${VSCODE_CONFIG_DIR}"
    
    cat > "${VSCODE_CONFIG_DIR}/settings.json" << 'EOF'
{
    "workbench.colorTheme": "Default High Contrast",
    "terminal.integrated.defaultProfile.linux": "zsh",
    "terminal.integrated.profiles.linux": {
        "zsh": {
            "path": "/bin/zsh",
            "args": ["-l"]
        }
    }
}
EOF
    log "INFO" "VS Code settings configured"
}

setup_vscode_extensions() {
    log "INFO" "Setting up VS Code extensions..."
    
    local extensions=(
        "ms-vscode.cpptools"
        "ms-vscode.cpptools-extension-pack"
        "ms-vscode.cpptools-themes"
        "twxs.cmake"
        "ms-vscode.cmake-tools"
        "ms-vscode-remote.remote-containers"
        "ms-azuretools.vscode-docker"
        "william-voyek.vscode-nginx"
        "ms-python.vscode-pylance"
        "ms-python.python"
    )
    
    if ! command -v code >/dev/null; then
        log "ERROR" "VS Code is not installed. Cannot install extensions."
        return 1
    fi
    
    local installed_extensions=$(code --list-extensions 2>/dev/null)
    
    for extension in "${extensions[@]}"; do
        if ! echo "$installed_extensions" | grep -qi "^${extension}$"; then
            log "INFO" "Installing VS Code extension: ${extension}"
            code --install-extension "${extension}" --force
        else
            log "INFO" "VS Code extension already installed: ${extension}"
        fi
    done
    
    code --update-extensions
}