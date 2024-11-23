#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$HOME/.devenv/logs"
BACKUP_DIR="$HOME/.devenv/backups"
VSCODE_CONFIG_DIR="$HOME/.config/Code/User"
SCRIPTS_DIR="$HOME/Development/scripts"

# Logging setup
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/devenv_${TIMESTAMP}.log"

# Enhanced logging function
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOG_FILE}"
}

# Error handler
error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR" "Error occurred in script at line: ${line_no}"
    log "ERROR" "Exit code: ${error_code}"
    exit "${error_code}"
}
trap 'error_handler ${LINENO} $?' ERR

# Healing function to check and fix permissions/installations
heal_component() {
    local component=$1
    local check_cmd=$2
    local install_cmd=$3
    
    log "INFO" "Checking ${component}..."
    if ! eval "${check_cmd}" > /dev/null 2>&1; then
        log "WARN" "${component} is missing or broken, fixing..."
        eval "${install_cmd}"
        log "INFO" "${component} has been fixed"
    else
        log "INFO" "${component} is properly installed"
    fi
}

# Backup existing configuration
backup_configs() {
    local backup_path="${BACKUP_DIR}/${TIMESTAMP}"
    mkdir -p "${backup_path}"
    
    # Backup existing configurations
    for config in ".gitconfig" ".zshrc" ".vscode/settings.json"; do
        if [ -f "$HOME/${config}" ]; then
            mkdir -p "${backup_path}/$(dirname ${config})"
            cp "$HOME/${config}" "${backup_path}/${config}"
            log "INFO" "Backed up ${config}"
        fi
    done
}

# VS Code settings management
setup_vscode_settings() {
    mkdir -p "${VSCODE_CONFIG_DIR}"
    
    # Create settings.json with merged configurations
    cat > "${VSCODE_CONFIG_DIR}/settings.json" << 'EOF'
{
    "workbench.colorTheme": "Default High Contrast",
    "terminal.integrated.defaultProfile.linux": "zsh",
    "terminal.integrated.profiles.linux": {
        "zsh": {
            "path": "/bin/zsh",
            "args": ["-l"]
        }
    },
    "terminal.integrated.env.linux": {
        "PATH": "${env:PATH}",
        "TERM": "xterm-256color"
    },
    "terminal.integrated.fontFamily": "MesloLGS NF",
    "terminal.integrated.fontSize": 14,
    "workbench.colorCustomizations": {
        "terminal.background": "#1E1E1E",
        "terminal.foreground": "#D4D4D4",
        "terminal.ansiBlack": "#000000",
        "terminal.ansiBlue": "#2472C8",
        "terminal.ansiCyan": "#11A8CD",
        "terminal.ansiGreen": "#0DBC79",
        "terminal.ansiMagenta": "#BC3FBC",
        "terminal.ansiRed": "#CD3131",
        "terminal.ansiWhite": "#E5E5E5",
        "terminal.ansiYellow": "#E5E510"
    },
    "docker.containers.defaultAction": "start",
    "docker.containers.sortBy": "Status",
    "remote.containers.defaultExtensions": [
        "ms-python.python",
        "ms-python.vscode-pylance"
    ],
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "python.analysis.extraPaths": [
        "${env:HOME}/.local/lib/python3/site-packages"
    ]
}
EOF
    log "INFO" "VS Code settings configured"
}

# VS Code extensions setup
setup_vscode_extensions() {
    log "INFO" "Setting up VS Code extensions..."
    
    # List of required extensions
    local extensions=(
        "ms-vscode.cpptools"                 # C/C++
        "ms-vscode.cpptools-extension-pack"  # C/C++ Extension Pack
        "ms-vscode.cpptools-themes"          # C/C++ Themes
        "twxs.cmake"                         # CMake
        "ms-vscode.cmake-tools"              # CMake Tools
        "ms-vscode-remote.remote-containers" # Dev Containers
        "ms-azuretools.vscode-docker"        # Docker
        "william-voyek.vscode-nginx"         # NGINX Configuration
        "ms-python.vscode-pylance"           # Pylance
        "ms-python.python"                   # Python
    )
    
    # Check if code is installed
    if ! command -v code >/dev/null; then
        log "ERROR" "VS Code is not installed. Cannot install extensions."
        return 1
    fi
    
    # Get currently installed extensions
    local installed_extensions=$(code --list-extensions 2>/dev/null)
    
    # Install missing extensions
    for extension in "${extensions[@]}"; do
        if ! echo "$installed_extensions" | grep -qi "^${extension}$"; then
            log "INFO" "Installing VS Code extension: ${extension}"
            code --install-extension "${extension}" --force
        else
            log "INFO" "VS Code extension already installed: ${extension}"
        fi
    done
    
    # Update all installed extensions
    log "INFO" "Updating VS Code extensions..."
    code --update-extensions
    
    # Verify installations
    log "INFO" "Verifying VS Code extensions..."
    local missing=0
    for extension in "${extensions[@]}"; do
        if ! code --list-extensions 2>/dev/null | grep -qi "^${extension}$"; then
            log "ERROR" "Failed to install extension: ${extension}"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -eq 0 ]; then
        log "INFO" "All VS Code extensions installed successfully"
    else
        log "WARN" "${missing} extension(s) failed to install"
    fi
}

# Generate system report
generate_system_report() {
    local report_file="${LOG_DIR}/system_report_${TIMESTAMP}.txt"
    log "INFO" "Generating system report..."
    
    {
        echo "=== Development Environment System Report ==="
        echo "Generated: $(date)"
        echo
        
        echo "=== System Information ==="
        echo "Kernel: $(uname -r)"
        echo "Distribution: $(cat /etc/redhat-release)"
        echo "Architecture: $(uname -m)"
        echo
        
        echo "=== Component Locations ==="
        echo "Development Directories:"
        echo "  Projects: ${HOME}/Development/projects"
        echo "  Scripts: ${HOME}/Development/scripts"
        echo "  Docker: ${HOME}/Development/docker"
        echo
        
        echo "Configuration Files:"
        echo "  Git Config: ${HOME}/.gitconfig"
        [ -f "${HOME}/.gitconfig" ] && echo "    $(git config --get user.name) <$(git config --get user.email)>"
        echo "  ZSH Config: ${HOME}/.zshrc"
        echo "  VS Code Settings: ${VSCODE_CONFIG_DIR}/settings.json"
        echo "  Docker Config: /etc/docker/daemon.json"
        echo
        
        echo "Installation Directories:"
        echo "  NVM: ${HOME}/.nvm"
        [ -d "${HOME}/.nvm" ] && echo "    Node Version: $(nvm current 2>/dev/null || echo 'Not installed')"
        echo "  Python: $(which python3)"
        echo "    Pip: $(which pip3)"
        echo "    Virtualenv: $(which virtualenv)"
        echo "    Site packages: ${HOME}/.local/lib/python3/site-packages"
        echo
        
        echo "SSH Configuration:"
        echo "  Keys Directory: ${HOME}/.ssh"
        [ -f "${HOME}/.ssh/id_ed25519.pub" ] && echo "    Public Key: $(cat ${HOME}/.ssh/id_ed25519.pub)"
        echo
        
        echo "=== Installed Tools Versions ==="
        echo "Git: $(git --version 2>/dev/null || echo 'Not installed')"
        echo "Docker: $(docker --version 2>/dev/null || echo 'Not installed')"
        echo "Python: $(python3 --version 2>/dev/null || echo 'Not installed')"
        echo "Pip: $(pip3 --version 2>/dev/null || echo 'Not installed')"
        echo "VS Code: $(code --version 2>/dev/null | head -n1 || echo 'Not installed')"
        echo "ZSH: $(zsh --version 2>/dev/null || echo 'Not installed')"
        echo "GCC: $(gcc --version 2>/dev/null | head -n1 || echo 'Not installed')"
        echo "Make: $(make --version 2>/dev/null | head -n1 || echo 'Not installed')"
        echo
        
        echo "=== VS Code Configuration ==="
        if command -v code >/dev/null; then
            echo "VS Code Version: $(code --version | head -n1)"
            echo
            echo "Installed Extensions:"
            code --list-extensions --show-versions 2>/dev/null | sort | while read -r ext; do
                echo "  $ext"
            done
            
            echo
            echo "Extension Locations:"
            echo "  User: ${HOME}/.vscode/extensions"
            echo "  System: /usr/share/code/resources/app/extensions"
            
            echo
            echo "Settings Location: ${VSCODE_CONFIG_DIR}/settings.json"
            if [ -f "${VSCODE_CONFIG_DIR}/settings.json" ]; then
                echo "Settings Content:"
                echo "----------------"
                cat "${VSCODE_CONFIG_DIR}/settings.json"
                echo "----------------"
            fi
        else
            echo "VS Code is not installed"
        fi
        echo
        
        echo "=== Docker Configuration ==="
        if [ -f "/etc/docker/daemon.json" ]; then
            echo "Docker daemon configuration:"
            cat "/etc/docker/daemon.json"
        else
            echo "Docker daemon configuration not found"
        fi
        echo
        
        echo "=== CPU Information ==="
        echo "Available CPU governors:"
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
            if [ -f "$cpu/cpufreq/scaling_available_governors" ]; then
                echo "  $(basename $cpu): $(cat $cpu/cpufreq/scaling_available_governors)"
            fi
        done
        echo
        
        echo "=== Environment Variables ==="
        echo "PATH: $PATH"
        echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
        [ -n "${PYTHONPATH+x}" ] && echo "PYTHONPATH: $PYTHONPATH"
        echo
        
        echo "=== Log Locations ==="
        echo "Main Log Directory: ${LOG_DIR}"
        echo "Current Log File: ${LOG_FILE}"
        echo "Backup Directory: ${BACKUP_DIR}"
        echo
        
        echo "=== Scripts ==="
        echo "CPU Control Script: ${SCRIPTS_DIR}/cpu-control.sh"
        [ -f "${SCRIPTS_DIR}/cpu-control.sh" ] && echo "  Permissions: $(stat -c '%a %U:%G' ${SCRIPTS_DIR}/cpu-control.sh)"
        echo
        
    } | tee "${report_file}"
    
    log "INFO" "System report generated at: ${report_file}"
    
    # Create HTML version of the report
    {
        echo "<html><head><title>Development Environment Report</title>"
        echo "<style>"
        echo "body { font-family: monospace; margin: 40px auto; max-width: 800px; line-height: 1.6; padding: 0 10px; }"
        echo "h2 { color: #333; border-bottom: 1px solid #ccc; }"
        echo "pre { background: #f4f4f4; padding: 10px; overflow-x: auto; }"
        echo "</style></head><body>"
        echo "<h1>Development Environment Report</h1>"
        sed 's/=== \(.*\) ===/<h2>\1<\/h2>/' "${report_file}" | sed 's/$/<br>/' | sed 's/^  /\&nbsp;\&nbsp;/'
        echo "</body></html>"
    } > "${report_file}.html"
    
    log "INFO" "HTML report generated at: ${report_file}.html"
}

# Main installation function
main() {
    log "INFO" "Starting development environment setup..."
    
    # Create backup
    backup_configs
    
    # Enable EPEL repository
    heal_component "EPEL" "rpm -q epel-release" "sudo dnf install -y epel-release"
    
    # System update
    log "INFO" "Updating system packages..."
    sudo dnf update -y
    heal_component "Development Tools" "rpm -q @development-tools" "sudo dnf groupinstall -y 'Development Tools'"
    
    # Install MacBook utilities
    log "INFO" "Installing MacBook utilities..."
    local macbook_utils=(
        "lm_sensors"
        "dmidecode"
        "htop"
        "cpufrequtils"
    )
    for util in "${macbook_utils[@]}"; do
        heal_component "${util}" "rpm -q ${util}" "sudo dnf install -y ${util}"
    done
    
    # Install development tools
    log "INFO" "Installing development utilities..."
    local dev_tools=(
        "git"
        "curl"
        "wget"
        "unzip"
        "htop"
        "vim"
        "nano"
        "make"
        "gcc"
        "gcc-c++"
        "kernel-devel"
    )
    for tool in "${dev_tools[@]}"; do
        heal_component "${tool}" "rpm -q ${tool}" "sudo dnf install -y ${tool}"
    done
    
    # Git configuration
    if [ ! -f "$HOME/.gitconfig" ] || ! grep -q "user.name" "$HOME/.gitconfig"; then
        log "INFO" "Configuring Git..."
        read -p "Enter your Git name: " git_name
        read -p "Enter your Git email: " git_email
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        git config --global init.defaultBranch main
        git config --global core.editor "nano"
    else
        log "INFO" "Git already configured"
    fi
    
    # Install Node.js using nvm
    if [ ! -d "$HOME/.nvm" ]; then
        log "INFO" "Installing Node.js using nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install --lts
        nvm use --lts
    else
        log "INFO" "NVM already installed, updating..."
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install --lts
        nvm use --lts
    fi
    
    # Python setup
    heal_component "python3-pip" "rpm -q python3-pip" "sudo dnf install -y python3-pip python3-devel"
    pip3 install --user --upgrade pip pipenv virtualenv
    
    # Docker installation and configuration
    if ! command -v docker &> /dev/null; then
        log "INFO" "Installing Docker..."
        sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    fi
    
    # Configure Docker daemon
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
    
    # VS Code installation
    if ! command -v code &> /dev/null; then
        log "INFO" "Installing Visual Studio Code..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
        sudo dnf install -y code
    fi
    
    # Configure VS Code settings
    setup_vscode_settings
    setup_vscode_extensions
    
    # Shell setup
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "INFO" "Installing ZSH and Oh My ZSH..."
        heal_component "zsh" "rpm -q zsh" "sudo dnf install -y zsh util-linux-user"
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o install-oh-my-zsh.sh
        sh install-oh-my-zsh.sh --unattended
        rm install-oh-my-zsh.sh
    fi
    
    # Create development directories
    mkdir -p ~/Development/{projects,scripts,docker}
    
    # Setup SSH key if not exists
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        log "INFO" "Setting up SSH key..."
        ssh-keygen -t ed25519 -C "$(git config --get user.email)" -f "$HOME/.ssh/id_ed25519" -N ""
    fi
    
    # Create CPU management script
    mkdir -p "${SCRIPTS_DIR}"
    cat << 'EOF' > "${SCRIPTS_DIR}/cpu-control.sh"
#!/bin/bash

case $1 in
    "performance")
        echo "Setting CPU to performance mode..."
        sudo cpufreq-set -g performance
        ;;
    "powersave")
        echo "Setting CPU to powersave mode..."
        sudo cpufreq-set -g powersave
        ;;
    *)
        echo "Usage: $0 {performance|powersave}"
        exit 1
        ;;
esac

# Show current CPU frequency
for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    cpu_num=$(basename $cpu | tr -dc '0-9')
    cur_freq=$(cat $cpu/cpufreq/scaling_cur_freq)
    echo "CPU$cpu_num: Current frequency: $((cur_freq/1000)) MHz"
done
EOF
    chmod +x "${SCRIPTS_DIR}/cpu-control.sh"
    generate_system_report
    log "INFO" "Installation complete!"
    echo ""
    echo "Important notes:"
    echo "1. To change your shell to ZSH: chsh -s $(which zsh)"
    echo "2. Load your ZSH configuration: source ~/.zshrc"
    echo "3. CPU control script: ${SCRIPTS_DIR}/cpu-control.sh"
    echo "4. Logs available in: ${LOG_DIR}"
    echo "5. Backups stored in: ${BACKUP_DIR}"
    echo ""
    echo "Docker usage tips:"
    echo "- Use 'docker system prune' regularly"
    echo "- Monitor resources: docker stats"
    echo "- Check logs: ${LOG_FILE}"
}

# Execute main function
main "$@"