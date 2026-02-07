#!/bin/bash
# modules/conda/conda.sh - Conda module implementation

# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "conda" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/conda.state"

# Define module components
COMPONENTS=(
    "core"          # Base Conda installation 
    "channels"      # Channel configuration and local channel setup
    "shell"         # Shell integration (ZSH setup)
    "vscode"        # VSCode integration
    "docker"        # Docker integration
)

# Display module information
show_module_info() {
    cat << 'EOF'

🐍 Conda Environment Manager
=========================

Description:
-----------
Professional Conda environment with optimized configuration,
local channel support, and comprehensive development integrations.

Benefits:
--------
✓ Complete Package Management - Conda environments and packages
✓ Local Channel Support - Custom package hosting and distribution
✓ IDE Integration - VSCode and Jupyter support preconfigured
✓ Container Ready - Docker integration for reproducible environments
✓ Shell Enhanced - ZSH integration with useful aliases

Components:
----------
1. Core Conda
   - Miniconda3 base installation
   - Conda package manager
   - Environment management

2. Channel Configuration
   - Local channel support
   - Custom package hosting
   - Channel priority management

3. Development Tools
   - IPython for enhanced REPL
   - Jupyter notebooks/lab
   - Package building tools

Integrations:
-----------
• VSCode - Conda environment selection and Jupyter support
• Docker - Container templates with Conda preinstalled
• ZSH - Shell completion and environment activation

Quick Start:
-----------
1. Activate environment:
   $ ca myenv

2. Install packages:
   $ ci numpy pandas

3. Create from file:
   $ cmb  # Uses environment.yml

4. List environments:
   $ ce

Aliases:
-------
Environment:
ca      : conda activate
cda     : conda deactivate
cl      : conda list
ce      : conda env list

Package Management:
ci      : conda install -y
cr      : conda remove -y
cu      : conda update -y

Environment Files:
cmb     : conda env create -f
cmu     : conda env update -f
cmr     : conda env remove -n

Configuration:
-------------
Location: ~/.condarc
Directories:
- ~/Development/conda/channels  : Local channel storage
- ~/Development/conda/envs     : Environment location
- ~/Development/conda/pkgs     : Package cache

Tips:
----
• Use local channels for custom packages
• Keep base environment minimal
• Create specific environments per project
• Use environment.yml for reproducibility

For more information:
-------------------
Documentation: https://docs.conda.io
Support: https://anaconda.org/conda/conda/issues

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    ensure_conda_loaded
                    if command -v conda &>/dev/null; then
                        echo "  Version: $(conda --version)"
                        echo "  Python: $(conda run python --version 2>/dev/null)"
                    fi
                    ;;
                "channels")
                    local channels=$(conda config --show channels | grep -v "^#")
                    echo "  Configured channels:"
                    echo "$channels" | sed 's/^/    /'
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

# Ensure Conda is loaded into the current shell session
ensure_conda_loaded() {
    if command -v conda &>/dev/null; then
        return 0
    fi
    local conda_root="${HOME}/miniconda3"
    # Try module config path if available
    local config_root
    config_root=$(get_module_config "conda" ".shell.paths.conda_root" 2>/dev/null) || true
    if [[ -n "$config_root" && "$config_root" != "null" ]]; then
        conda_root=$(echo "$config_root" | expand_vars)
    fi
    if [[ -s "$conda_root/etc/profile.d/conda.sh" ]]; then
        \. "$conda_root/etc/profile.d/conda.sh"
        return 0
    elif [[ -d "$conda_root/bin" ]]; then
        export PATH="$conda_root/bin:$PATH"
        return 0
    fi
    return 1
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            ensure_conda_loaded
            command -v conda &>/dev/null && \
            conda info &>/dev/null
            ;;
        "channels")
            verify_channels
            ;;
        "shell")
            verify_shell_integration
            ;;
        "vscode")
            verify_vscode_integration
            ;;
        "docker")
            verify_docker_integration
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Component verification helpers
verify_channels() {
    local channel_dir=$(get_module_config "conda" ".shell.paths.channel_dir")
    channel_dir=$(echo "$channel_dir" | expand_vars)
    
    [[ -d "$channel_dir" ]] && \
    [[ -f "$channel_dir/channeldata.json" ]] && \
    [[ -d "$channel_dir/linux-64" ]] && \
    [[ -d "$channel_dir/noarch" ]]
}

verify_shell_integration() {
    local modules_dir=$(get_aliases_dir)
    local completions_dir=$(get_module_config "zsh" ".shell.paths.completions_dir")
    completions_dir=$(echo "$completions_dir" | expand_vars)
    
    [[ -f "$modules_dir/conda.zsh" ]] && \
    [[ -f "$completions_dir/_conda" ]] && \
    list_module_aliases "conda" "conda" &>/dev/null && \
    list_module_aliases "conda" "env" &>/dev/null
}

verify_vscode_integration() {
    local vscode_config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    vscode_config_dir=$(echo "$vscode_config_dir" | expand_vars)
    [[ -f "$vscode_config_dir/settings.json" ]] && \
    grep -q "python.condaPath" "$vscode_config_dir/settings.json"
}

verify_docker_integration() {
    local templates_dir=$(get_module_config "conda" ".shell.paths.templates_dir")
    templates_dir=$(echo "$templates_dir" | expand_vars)
    [[ -f "$templates_dir/Dockerfile.conda" ]]
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "conda"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_conda_package; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "channels")
            if configure_channels; then
                save_state "channels" "installed"
                return 0
            fi
            ;;
        "shell")
            if configure_shell_integration; then
                save_state "shell" "installed"
                return 0
            fi
            ;;
        "vscode")
            if configure_vscode_integration; then
                save_state "vscode" "installed"
                return 0
            fi
            ;;
        "docker")
            if configure_docker_integration; then
                save_state "docker" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Component installation implementations
install_conda_package() {
    local conda_root=$(get_module_config "conda" ".shell.paths.conda_root")
    conda_root=$(echo "$conda_root" | expand_vars)

    if [[ -d "$conda_root" ]]; then
        log "INFO" "Conda already installed at $conda_root" "conda"
        export PATH="$conda_root/bin:$PATH"
        conda update -n base conda -y
        return 0
    fi

    local installer_url=$(get_module_config "conda" ".package.installer_urls[\"linux-x86_64\"]")
    local installer_script="/tmp/miniconda.sh"

    wget -q "$installer_url" -O "$installer_script" || return 1
    bash "$installer_script" -b -p "$conda_root" || return 1
    rm -f "$installer_script"

    export PATH="$conda_root/bin:$PATH"
    conda init bash
    conda init zsh

    return 0
}

configure_channels() {
    local channel_dir=$(get_module_config "conda" ".shell.paths.channel_dir")
    channel_dir=$(echo "$channel_dir" | expand_vars)

    mkdir -p "$channel_dir"/{linux-64,noarch}

    # Initialize channel metadata
    for subdir in linux-64 noarch; do
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
        bzip2 -k -f "$channel_dir/$subdir/repodata.json"
    done

    # Create channeldata.json
    cat > "$channel_dir/channeldata.json" << EOF
{
    "channeldata_version": 1,
    "packages": {},
    "subdirs": ["linux-64", "noarch"]
}
EOF

    # Configure .condarc
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
EOF

    conda clean -y --all
    return 0
}

configure_shell_integration() {
    local modules_dir=$(get_aliases_dir)
    local conda_init="$modules_dir/conda.zsh"

    mkdir -p "$modules_dir"

    # Create conda initialization script
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

# Initialize conda completion
if [ -f "$completions_dir/_conda" ]; then
    fpath=($completions_dir $fpath)
    compinit conda
fi
EOF

    # Install conda completion
    if [ ! -f "$completions_dir/_conda" ]; then
        log "INFO" "Installing conda completion..." "conda"
        curl -fsSL "https://raw.githubusercontent.com/esc/conda-zsh-completion/master/_conda" \
            -o "$completions_dir/_conda"
    fi

    # Add aliases
    add_module_aliases "conda" "conda" || return 1
    add_module_aliases "conda" "env" || return 1

    return 0
}

configure_vscode_integration() {
    local vscode_settings=$(get_module_config "conda" ".vscode.settings")
    [[ -z "$vscode_settings" ]] && return 0

    vscode_settings=$(echo "$vscode_settings" | expand_vars)
    local vscode_config_dir=$(get_module_config "vscode" ".shell.paths.config_dir")
    vscode_config_dir=$(echo "$vscode_config_dir" | expand_vars)
    local settings_file="$vscode_config_dir/settings.json"

    mkdir -p "$vscode_config_dir"

    if [[ -f "$settings_file" ]]; then
        local temp_settings=$(mktemp)
        jq -s '.[0] * .[1]' "$settings_file" <(echo "$vscode_settings") > "$temp_settings" && \
        mv "$temp_settings" "$settings_file"
    else
        echo "$vscode_settings" > "$settings_file"
    fi

    # Install extensions
    local extensions=($(get_module_config "conda" ".vscode.extensions[]"))
    for ext in "${extensions[@]}"; do
        code --install-extension "$ext" --force
    done

    return 0
}

configure_docker_integration() {
    local templates_dir=$(get_module_config "conda" ".shell.paths.templates_dir")
    templates_dir=$(echo "$templates_dir" | expand_vars)

    mkdir -p "$templates_dir"

    cat > "$templates_dir/Dockerfile.conda" << EOF
FROM continuumio/miniconda3:latest

# Copy environment file
COPY environment.yml /tmp/

# Create conda environment
RUN conda env create -f /tmp/environment.yml

# Set default command
CMD ["/bin/bash"]
EOF

    return 0
}

# Grovel checks existence and basic functionality
grovel_conda() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "conda"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_conda() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_conda &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "conda"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "conda"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "conda"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Remove conda configuration
remove_conda() {
    log "INFO" "Removing Conda configuration..." "conda"

    # Backup existing configurations
    [[ -f "$HOME/.condarc" ]] && backup_file "$HOME/.condarc" "conda"

    # Remove shell integration
    local modules_dir=$(get_aliases_dir)
    rm -f "$modules_dir/conda.zsh"

    # Remove aliases
    remove_module_aliases "conda" "conda"
    remove_module_aliases "conda" "env"

    # Remove development directories
    local dev_base="$HOME/Development/conda"
    [[ -d "$dev_base" ]] && rm -rf "$dev_base"

    # Remove state file
    rm -f "$STATE_FILE"

    log "WARN" "Conda installation preserved at $HOME/miniconda3. Run 'rm -rf ~/miniconda3' to remove completely." "conda"

    return 0
}

# Verify entire installation
verify_conda() {
    log "INFO" "Verifying Conda installation..." "conda"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "conda"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "Conda verification completed successfully" "conda"
        conda --version
        conda info --base
    fi

    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_conda
        ;;
    install)
        install_conda "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_conda
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_conda
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "conda"
        exit 1
        ;;
esac