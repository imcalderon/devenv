#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

check_health() {
    local component=$1
    local check_cmd=$2
    
    if eval "${check_cmd}" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_system_health() {
    local issues=0
    
    # Check core development tools
    for tool in git curl wget unzip htop vim nano make gcc "gcc-c++"; do
        if ! check_health "${tool}" "rpm -q ${tool}"; then
            log "WARN" "${tool} is not properly installed"
            ((issues++))
        fi
    done
    
    # Additional health checks
    if ! check_health "VS Code" "which code"; then
        log "WARN" "VS Code is not properly installed"
        ((issues++))
    fi
    
    if ! check_health "Docker" "systemctl is-active docker"; then
        log "WARN" "Docker service is not running"
        ((issues++))
    fi
    
    if ! check_health "pip3" "which pip3"; then
        log "WARN" "Python pip3 is not properly installed"
        ((issues++))
    fi
    
    if [ ! -d "$HOME/.nvm" ]; then
        log "WARN" "NVM is not installed"
        ((issues++))
    fi
    
    for dir in projects scripts docker; do
        if [ ! -d "$HOME/Development/${dir}" ]; then
            log "WARN" "Development directory missing: ${dir}"
            ((issues++))
        fi
    done
    
    return $issues
}

heal_component() {
    local component=$1
    local check_cmd=$2
    local install_cmd=$3
    local status=0
    
    log "INFO" "Checking ${component}..."
    if ! eval "${check_cmd}" > /dev/null 2>&1; then
        log "WARN" "${component} is missing or broken, fixing..."
        if eval "${install_cmd}"; then
            log "INFO" "${component} has been fixed"
        else
            log "ERROR" "Failed to fix ${component}"
            status=1
        fi
    else
        log "INFO" "${component} is properly installed"
    fi
    return $status
}