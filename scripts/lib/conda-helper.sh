#!/bin/bash
# scripts/lib/conda-helper.sh - Conda environment management utilities

source "$(dirname "$0")/common.sh"

export_environment() {
    local env_name=$1
    local output_dir="${HOME}/Development/environments"
    mkdir -p "$output_dir"
    
    # Export conda environment
    conda env export -n "$env_name" > "${output_dir}/${env_name}-environment.yml"
    
    # Export pip requirements
    conda activate "$env_name"
    pip freeze > "${output_dir}/${env_name}-requirements.txt"
    conda deactivate
}

clone_environment() {
    local source_env=$1
    local target_env=$2
    
    conda create -y -n "$target_env" --clone "$source_env"
}

create_kernel() {
    local env_name=$1
    
    conda activate "$env_name"
    python -m ipykernel install --user --name "$env_name" --display-name "Python ($env_name)"
    conda deactivate
}

clean_environment() {
    local env_name=$1
    
    conda activate "$env_name"
    conda clean -a -y
    pip cache purge
    conda deactivate
}

check_environment() {
    local env_name=$1
    local issues=0
    
    # Check if environment exists
    if ! conda env list | grep -q "^${env_name} "; then
        log "ERROR" "Environment ${env_name} does not exist"
        return 1
    fi
    
    # Check packages
    conda activate "$env_name"
    
    # Verify conda packages
    if ! conda list | grep -q "python ${python[version]}"; then
        log "ERROR" "Python version mismatch in ${env_name}"
        ((issues++))
    fi
    
    # Check pip packages
    if ! pip list &>/dev/null; then
        log "ERROR" "Pip installation issues in ${env_name}"
        ((issues++))
    fi
    
    # Check Jupyter kernel if applicable
    if conda list | grep -q "ipykernel"; then
        if ! jupyter kernelspec list | grep -q "$env_name"; then
            log "ERROR" "Jupyter kernel missing for ${env_name}"
            ((issues++))
        fi
    fi
    
    conda deactivate
    
    return $issues
}

case "${1:-help}" in
    "export")
        [ -z "$2" ] && { echo "Usage: $0 export <env_name>"; exit 1; }
        export_environment "$2"
        ;;
    "clone")
        [ -z "$3" ] && { echo "Usage: $0 clone <source_env> <target_env>"; exit 1; }
        clone_environment "$2" "$3"
        ;;
    "kernel")
        [ -z "$2" ] && { echo "Usage: $0 kernel <env_name>"; exit 1; }
        create_kernel "$2"
        ;;
    "clean")
        [ -z "$2" ] && { echo "Usage: $0 clean <env_name>"; exit 1; }
        clean_environment "$2"
        ;;
    "check")
        [ -z "$2" ] && { echo "Usage: $0 check <env_name>"; exit 1; }
        check_environment "$2"
        ;;
    "help"|*)
        echo "Usage: $0 {export|clone|kernel|clean|check} <env_name> [target_env]"
        exit 1
        ;;
esac
