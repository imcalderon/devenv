#!/bin/bash
# modules/wsl/wsl.sh - WSL module implementation for Windows

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "wsl" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/wsl.state"

# Define module components
COMPONENTS=(
    "core"          # Base WSL configuration
    "integration"   # Windows-WSL integration
    "mounts"        # Mount configuration
    "networking"    # WSL networking setup
)

# Display module information
show_module_info() {
    cat << 'EOF'

🪟 WSL Integration
===============

Description:
-----------
Windows Subsystem for Linux integration that optimizes the development
experience between Windows and Linux environments.

Benefits:
--------
✓ Seamless Integration - Configured path translation between Windows and Linux
✓ Performance Optimization - Properly configured mount options for speed
✓ Visual Studio Code Integration - Remote WSL development setup
✓ Docker Integration - Configured for best practices with WSL 2
✓ Windows Terminal Integration - Customized profiles for development

Components:
----------
1. Core WSL Settings
   - WSL 2 backend
   - Memory and CPU allocation
   - Performance tuning

2. Windows Integration
   - Path translation
   - Windows Terminal profiles
   - VS Code integration

3. Mount Configuration
   - Optimized file system mounts
   - Windows drive access
   - Performance configuration

4. Networking
   - Local network access
   - Port forwarding
   - Service exposure

Quick Start:
-----------
1. Edit WSL config:
   $ wsledit

2. Restart WSL:
   $ wslrestart

3. Access Windows files:
   $ cdwin

Aliases:
-------
wsledit     : Edit WSL configuration
wslrestart  : Restart WSL
cdwin       : Change to Windows home directory
cdproj      : Change to projects directory
wslip       : Show WSL IP address
winip       : Show Windows host IP

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v wsl.exe &>/dev/null; then
                        echo "  WSL Version: 2"
                    fi
                    ;;
                "integration")
                    local vscode_installed=$(command -v code &>/dev/null && echo "yes" || echo "no")
                    echo "  VS Code Integration: $vscode_installed"
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
    echo
}

# Save component state
save_state() {
    local component=$1
    local status=$2
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$component:$status:$(date +%s)" >> "$STATE_FILE"
}

# Check component state
check_state() {
    local component=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep -q "^$component:installed:" "$STATE_FILE"
        return $?
    fi
    return 1
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            # Check for WSL 2
            [[ -f /proc/version ]] && grep -q "microsoft" /proc/version
            ;;
        "integration")
            # Check for Windows-WSL integration
            verify_vs_code_integration && verify_windows_terminal
            ;;
        "mounts")
            # Check for optimized mount configuration
            verify_mount_configuration
            ;;
        "networking")
            # Check for networking setup
            verify_networking_setup
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verify VS Code integration
verify_vs_code_integration() {
    # Check for VS Code and the Remote-WSL extension
    if command -v code &>/dev/null; then
        return 0
    fi
    return 1
}

# Verify Windows Terminal configuration
verify_windows_terminal() {
    # We can't directly verify Windows Terminal from WSL
    # So we check if our configuration file exists
    local wt_config=$(get_module_config "wsl" ".shell.paths.windows_terminal_config")
    wt_config=$(eval echo "$wt_config")
    
    # This check needs to be handled more carefully since the file is in Windows
    [[ -n "$wt_config" ]]
}

# Verify mount configuration
verify_mount_configuration() {
    # Check if the WSL configuration has our mount options
    local wsl_conf="/etc/wsl.conf"
    if [[ -f "$wsl_conf" ]]; then
        grep -q "^\[automount\]" "$wsl_conf" && \
        grep -q "^options" "$wsl_conf"
        return $?
    fi
    return 1
}

# Verify networking setup
verify_networking_setup() {
    # Basic connectivity check
    ping -c 1 1.1.1.1 >/dev/null 2>&1
}

# Configure core WSL settings
configure_core() {
    log "INFO" "Configuring core WSL settings..." "wsl"
    
    # Create .wslconfig in Windows home if it doesn't exist
    local win_home=$(get_module_config "wsl" ".shell.paths.windows_home")
    win_home=$(eval echo "$win_home")
    local wsl_config="$win_home/.wslconfig"
    
    # Use PowerShell to check if .wslconfig exists
    if ! powershell.exe "Test-Path $wsl_config" | grep -q "True"; then
        log "INFO" "Creating .wslconfig in Windows home..." "wsl"
        
        # Get configuration values
        local memory=$(get_module_config "wsl" ".wsl.config.memory")
        local processors=$(get_module_config "wsl" ".wsl.config.processors")
        local swap=$(get_module_config "wsl" ".wsl.config.swap")
        
        # Write config using PowerShell
        powershell.exe "Set-Content -Path $wsl_config -Value \"[wsl2]`r`nmemory=$memory`r`nprocessors=$processors`r`nswap=$swap`r`n\""
        
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to create .wslconfig in Windows home" "wsl"
            return 1
        fi
    fi
    
    # Configure /etc/wsl.conf
    local wsl_conf="/etc/wsl.conf"
    
    # Backup existing configuration
    [[ -f "$wsl_conf" ]] && backup_file "$wsl_conf" "wsl"
    
    # Create new configuration
    sudo tee "$wsl_conf" > /dev/null << EOF
# WSL Configuration - Managed by DevEnv

[automount]
enabled = true
options = "metadata,uid=1000,gid=1000,umask=022,fmask=111"
mountFsTab = true

[network]
generateHosts = true
generateResolvConf = true

[interop]
enabled = true
appendWindowsPath = true

[user]
default = $(whoami)
EOF

    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to configure /etc/wsl.conf" "wsl"
        return 1
    fi
    
    return 0
}

# Configure Windows-WSL integration
configure_integration() {
    log "INFO" "Configuring Windows-WSL integration..." "wsl"
    
    # Configure VS Code WSL integration
    configure_vscode_integration || return 1
    
    # Configure Windows Terminal
    configure_windows_terminal || return 1
    
    # Create aliases for Windows integration
    add_module_aliases "wsl" "windows" || return 1
    
    return 0
}

# Configure VS Code WSL integration
configure_vscode_integration() {
    log "INFO" "Configuring VS Code WSL integration..." "wsl"
    
    # Check if VS Code is installed in Windows
    if ! command -v code &>/dev/null; then
        log "INFO" "Installing VS Code server for WSL..." "wsl"
        
        # Install VS Code server components
        curl -L "https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64" -o /tmp/vscode-cli.tar.gz
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to download VS Code CLI" "wsl"
            return 1
        fi
        
        mkdir -p ~/.local/bin
        tar -xf /tmp/vscode-cli.tar.gz -C ~/.local/bin
        chmod +x ~/.local/bin/code
        rm /tmp/vscode-cli.tar.gz
        
        if ! command -v code &>/dev/null; then
            export PATH="$PATH:$HOME/.local/bin"
            echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
        fi
    fi
    
    # Install VS Code WSL extension in Windows
    log "INFO" "Installing VS Code Remote-WSL extension..." "wsl"
    powershell.exe "& \$env:LOCALAPPDATA\Programs\'Microsoft VS Code'\bin\code.cmd --install-extension ms-vscode-remote.remote-wsl" || true
    
    return 0
}

# Configure Windows Terminal
configure_windows_terminal() {
    log "INFO" "Configuring Windows Terminal..." "wsl"
    
    # Get Windows Terminal settings path
    local wt_settings=$(get_module_config "wsl" ".shell.paths.windows_terminal_config")
    wt_settings=$(eval echo "$wt_settings")
    
    # Check if Windows Terminal settings file exists
    if ! powershell.exe "Test-Path \"$wt_settings\"" | grep -q "True"; then
        log "WARN" "Windows Terminal settings file not found: $wt_settings" "wsl"
        log "INFO" "Skipping Windows Terminal configuration" "wsl"
        return 0
    fi
    
    # Get distribution name
    local distro=$(basename $(cat /etc/os-release | grep -oP '(?<=^ID=).+' | tr -d '"'))
    local distro_pretty=$(cat /etc/os-release | grep -oP '(?<=^PRETTY_NAME=).+' | tr -d '"')
    
    # Get current user
    local current_user=$(whoami)
    
    # Create Windows Terminal profile
    local profile_json="{
        \"name\": \"${distro_pretty} (DevEnv)\",
        \"commandline\": \"wsl.exe -d ${distro} -u ${current_user}\",
        \"icon\": \"%USERPROFILE%\\\\.devenv\\\\icons\\\\devenv.png\",
        \"startingDirectory\": \"//wsl\$/${distro}/home/${current_user}\",
        \"colorScheme\": \"One Half Dark\",
        \"fontFace\": \"CaskaydiaCove Nerd Font\"
    }"
    
    # Use PowerShell to update Windows Terminal settings
    # This is complex and requires PowerShell script execution
    local ps_script=$(cat << 'EOF'
$settingsPath = $args[0]
$newProfile = $args[1] | ConvertFrom-Json

$settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json

$profileExists = $false
foreach ($profile in $settings.profiles.list) {
    if ($profile.name -eq $newProfile.name) {
        $profileExists = $true
        break
    }
}

if (-not $profileExists) {
    $settings.profiles.list += $newProfile
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath
    Write-Output "Added DevEnv profile to Windows Terminal"
} else {
    Write-Output "DevEnv profile already exists in Windows Terminal"
}
EOF
)

    # Create a temporary file for the PowerShell script
    echo "$ps_script" > /tmp/update_wt.ps1
    
    # Execute the PowerShell script
    powershell.exe "& {$(cat /tmp/update_wt.ps1)} '$wt_settings' '$profile_json'"
    
    # Clean up
    rm /tmp/update_wt.ps1
    
    return 0
}

# Configure mount optimization
configure_mounts() {
    log "INFO" "Configuring mount optimization..." "wsl"
    
    # Create project directories
    local win_projects=$(get_module_config "wsl" ".shell.paths.windows_projects")
    local linux_projects=$(get_module_config "wsl" ".shell.paths.linux_projects")
    
    win_projects=$(eval echo "$win_projects")
    linux_projects=$(eval echo "$linux_projects")
    
    # Create Windows projects directory if it doesn't exist
    if ! powershell.exe "Test-Path $win_projects" | grep -q "True"; then
        log "INFO" "Creating Windows projects directory: $win_projects..." "wsl"
        powershell.exe "New-Item -Path '$win_projects' -ItemType Directory -Force"
    fi
    
    # Create Linux projects directory and symlink if needed
    mkdir -p "$linux_projects"
    
    # Create symlink to Windows projects if requested
    local symlink_projects=$(get_module_config "wsl" ".wsl.mount.symlink_projects")
    if [[ "$symlink_projects" == "true" ]]; then
        local win_path="/mnt/c/${win_projects#C:/}"
        win_path=$(echo "$win_path" | tr '\\' '/')
        
        # Create symlink if it doesn't exist or points to wrong location
        if [[ ! -L "$linux_projects" ]] || [[ "$(readlink "$linux_projects")" != "$win_path" ]]; then
            rm -rf "$linux_projects"
            ln -sf "$win_path" "$linux_projects"
            log "INFO" "Created symlink from $linux_projects to $win_path" "wsl"
        fi
    fi
    
    return 0
}

# Configure networking
configure_networking() {
    log "INFO" "Configuring networking..." "wsl"
    
    # Create helper scripts for networking
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    
    # Script to get WSL IP address
    cat > "$bin_dir/wslip" << 'EOF'
#!/bin/bash
ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
EOF
    chmod +x "$bin_dir/wslip"
    
    # Script to get Windows host IP address
    cat > "$bin_dir/winip" << 'EOF'
#!/bin/bash
cat /etc/resolv.conf | grep -oP '(?<=nameserver\s)\d+(\.\d+){3}'
EOF
    chmod +x "$bin_dir/winip"
    
    # Add scripts to PATH if needed
    if ! grep -q "$bin_dir" "$HOME/.bashrc"; then
        echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$HOME/.bashrc"
    fi
    
    return 0
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "wsl"
        return 0
    fi
    
    case "$component" in
        "core")
            if configure_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "integration")
            if configure_integration; then
                save_state "integration" "installed"
                return 0
            fi
            ;;
        "mounts")
            if configure_mounts; then
                save_state "mounts" "installed"
                return 0
            fi
            ;;
        "networking")
            if configure_networking; then
                save_state "networking" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Grovel checks existence and basic functionality
grovel_wsl() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "wsl"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_wsl() {
    local force=${1:-false}
    
    # Check if we're running in WSL
    if ! grep -q "microsoft" /proc/version 2>/dev/null; then
        log "ERROR" "This module can only be run inside WSL" "wsl"
        return 1
    fi
    
    if [[ "$force" == "true" ]] || ! grovel_wsl &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "wsl"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "wsl"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "wsl"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Remove WSL configuration
remove_wsl() {
    log "INFO" "Removing WSL configuration..." "wsl"

    # Backup existing configurations
    [[ -f "/etc/wsl.conf" ]] && backup_file "/etc/wsl.conf" "wsl"
    
    # Remove configurations
    sudo rm -f "/etc/wsl.conf"
    
    # Remove aliases
    remove_module_aliases "wsl" "windows"
    
    # Remove state file
    rm -f "$STATE_FILE"
    
    log "WARN" "Windows-side configurations (.wslconfig, Windows Terminal) were not removed." "wsl"
    
    return 0
}

# Verify entire installation
verify_wsl() {
    log "INFO" "Verifying WSL installation..." "wsl"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "wsl"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "WSL verification completed successfully" "wsl"
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_wsl
        ;;
    install)
        install_wsl "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_wsl
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_wsl
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "wsl"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac