#!/bin/bash
# modules/conda/conda.sh - Conda module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"  # Load logging first
source "$SCRIPT_DIR/json.sh"     # Then JSON handling
source "$SCRIPT_DIR/module.sh"   # Then module utilities
source "$SCRIPT_DIR/backup.sh"   # Finally backup utilities
source "$SCRIPT_DIR/alias.sh"    # For shell alias support

# Initialize module
init_module "conda" || exit 1

ensure_conda_path() {
    local conda_root=$(get_module_config "conda" ".shell.paths.conda_root")
    conda_root=$(eval echo "$conda_root")
    export PATH="$conda_root/bin:$PATH"
}

# Check for conda installation and configuration
grovel_conda() {
    local conda_root=$(get_module_config "conda" ".shell.paths.conda_root")
    conda_root=$(eval echo "$conda_root")
    
    if [[ ! -d "$conda_root" ]]; then
        log "INFO" "Conda installation not found" "conda"
        return 1
    fi

    if ! command -v conda &>/dev/null; then
        log "INFO" "Conda command not found in PATH" "conda"
        return 1
    fi

    # Check for local channel directory
    local channel_dir=$(get_module_config "conda" ".shell.paths.channel_dir")
    channel_dir=$(eval echo "$channel_dir")
    if [[ ! -d "$channel_dir" ]]; then
        log "INFO" "Local channel directory not found" "conda"
        return 1
    fi

    return 0
}

# Install and configure conda
install_conda() {
    log "INFO" "Setting up Conda environment..." "conda"

    # Install conda if needed
    if ! command -v conda &>/dev/null; then
        if ! install_conda_package; then
            return 1
        fi
    fi

    # Ensure conda is in PATH
    ensure_conda_path
    
    local conda_root=$(get_module_config "conda" ".shell.paths.conda_root")
    conda_root=$(eval echo "$conda_root")

    # Configure conda
    if ! configure_conda; then
        return 1
    fi

    # Set up local channel repository
    if ! setup_local_channel; then
        return 1
    fi

    # Configure shell integration
    if ! configure_shell_integration; then
        return 1
    fi

    # Configure VSCode integration
    if ! configure_vscode_integration; then
        return 1
    fi

    # Configure Docker integration
    if ! configure_docker_integration; thens
        return 1
    fi

    # Add conda aliases
    add_module_aliases "conda" "conda" || return 1
    add_module_aliases "conda" "env" || return 1

    # Reload shell configuration to ensure conda is available
    if [[ -f "$conda_root/etc/profile.d/conda.sh" ]]; then
        source "$conda_root/etc/profile.d/conda.sh"
    else
        log "WARN" "Conda shell script not found at $conda_root/etc/profile.d/conda.sh" "conda"
    fi
    
    if [ $? -eq 0 ]; then
        show_conda_summary
    fi
    
    return 0
}

reset_conda_config() {
    log "INFO" "Resetting conda configuration..." "conda"
    
    # Backup existing configuration
    [[ -f "$HOME/.condarc" ]] && backup_file "$HOME/.condarc" "conda"
    
    # Remove existing .condarc
    rm -f "$HOME/.condarc"
    
    # Create minimal configuration
    cat > "$HOME/.condarc" << EOF
channels:
  - defaults
channel_priority: strict
EOF
    
    return 0
}

# Install Conda package
install_conda_package() {
    log "INFO" "Installing Conda..." "conda"

    local conda_root=$(get_module_config "conda" ".shell.paths.conda_root")
    conda_root=$(eval echo "$conda_root")

    # Check if conda is already installed
    if [[ -d "$conda_root" ]]; then
        log "INFO" "Conda already installed at $conda_root" "conda"
        
        # Add conda to PATH
        export PATH="$conda_root/bin:$PATH"
        
        # Reset conda configuration
        reset_conda_config || return 1
        
        # Update conda using default channel only
        if conda update -n base conda -y; then
            log "INFO" "Successfully updated existing conda installation" "conda"
            return 0
        else
            log "ERROR" "Failed to update existing conda installation" "conda"
            return 1
        fi
    fi

    # If not installed, proceed with fresh installation
    local installer_url=$(get_module_config "conda" ".package.installer_urls[\"linux-x86_64\"]")
    log "DEBUG" "Installer URL: $installer_url" "conda"
    
    local installer_script="/tmp/miniconda.sh"

    if ! wget -q "$installer_url" -O "$installer_script"; then
        log "ERROR" "Failed to download Conda installer" "conda"
        return 1
    fi

    # Install Miniconda
    if ! bash "$installer_script" -b -p "$conda_root"; then
        log "ERROR" "Failed to install Conda" "conda"
        rm -f "$installer_script"
        return 1
    fi

    # Clean up
    rm -f "$installer_script"

    # Add to PATH
    export PATH="$conda_root/bin:$PATH"

    # Initialize conda for shell
    "$conda_root/bin/conda" init bash
    "$conda_root/bin/conda" init zsh

    return 0
}
# Configure conda
configure_conda() {
    log "INFO" "Configuring Conda..." "conda"

    # Add conda to PATH for this session
    local conda_root=$(get_module_config "conda" ".shell.paths.conda_root")
    conda_root=$(eval echo "$conda_root")
    export PATH="$conda_root/bin:$PATH"

    # Set up development directories
    local dev_base="$HOME/Development/conda"
    mkdir -p "$dev_base"/{channels,envs,pkgs,templates}

    local channel_dir="$dev_base/channels"
    local envs_dir="$dev_base/envs"
    local pkgs_dir="$dev_base/pkgs"

    # Create channel directory structure
    mkdir -p "$channel_dir"/{linux-64,noarch}
    
    # Create initial repodata files with proper structure
    for subdir in linux-64 noarch; do
        log "DEBUG" "Creating repodata for $subdir" "conda"
        
        # Create directory if it doesn't exist
        mkdir -p "$channel_dir/$subdir"
        
        # Create repodata.json
        cat > "$channel_dir/$subdir/repodata.json" << EOF
{
    "info": {
        "subdir": "$subdir"
    },
    "packages": {},
    "packages.conda": {},
    "removed": [],
    "repodata_version": 1
}
EOF
        
        # Create .bz2 version
        bzip2 -k -f "$channel_dir/$subdir/repodata.json"
        
        # Create channeldata.json in root if it doesn't exist
        if [[ ! -f "$channel_dir/channeldata.json" ]]; then
            cat > "$channel_dir/channeldata.json" << EOF
{
    "channeldata_version": 1,
    "packages": {},
    "subdirs": ["linux-64", "noarch"]
}
EOF
        fi
    done

    # Configure conda with all settings
    cat > "$HOME/.condarc" << EOF
channels:
  - defaults
  - conda-forge
  - file://$channel_dir
channel_priority: strict
create_default_packages:
  - pip
  - ipython
  - jupyter
env_prompt: ({name})
auto_activate_base: false
pip_interop_enabled: true
envs_dirs:
  - $envs_dir
pkgs_dirs:
  - $pkgs_dir
pkg_format: '2'
EOF

    # Clear the conda cache to ensure clean start
    conda clean -y --all

    # Update conda using default channels only
    if ! conda update -n base -c defaults conda -y; then
        log "ERROR" "Failed to update conda" "conda"
        return 1
    fi

    # Verify channel access
    if ! conda search --json -c "file://$channel_dir" > /dev/null 2>&1; then
        log "ERROR" "Local channel verification failed" "conda"
        return 1
    fi

    log "INFO" "Conda configuration complete" "conda"
    return 0
}

# Configure shell integration
configure_shell_integration() {
    log "INFO" "Configuring shell integration..." "conda"

    local modules_dir=$(get_aliases_dir)
    local conda_init="$modules_dir/conda.zsh"

    # Add conda initialization to ZSH
    cat > "$conda_init" << 'EOF'
# Conda initialization
__conda_setup="$($HOME/miniconda3/bin/conda 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
EOF

    return 0
}

# Configure VSCode integration
configure_vscode_integration() {
    log "INFO" "Configuring VSCode integration..." "conda"

    # Get VSCode settings
    local vscode_settings=$(get_module_config "conda" ".vscode.settings")
    
    if [[ -z "$vscode_settings" ]]; then
        log "WARN" "No VSCode settings found in config" "conda"
        return 0
    fi
    
    # Expand environment variables in settings
    vscode_settings=$(echo "$vscode_settings" | envsubst)
    
    # Update VSCode settings using the vscode module's configuration
    local vscode_config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    vscode_config_dir=$(eval echo "$vscode_config_dir")
    local settings_file="$vscode_config_dir/settings.json"

    mkdir -p "$vscode_config_dir"

    if [[ -f "$settings_file" ]]; then
        # Merge settings
        local temp_settings=$(mktemp)
        if ! jq -s '.[0] * .[1]' "$settings_file" <(echo "$vscode_settings") > "$temp_settings"; then
            log "ERROR" "Failed to merge VSCode settings" "conda"
            rm -f "$temp_settings"
            return 1
        fi
        mv "$temp_settings" "$settings_file"
    else
        echo "$vscode_settings" > "$settings_file"
    fi

    # Install required extensions
    local extensions
    if ! extensions=($(get_module_config "conda" ".vscode.extensions[]")); then
        log "WARN" "No VSCode extensions found in config" "conda"
        return 0
    fi

    for ext in "${extensions[@]}"; do
        if [[ -n "$ext" ]]; then
            code --install-extension "$ext" --force
        fi
    done

    return 0
}

# Configure Docker integration
configure_docker_integration() {
    log "INFO" "Configuring Docker integration..." "conda"

    local channel_dir=$(get_module_config "conda" ".shell.paths.channel_dir")
    local templates_dir=$(get_module_config "conda" ".shell.paths.templates_dir")
    channel_dir=$(eval echo "$channel_dir")
    templates_dir=$(eval echo "$templates_dir")

    # Create templates directory
    mkdir -p "$templates_dir"

    cat > "$templates_dir/Dockerfile.conda" << EOF
FROM continuumio/miniconda3:latest

# Mount point for local channel
VOLUME ["$channel_dir:/opt/conda/channels"]

# Copy environment file
COPY environment.yml /tmp/

# Create conda environment
RUN conda env create -f /tmp/environment.yml

# Set default command
CMD ["/bin/bash"]
EOF

    return 0
}

# Remove conda configuration
remove_conda() {
    log "INFO" "Removing Conda configuration..." "conda"

    # Backup existing configurations
    [[ -f "$HOME/.condarc" ]] && backup_file "$HOME/.condarc" "conda"

    # Remove conda initialization from shell
    local modules_dir=$(get_aliases_dir)
    rm -f "$modules_dir/conda.zsh"

    # Remove aliases
    remove_module_aliases "conda" "conda"
    remove_module_aliases "conda" "env"

    # Remove development directories
    local dev_base="$HOME/Development/conda"
    if [[ -d "$dev_base" ]]; then
        log "INFO" "Removing conda development directories..." "conda"
        rm -rf "$dev_base"
    fi

    log "WARN" "Conda installation preserved at $HOME/miniconda3. Run 'rm -rf ~/miniconda3' to remove completely." "conda"

    return 0
}

# Verify conda installation and configuration
verify_conda() {
    log "INFO" "Verifying Conda installation..." "conda"
    local status=0

    # Ensure conda is in PATH
    ensure_conda_path

    # Check conda installation
    if ! command -v conda &>/dev/null; then
        log "ERROR" "Conda is not installed" "conda"
        status=1
    fi

    # Check conda initialization
    local modules_dir=$(get_aliases_dir)
    if [[ ! -f "$modules_dir/conda.zsh" ]]; then
        log "ERROR" "Conda shell integration not configured" "conda"
        status=1
    fi

    # Check development directories
    local dev_base="$HOME/Development/conda"
    local channel_dir="$dev_base/channels"
    local envs_dir="$dev_base/envs"
    local pkgs_dir="$dev_base/pkgs"

    for dir in "$channel_dir" "$envs_dir" "$pkgs_dir"; do
        if [[ ! -d "$dir" ]]; then
            log "ERROR" "Directory not found: $dir" "conda"
            status=1
        fi
    done

    # Check channel structure
    for subdir in linux-64 noarch; do
        if [[ ! -f "$channel_dir/$subdir/repodata.json" ]] || [[ ! -f "$channel_dir/$subdir/repodata.json.bz2" ]]; then
            log "ERROR" "Missing repodata files in $subdir" "conda"
            status=1
        fi
    done

    if [[ ! -f "$channel_dir/channeldata.json" ]]; then
        log "ERROR" "Missing channeldata.json" "conda"
        status=1
    fi

    # Check conda configuration
    if ! conda config --show channels | grep -q "file://$channel_dir"; then
        log "ERROR" "Local channel not configured" "conda"
        status=1
    fi

    # Check aliases
    if ! list_module_aliases "conda" "conda" &>/dev/null || \
       ! list_module_aliases "conda" "env" &>/dev/null; then
        log "ERROR" "Conda aliases not configured" "conda"
        status=1
    fi

    # Check if conda is functional
    if ! conda list &>/dev/null; then
        log "ERROR" "Conda is not functioning properly" "conda"
        status=1
    fi

    if [ $status -eq 0 ]; then
        log "INFO" "Conda verification completed successfully" "conda"
        
        # Show installation details
        log "INFO" "Conda version:" "conda"
        conda --version
        
        log "INFO" "Configured channels:" "conda"
        conda config --show channels | grep -v "^#"
    fi

    return $status
}

show_conda_summary() {
    cat << 'EOF'

🐍 Conda Setup Complete - Quick Reference
=======================================

Environment Management:
---------------------
ca   : conda activate         - Activate an environment
cda  : conda deactivate      - Deactivate current environment
cl   : conda list            - List installed packages
ce   : conda env list        - List all environments
ci   : conda install -y      - Install packages
cr   : conda remove -y       - Remove packages
cu   : conda update -y       - Update packages

Environment File Commands:
------------------------
cmb  : conda env create -f   - Build environment from environment.yml
cmu  : conda env update -f   - Update environment from environment.yml
cmr  : conda env remove -n   - Remove an environment

Local Channel Repository:
-----------------------
Location: ~/conda-channels/
Structure:
  ~/conda-channels/
  ├── linux-64/    - Platform-specific packages
  └── noarch/      - Platform-independent packages

To add packages to local channel:
1. Download package: conda download <package>
2. Copy to appropriate directory: 
   - For most packages: ~/conda-channels/linux-64/
   - For noarch packages: ~/conda-channels/noarch/
3. Index channel: conda index ~/conda-channels/

Docker Integration:
-----------------
- Base image: continuumio/miniconda3:latest
- Local channel mounted at: /opt/conda/channels
- Template available at: ~/.devenv/modules/conda/templates/Dockerfile.conda

VSCode Integration:
-----------------
- Python and Jupyter extensions installed
- Conda path configured
- Environment switching supported
- Jupyter notebook support enabled

Common Workflows:
---------------
1. Create new environment:
   $ cmb  # Reads from environment.yml
   or
   $ conda create -n myenv python=3.9

2. Activate and install packages:
   $ ca myenv
   $ ci numpy pandas

3. Create environment.yml:
   $ conda env export > environment.yml

4. Use with Docker:
   $ docker build -f ~/.devenv/modules/conda/templates/Dockerfile.conda .

5. Open in VSCode:
   - Use Command Palette (Ctrl+Shift+P)
   - Select "Python: Select Interpreter"
   - Choose your conda environment

Documentation:
------------
- Conda commands: conda --help
- Environment files: conda env --help
- More info: https://docs.conda.io

EOF

    # Show current conda version
    echo "Currently installed conda version:"
    conda --version

    # Show configured channels
    echo -e "\nConfigured channels (in order of priority):"
    conda config --show channels | grep -v "^#" | grep "  -"
}
# Execute requested action
case "${1:-}" in
    grovel)
        grovel_conda
        ;;
    install)
        install_conda
        ;;
    remove)
        remove_conda
        ;;
    verify)
        verify_conda
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "conda"
        exit 1
        ;;
esac