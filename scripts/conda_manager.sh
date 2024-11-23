#!/bin/bash
# scripts/conda_manager.sh - Conda environment and package cache management

source "$(dirname "$0")/lib/common.sh"

setup_conda() {
    load_config
    log "INFO" "Setting up Conda environment..."

    # Download and install Miniconda if not present
    if ! command -v conda &>/dev/null; then
        log "INFO" "Installing Miniconda..."
        local miniconda_script="Miniconda3-latest-Linux-x86_64.sh"
        local miniconda_url="https://repo.anaconda.com/miniconda/${miniconda_script}"
        
        # Download to cache if not present
        if [ ! -f "${package_cache}/${miniconda_script}" ]; then
            mkdir -p "${package_cache}"
            curl -Lo "${package_cache}/${miniconda_script}" "${miniconda_url}"
        fi

        bash "${package_cache}/${miniconda_script}" -b -p "${conda_dir}"
        
        # Initialize conda for shell integration
        "${conda_dir}/bin/conda" init bash
        "${conda_dir}/bin/conda" init zsh
    fi

    # Configure conda
    configure_conda
    setup_package_cache
    create_environments
}

configure_conda() {
    log "INFO" "Configuring Conda..."
    
    # Configure conda settings
    conda config --set auto_activate_base false
    conda config --set channel_priority strict
    
    # Add channels
    for channel in "${python[conda][channels]}"; do
        conda config --add channels "$channel"
    done
    
    # Setup local package cache
    conda config --add pkgs_dirs "${package_cache}/conda"
    
    # Create .condarc with advanced settings
    cat > "${HOME}/.condarc" << EOF
channels:
  - conda-forge
  - defaults

# Cache directory configuration
pkgs_dirs:
  - ${package_cache}/conda

# Performance optimization
solver: libmamba
verify_threads: ${CPU_COUNT}
default_threads: ${CPU_COUNT}
repodata_threads: ${CPU_COUNT}

# Network settings
remote_connect_timeout_secs: 30.0
remote_read_timeout_secs: 120.0
remote_max_retries: 3

# Storage management
clean_index_cache: false
auto_stack: 1

# Advanced configuration
rollback_enabled: true
allow_conda_downgrades: false
notify_outdated_conda: true
EOF
}

setup_package_cache() {
    log "INFO" "Setting up package cache..."
    
    local cache_dirs=(
        "${package_cache}/conda"
        "${package_cache}/pip"
        "${local_repo}/conda"
        "${local_repo}/pip"
    )
    
    # Create cache directories
    for dir in "${cache_dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Configure pip to use local cache
    cat > "${HOME}/.config/pip/pip.conf" << EOF
[global]
cache-dir = ${package_cache}/pip
index-url = ${python[pip][index_url]}
trusted-host = 
    ${python[pip][trusted_hosts]}

[search]
index = ${local_repo}/pip
EOF

    # Setup local package repository
    setup_local_repo
}

setup_local_repo() {
    log "INFO" "Setting up local package repository..."
    
    # Create directory structure for local repo
    mkdir -p "${local_repo}/{conda,pip}/packages"
    
    # Download and cache conda packages
    for package in "${python[conda][cached_packages]}"; do
        if ! [ -f "${local_repo}/conda/packages/${package}*.tar.bz2" ]; then
            log "INFO" "Caching conda package: ${package}"
            conda download --dest "${local_repo}/conda/packages" "$package"
        fi
    done
    
    # Download and cache pip packages
    for package in "${python[pip][cached_packages]}"; do
        log "INFO" "Caching pip package: ${package}"
        pip download --dest "${local_repo}/pip/packages" "$package"
    done
    
    # Index the local repository
    create_repo_index
}

create_repo_index() {
    log "INFO" "Creating repository indexes..."
    
    # Create conda repository index
    conda index "${local_repo}/conda/packages"
    
    # Create pip repository index
    pushd "${local_repo}/pip/packages" > /dev/null
    for f in *.whl *.tar.gz; do
        [ -e "$f" ] || continue
        echo "$(basename $f)" >> "../simple/index.html"
    done
    popd > /dev/null
}

create_environments() {
    log "INFO" "Creating Conda environments..."
    
    # Create each environment from config
    for env_name in "${!python[conda][environments]}"; do
        log "INFO" "Creating environment: ${env_name}"
        
        # Create environment if it doesn't exist
        if ! conda env list | grep -q "^${env_name} "; then
            conda create -y -n "$env_name" python="${python[version]}"
            
            # Install packages for this environment
            conda activate "$env_name"
            for package in "${python[conda][environments[$env_name][packages]}"; do
                conda install -y "$package"
            done
            conda deactivate
        fi
    done
}

maintain_cache() {
    log "INFO" "Maintaining package cache..."
    
    # Clean old packages based on retention policy
    find "${package_cache}" -type f -mtime "+${package_cache[retention_days]}" -delete
    
    # Check cache size and clean if necessary
    local cache_size=$(du -s -BG "${package_cache}" | cut -f1 | tr -d 'G')
    if (( cache_size > package_cache[max_size_gb] )); then
        log "WARN" "Cache size (${cache_size}G) exceeds limit (${package_cache[max_size_gb]}G), cleaning..."
        conda clean -a -y
        pip cache purge
    fi
    
    # Compress cache if enabled
    if [ "${package_cache[compression]}" = true ]; then
        find "${package_cache}" -type f -name "*.whl" -o -name "*.tar.gz" | while read file; do
            if ! [ -f "${file}.gz" ]; then
                gzip -k "$file"
            fi
        done
    fi
}

case "${1:-setup}" in
    "setup")
        setup_conda
        ;;
    "clean")
        maintain_cache
        ;;
    "update-index")
        create_repo_index
        ;;
    "update-cache")
        setup_local_repo
        ;;
    *)
        echo "Usage: $0 {setup|clean|update-index|update-cache}"
        exit 1
        ;;
esac
