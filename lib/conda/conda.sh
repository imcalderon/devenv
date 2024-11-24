#!/bin/bash
# lib/conda/conda.sh - Conda module implementation

# Use environment variables set by devenv.sh, with fallback if running standalone
if [ -z "${ROOT_DIR:-}" ]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Source dependencies using SCRIPT_DIR
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/module_base.sh"

grovel_conda() {
    log "INFO" "Checking Conda dependencies..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local conda_path="${config_modules_conda_paths_root}/bin/conda"
    if [ ! -f "$conda_path" ]; then
        log "INFO" "Conda not found at $conda_path"
        return 1
    fi
}

install_conda() {
    log "INFO" "Setting up Conda environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Install Miniconda if not present
    if [ ! -d "${config_modules_conda_paths_root}" ]; then
        install_miniconda
    else
        log "INFO" "Updating existing Conda installation..."
        source "${config_modules_conda_paths_root}/etc/profile.d/conda.sh"
        conda update -n base -c defaults conda -y
    fi
    
    # Configure conda
    configure_conda
    
    # Create environments
    create_environments
    
    # Initialize shell integration
    local shells=("bash" "zsh")
    for shell in "${shells[@]}"; do
        local rc_file="$HOME/.${shell}rc"
        if [ -f "$rc_file" ]; then
            "${config_modules_conda_paths_root}/bin/conda" init "$shell"
        fi
    done

    return 0
}

install_miniconda() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    log "INFO" "Installing Miniconda..."
    wget "${config_modules_conda_installer_url}" -O "${config_modules_conda_installer_path}"
    bash "${config_modules_conda_installer_path}" -b -p "${config_modules_conda_paths_root}"
    rm "${config_modules_conda_installer_path}"
    
    # Initialize conda for shells
    "${config_modules_conda_paths_root}/bin/conda" init bash
    "${config_modules_conda_paths_root}/bin/conda" init zsh
}

configure_conda() {
    log "INFO" "Configuring Conda..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local condarc="$HOME/.condarc"
    backup_file "$condarc"
    
    # Create .condarc with base configuration
    cat > "$condarc" << EOF
# Channels configuration
channels:
$(for channel in "${config_modules_conda_base_config_channels[@]}"; do echo "  - $channel"; done)

# Channel priority
channel_priority: ${config_modules_conda_base_config_channel_priority}

# Solver settings
solver: ${config_modules_conda_base_config_solver}

# Environment locations
envs_dirs:
  - ${config_modules_conda_paths_envs}

# Local package repository path
pkg_dirs:
  - ${config_modules_conda_paths_packages}

# Additional settings
auto_activate_base: ${config_modules_conda_base_config_auto_activate_base}
always_yes: ${config_modules_conda_base_config_always_yes}
notify_outdated_conda: ${config_modules_conda_base_config_notify_outdated_conda}
pip_interop_enabled: ${config_modules_conda_base_config_pip_interop_enabled}
EOF
}

create_environments() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    source "${config_modules_conda_paths_root}/etc/profile.d/conda.sh"
    
    # Create development directory structure
    mkdir -p "${config_modules_conda_paths_packages}"
    mkdir -p "${config_modules_conda_paths_pkg_build}"
    mkdir -p "${config_modules_conda_paths_pkg_dist}"
    
    # Loop through each environment in config
    for env_name in $(get_environment_names); do
        log "INFO" "Setting up $env_name environment..."
        
        # Create basic environment if it doesn't exist
        if ! conda env list | grep -q "^${env_name} "; then
            conda create -n "$env_name" -y
        fi
        
        # Activate environment
        conda activate "$env_name"
        
        # Install packages for each category in the environment
        for category in $(get_environment_categories "$env_name"); do
            log "INFO" "Installing $category packages for $env_name..."
            local packages=($(get_environment_packages "$env_name" "$category"))
            if [ ${#packages[@]} -gt 0 ]; then
                conda install -y "${packages[@]}"
            fi
        done
        
        conda deactivate
    done
}

get_environment_names() {
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    echo "${!config_modules_conda_environments[@]}" | tr ' ' '\n' | sort
}

get_environment_categories() {
    local env_name=$1
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    local prefix="config_modules_conda_environments_${env_name}_packages_"
    compgen -A variable | grep "^$prefix" | sed "s/^$prefix//" | cut -d_ -f1 | sort -u
}

get_environment_packages() {
    local env_name=$1
    local category=$2
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    local var_name="config_modules_conda_environments_${env_name}_packages_${category}[@]"
    echo "${!var_name}"
}

remove_conda() {
    log "INFO" "Removing Conda configuration..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Restore original condarc from backup
    restore_backup "$HOME/.condarc"
    
    # Remove shell initialization
    local shells=("bash" "zsh")
    for shell in "${shells[@]}"; do
        local rc_file="$HOME/.${shell}rc"
        if [ -f "$rc_file" ]; then
            sed -i '/^# >>> conda initialize/,/^# <<< conda initialize/d' "$rc_file"
        fi
    done
    
    log "INFO" "Conda configuration removed"
    log "INFO" "Use 'rm -rf ${config_modules_conda_paths_root}' to remove Conda installation if desired"
    return 0
}

verify_conda() {
    log "INFO" "Verifying Conda installation..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    local verification_failed=false
    
    # Check conda installation
    if [ ! -f "${config_modules_conda_paths_root}/bin/conda" ]; then
        log "ERROR" "Conda not installed"
        verification_failed=true
    fi
    
    # Check conda configuration
    if [ ! -f "$HOME/.condarc" ]; then
        log "ERROR" "Conda configuration not found"
        verification_failed=true
    fi
    
    # Verify environments and packages
    if [ -f "${config_modules_conda_paths_root}/bin/conda" ]; then
        source "${config_modules_conda_paths_root}/etc/profile.d/conda.sh"
        for env_name in $(get_environment_names); do
            if ! conda env list | grep -q "^${env_name} "; then
                log "ERROR" "Environment not found: $env_name"
                verification_failed=true
                continue
            fi
            
            # Check packages in each category
            conda activate "$env_name"
            for category in $(get_environment_categories "$env_name"); do
                local packages=($(get_environment_packages "$env_name" "$category"))
                for package in "${packages[@]}"; do
                    if ! conda list | grep -q "^${package%%=*} "; then
                        log "ERROR" "Package not found in $env_name: $package"
                        verification_failed=true
                    fi
                done
            done
            conda deactivate
        done
    fi
    
    # Check development directories
    for dir in "${config_modules_conda_paths_packages}" "${config_modules_conda_paths_pkg_build}" "${config_modules_conda_paths_pkg_dist}"; do
        if [ ! -d "$dir" ]; then
            log "ERROR" "Development directory not found: $dir"
            verification_failed=true
        fi
    done
    
    # Verify shell initialization
    local shells=("bash" "zsh")
    for shell in "${shells[@]}"; do
        local rc_file="$HOME/.${shell}rc"
        if [ -f "$rc_file" ] && ! grep -q "conda initialize" "$rc_file"; then
            log "ERROR" "Conda initialization not found in $rc_file"
            verification_failed=true
        fi
    done
    
    [ "$verification_failed" = true ] && return 1
    
    log "INFO" "Conda verification complete"
    return 0
}

update_conda() {
    log "INFO" "Updating Conda environment..."
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    if [ -f "${config_modules_conda_paths_root}/bin/conda" ]; then
        source "${config_modules_conda_paths_root}/etc/profile.d/conda.sh"
        
        # Update base conda
        conda update -n base -c defaults conda -y
        
        # Update each environment
        for env_name in $(get_environment_names); do
            if conda env list | grep -q "^${env_name} "; then
                log "INFO" "Updating $env_name environment..."
                conda activate "$env_name"
                conda update --all -y
                conda deactivate
            fi
        done
        
        # Reconfigure with latest settings
        configure_conda
        return 0
    else
        log "ERROR" "Conda not installed"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        log "ERROR" "Usage: $0 {grovel|install|remove|verify|update}"
        exit 1
    fi
    module_base "$1" "conda"
fi