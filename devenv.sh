#!/bin/bash
# devenv.sh - Development environment setup with cross-platform support

set -euo pipefail

# Get absolute paths if not already set
if [[ -z "${ROOT_DIR:-}" ]]; then
    export ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "${CONFIG_FILE:-}" ]]; then
    export CONFIG_FILE="$ROOT_DIR/config.json"
fi

# Detect platform
detect_platform() {
    local platform="unknown"
    case "$(uname -s)" in
        Linux*)     platform="linux";;
        Darwin*)    platform="darwin";;
        *)          platform="unknown";;
    esac
    
    echo "$platform"
}

PLATFORM=$(detect_platform)

# Set platform-specific script directory
export SCRIPT_DIR="$ROOT_DIR/lib"
export MODULES_DIR="$ROOT_DIR/modules"

# Ensure DEVENV environment variables are set
if [[ -z "${DEVENV_ROOT:-}" ]]; then
    export DEVENV_ROOT="$ROOT_DIR"
    export DEVENV_DATA_DIR="$ROOT_DIR/data"
    export DEVENV_CONFIG_DIR="$ROOT_DIR/config"
    export DEVENV_MODULES_DIR="$ROOT_DIR/modules"
    export DEVENV_STATE_DIR="$DEVENV_DATA_DIR/state"
    export DEVENV_LOGS_DIR="$DEVENV_DATA_DIR/logs"
    export DEVENV_BACKUPS_DIR="$DEVENV_DATA_DIR/backups"
    
    # Create data directories if they don't exist
    mkdir -p "$DEVENV_DATA_DIR"
    mkdir -p "$DEVENV_STATE_DIR"
    mkdir -p "$DEVENV_LOGS_DIR"
    mkdir -p "$DEVENV_BACKUPS_DIR"
fi

# Use project-based state directory
export STATE_DIR="$DEVENV_STATE_DIR"

# Load utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities

# Detect and configure WSL environment
setup_wsl_environment() {
    # Only run this on Windows/WSL
    if ! grep -q "microsoft" /proc/version 2>/dev/null; then
        return 0
    fi
    
    # Check if WSL is already configured
    local wsl_state_file="${DEVENV_STATE_DIR}/wsl_configured"
    if [[ -f "$wsl_state_file" ]] && [[ "$1" != "--force" ]]; then
        log "INFO" "WSL environment already configured, skipping setup"
        return 0
    fi
    
    log "INFO" "WSL environment detected, configuring for optimal performance..."
    setup_wsl_environment() {
    # Only run this on Windows/WSL
    if ! grep -q "microsoft" /proc/version 2>/dev/null; then
        return 0
    fi
    
    # Check if WSL is already configured
    local wsl_state_file="${DEVENV_STATE_DIR}/wsl_configured"
    if [[ -f "$wsl_state_file" ]] && [[ "$1" != "--force" ]]; then
        log "INFO" "WSL environment already configured, skipping setup"
        return 0
    fi
    
    log "INFO" "WSL environment detected, configuring for optimal performance..."
    # Get Windows home directory path
    local windows_home=$(wslpath "$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')")
    local wslconfig="${windows_home}/.wslconfig"
    
    # Create optimized .wslconfig content
    local wslconfig_content=$(cat << 'EOF'
[wsl2]
# Memory allocation
memory=8GB
# CPU allocation
processors=4
# Enable better GPU support
gpuSupport=true
# Enable experimental features
nestedVirtualization=true
# Network settings
dnsTunneling=true
firewall=true
# Set swap storage
swap=4GB
# Set VM disk compression
diskCompression=zstd
EOF
)
    
    # Check if .wslconfig already exists
    if [[ -f "$wslconfig" ]]; then
        log "WARN" "Existing .wslconfig found at $windows_home"
        log "INFO" "DevEnv can create an optimized .wslconfig for better performance"
        
        # Ask user for permission to overwrite
        read -p "Would you like to overwrite the existing .wslconfig with optimized settings? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log "INFO" "Keeping existing .wslconfig"
        else
            log "INFO" "Overwriting .wslconfig with optimized settings..."
            echo "$wslconfig_content" > "$wslconfig"
            log "INFO" "Created optimized .wslconfig file at $wslconfig"
        fi
    else
        # No existing file, create a new one
        log "INFO" "Creating optimized .wslconfig in Windows home directory..."
        echo "$wslconfig_content" > "$wslconfig"
        log "INFO" "Created optimized .wslconfig file at $wslconfig"
    fi
    
    # Fix Docker permissions
    if command -v docker &>/dev/null; then
       log "INFO" "Docker found, checking permissions..."
        
        # Test Docker connectivity with timeout (5 seconds)
        if ! timeout 5 docker info &>/dev/null; then
            log "WARN" "Docker permission issues detected"
            
            # Check if docker group exists
            if getent group docker &>/dev/null; then
                # Check if user is already in the docker group
                if ! groups | grep -q docker; then
                    log "INFO" "Adding current user to docker group..."
                    sudo usermod -aG docker $USER
                    
                    # Fix socket permissions
                    if [[ -S /var/run/docker.sock ]]; then
                        log "INFO" "Fixing Docker socket permissions..."
                        sudo chown root:docker /var/run/docker.sock
                        sudo chmod 660 /var/run/docker.sock
                    fi
                    
                    # Mark WSL as configured BEFORE asking about restart
                    mkdir -p "$(dirname "$wsl_state_file")"
                    echo "WSL configured on $(date)" > "$wsl_state_file"
                    
                    log "WARN" "Docker permissions fixed. You need to log out and back in for group changes to take effect"
                    log "INFO" "Would you like to restart the WSL session now? (y/n): "
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        log "INFO" "Requesting WSL restart..."
                        # Use PowerShell to restart WSL
                        powershell.exe -Command "wsl --shutdown" || true
                        log "INFO" "WSL shutdown requested. Please restart your WSL session manually."
                        exit 0
                    else
                        log "INFO" "Please restart your WSL session manually for changes to take effect"
                    fi
                else
                    log "INFO" "User already in docker group, but Docker still not accessible"
                    log "INFO" "This could be a Docker Desktop configuration issue"
                    # Still mark as configured
                    mkdir -p "$(dirname "$wsl_state_file")"
                    echo "WSL configured on $(date)" > "$wsl_state_file"
                fi
            else
                log "ERROR" "Docker group not found. Docker may not be properly installed"
                # Still mark as configured to avoid endless loops
                mkdir -p "$(dirname "$wsl_state_file")"
                echo "WSL configured on $(date)" > "$wsl_state_file"
            fi
        else
            log "INFO" "Docker permissions are correctly configured"
            # Mark as configured
            mkdir -p "$(dirname "$wsl_state_file")"
            echo "WSL configured on $(date)" > "$wsl_state_file"
        fi

        log "INFO" "checking WSL integration..."
        
        if ! docker info &>/dev/null; then
            log "WARN" "Docker command exists but daemon is not accessible."
            log "INFO" "Please ensure Docker Desktop is running with WSL integration enabled for this distribution."
            log "INFO" "Steps to enable:"
            log "INFO" "1. Open Docker Desktop"
            log "INFO" "2. Go to Settings > Resources > WSL Integration"
            log "INFO" "3. Enable integration with this distribution"
            log "INFO" "4. Click 'Apply & Restart'"
        else
            log "INFO" "Docker Desktop WSL integration is working correctly."
        fi
    else
        # No Docker, but still mark as configured
        mkdir -p "$(dirname "$wsl_state_file")"
        echo "WSL configured on $(date)" > "$wsl_state_file"
    fi
    
    # Configure systemd if not already enabled
    if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
        log "INFO" "WSL distribution would benefit from systemd support."
        read -p "Would you like to enable systemd in WSL? (requires sudo, y/n): " confirm
        
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            log "INFO" "Configuring systemd support in WSL..."
            
            sudo tee /etc/wsl.conf > /dev/null << EOF
[boot]
systemd=true

[automount]
enabled=true
options=metadata,uid=1000,gid=1000,umask=022

[network]
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=true
EOF
            
            log "WARN" "WSL configured with systemd support. You must restart WSL for changes to take effect."
            log "INFO" "Run 'wsl.exe --shutdown' from PowerShell to restart WSL."
        fi
    fi
    
    # Mark WSL as configured
    mkdir -p "$(dirname "$wsl_state_file")"
    echo "WSL configured on $(date)" > "$wsl_state_file"
    log "INFO" "WSL configuration complete and marked as configured"

    return 0
}
# Verify environment
verify_environment() {
    # Check for required directories
    for dir in "$SCRIPT_DIR" "$MODULES_DIR"; do
        if [[ ! -d "$dir" ]]; then
            log "ERROR" "Required directory not found: $dir"
            return 1
        fi
    done
    
    # Check for global config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR" "Global config not found: $CONFIG_FILE"
        return 1
    fi
    
    # Ensure jq is available
    if ! ensure_json_parser; then
        log "ERROR" "jq is not available"
        return 1
    fi
    
    # Validate global config
    if ! validate_json "$CONFIG_FILE"; then
        log "ERROR" "Config validation failed"
        return 1
    fi
    
    return 0
}

# Get ordered list of enabled modules
get_ordered_modules() {
    local modules=($(get_json_value "$CONFIG_FILE" '.global.modules.order[]'))
    local enabled_modules=()
    
    for module in "${modules[@]}"; do
        if is_module_enabled "$module"; then
            enabled_modules+=("$module")
        fi
    done
    
    printf '%s\n' "${enabled_modules[@]}"
}

# Execute a stage for modules
execute_stage() {
    local stage=$1
    local specific_module=${2:-}
    local force=${3:-false}
    local -a modules
    
    if [[ -n "$specific_module" ]]; then
        if ! verify_module "$specific_module"; then
            return 1
        fi
        modules=("$specific_module")
    else
        readarray -t modules < <(get_ordered_modules)
    fi
    
    if [[ ${#modules[@]} -eq 0 ]]; then
        log "WARN" "No enabled modules found"
        return 0
    fi
    
    log "INFO" "Executing stage: $stage"
    local exit_code=0
    
    for module in "${modules[@]}"; do
        # Initialize module context
        if ! init_module "$module"; then
            log "ERROR" "Failed to initialize module: $module"
            continue
        fi
        
        # Check if there's a platform-specific implementation
        local module_script="$MODULES_DIR/$module/$PLATFORM/$module.sh"
        
        # Fall back to common implementation if platform-specific one doesn't exist
        if [[ ! -f "$module_script" ]]; then
            module_script="$MODULES_DIR/$module/$module.sh"
        fi
        
        if [[ -f "$module_script" ]]; then
            log "INFO" "Running $stage for module: $module" "$module"
            
            case "$stage" in
                "install")
                    bash "$module_script" "$stage" "$force" || exit_code=1
                    ;;
                "info")
                    bash "$module_script" "$stage" || true  # Don't fail on info
                    ;;
                *)
                    bash "$module_script" "$stage" || exit_code=1
                    ;;
            esac
        else
            log "ERROR" "Module script not found: $module_script" "$module"
            [[ "$stage" != "grovel" ]] && exit_code=1
        fi
    done
    
    return $exit_code
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 COMMAND [MODULE] [OPTIONS]

Commands:
  install   Install one or all modules
  remove    Remove one or all modules
  verify    Verify one or all modules
  info      Show information about one or all modules
  backup    Create backup of current environment
  restore   Restore from backup

Options:
  --force   Force installation even if already installed

Examples:
  $0 install              # Install all modules
  $0 install git --force  # Force install git module
  $0 info docker         # Show docker module information
  $0 verify             # Verify all modules
EOF
}

create_backup() {
    local specific_module=${1:-}
    local -a modules
    
    if [[ -n "$specific_module" ]]; then
        modules=("$specific_module")
    else
        readarray -t modules < <(get_ordered_modules)
    fi
    
    for module in "${modules[@]}"; do
        # Initialize module context
        if ! init_module "$module"; then
            log "ERROR" "Failed to initialize module: $module"
            continue
        fi
        
        log "INFO" "Creating backup for module: $module" "$module"
        
        # Get module-specific backup paths from global config
        local paths=($(get_module_config "$module" '.backup.paths[]'))
        
        # Get platform-specific backup paths
        #local platform_paths=($(get_module_config "$module" ".platforms.$PLATFORM.backup.paths[]" || echo ""))
        
        # Combine paths
        paths+=("${platform_paths[@]}")
        
        for path in "${paths[@]}"; do
            path=$(eval echo "$path")  # Expand environment variables
            if [[ -e "$path" ]]; then
                backup_file "$path" "$module"
            fi
        done
    done
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    # Parse arguments
    local action=$1
    shift
    local specific_module=""
    local force="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force="true"
                shift
                ;;
            *)
                if [[ -z "$specific_module" ]]; then
                    specific_module="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Verify environment first
    if ! verify_environment; then
        log "ERROR" "Environment verification failed"
        exit 1
    fi

    if [[ "$action" == "install" && "$force" == "true" ]]; then
        # Enable force reconfiguration if --force is specified
        # Remove the WSL configured flag if it exists
        rm -f "${DEVENV_STATE_DIR}/wsl_configured"
        setup_wsl_environment "--force"
    else
        # Normal configuration check
        setup_wsl_environment
    fi
    
    case "$action" in
        install)
            create_backup "$specific_module"
            execute_stage "install" "$specific_module" "$force"
            ;;
        remove)
            execute_stage "remove" "$specific_module"
            ;;
        verify)
            execute_stage "verify" "$specific_module"
            ;;
        info)
            execute_stage "info" "$specific_module"
            ;;
        backup)
            create_backup "$specific_module"
            ;;
        restore)
            log "ERROR" "Restore functionality not yet implemented"
            exit 1
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi