#!/bin/bash
# scripts/conda.sh - Comprehensive Conda management system

source "$(dirname "$0")/../lib/common.sh"

CONDA_CONFIG_FILE="${SCRIPT_DIR}/conda_config.yml"
CONDA_LOCK_FILE="/tmp/conda_manager.lock"

# Ensure only one instance runs at a time
[[ -f $CONDA_LOCK_FILE ]] && { echo "Another conda operation in progress"; exit 1; }
trap "rm -f $CONDA_LOCK_FILE" EXIT
touch $CONDA_LOCK_FILE

setup_conda_base() {
    load_config "$CONDA_CONFIG_FILE"
    log "INFO" "Setting up base Conda installation..."

    if ! command -v conda &>/dev/null; then
        local miniconda_script="Miniconda3-latest-Linux-x86_64.sh"
        local miniconda_url="https://repo.anaconda.com/miniconda/${miniconda_script}"
        
        # Download to cache if not present
        if [ ! -f "${package_cache}/${miniconda_script}" ]; then
            mkdir -p "${package_cache}"
            curl -Lo "${package_cache}/${miniconda_script}" "${miniconda_url}"
        fi

        bash "${package_cache}/${miniconda_script}" -b -p "${conda_base}"
        
        # Initialize shell integration
        "${conda_base}/bin/conda" init bash
        "${conda_base}/bin/conda" init zsh
    fi

    # Install mamba for faster solving
    conda install -n base -c conda-forge mamba -y
}

configure_conda() {
    log "INFO" "Configuring Conda installation..."
    
    # Configure conda settings
    cat > "${HOME}/.condarc" << EOF
channels:
$(for channel in "${conda[channels]}"; do echo "  - $channel"; done)

# Cache and repository configuration
pkgs_dirs:
  - ${package_cache}
default_threads: ${CPU_COUNT}
repodata_threads: ${CPU_COUNT}

# Performance optimization
solver: libmamba
auto_update_conda: false
channel_priority: strict
pip_interop_enabled: true

# Network settings
remote_connect_timeout_secs: 30.0
remote_read_timeout_secs: 120.0
remote_max_retries: 3

# Advanced configuration
rollback_enabled: true
env_prompt: ({name})
EOF

    # Setup local repository structure
    mkdir -p "${local_repo}"/{noarch,linux-64}
    conda index "${local_repo}"
}

create_environment() {
    local env_name=$1
    local env_config="${conda[environments[$env_name]]}"
    
    log "INFO" "Creating environment: $env_name"
    
    # Create environment file
    local env_file="${env_configs}/${env_name}.yml"
    mkdir -p "$(dirname "$env_file")"
    
    # Generate environment YAML
    cat > "$env_file" << EOF
name: $env_name
channels:
$(for channel in "${env_config[channels]}"; do echo "  - $channel"; done)
dependencies:
$(for pkg in "${env_config[packages]}"; do echo "  - $pkg"; done)
EOF

    # Create environment using mamba for speed
    mamba env create -f "$env_file" -n "$env_name"
    
    # Set environment variables
    local env_vars_file="${conda_base}/envs/${env_name}/etc/conda/activate.d/env_vars.sh"
    mkdir -p "$(dirname "$env_vars_file")"
    
    # Write environment variables
    for var in "${!env_config[env_vars]}"; do
        echo "export $var=${env_config[env_vars[$var]]}" >> "$env_vars_file"
    done
}

manage_cache() {
    log "INFO" "Managing package cache..."
    
    # Clean old packages
    find "${package_cache}" -type f -mtime "+${package_cache[retention_days]}" -delete
    
    # Check cache size
    local cache_size=$(du -s -BG "${package_cache}" | cut -f1 | tr -d 'G')
    if (( cache_size > package_cache[max_size_gb] )); then
        log "WARN" "Cache size (${cache_size}G) exceeds limit (${package_cache[max_size_gb]}G)"
        mamba clean -a -y
    fi
    
    # Cleanup unused packages
    if [ "${package_cache[cleanup_policy][keep_latest]}" = true ]; then
        conda clean --tarballs --index-cache --packages --yes
    fi
}

sync_local_repo() {
    log "INFO" "Syncing local repository..."
    
    # Download packages for local repo
    for category in "${!conda[cached_packages]}"; do
        for package in "${conda[cached_packages[$category]]}"; do
            log "INFO" "Caching $package for $category"
            mamba download --cache-dir "${package_cache}" "$package"
        done
    done
    
    # Update repository index
    conda index "${local_repo}"
}

check_environment() {
    local env_name=$1
    local status=0
    
    log "INFO" "Checking environment: $env_name"
    
    # Verify environment exists
    if ! conda env list | grep -q "^${env_name} "; then
        log "ERROR" "Environment $env_name does not exist"
        return 1
    fi
    
    # Check packages
    local env_config="${conda[environments[$env_name]]}"
    conda activate "$env_name"
    
    # Verify each required package
    for package in "${env_config[packages]}"; do
        if ! conda list | grep -q "^${package%=*}"; then
            log "ERROR" "Package $package not found in $env_name"
            ((status++))
        fi
    done
    
    # Check environment variables
    for var in "${!env_config[env_vars]}"; do
        if [ -z "${!var}" ]; then
            log "ERROR" "Environment variable $var not set in $env_name"
            ((status++))
        fi
    done
    
    conda deactivate
    return $status
}

# Main command dispatcher
case "${1:-help}" in
    "setup")
        setup_conda_base
        configure_conda
        ;;
    "create-env")
        [ -z "$2" ] && { echo "Usage: $0 create-env <env_name>"; exit 1; }
        create_environment "$2"
        ;;
    "sync-repo")
        sync_local_repo
        ;;
    "clean-cache")
        manage_cache
        ;;
    "check-env")
        [ -z "$2" ] && { echo "Usage: $0 check-env <env_name>"; exit 1; }
        check_environment "$2"
        ;;
    "update-index")
        conda index "${local_repo}"
        ;;
    *)
        echo "Usage: $0 {setup|create-env|sync-repo|clean-cache|check-env|update-index}"
        exit 1
        ;;
esac
