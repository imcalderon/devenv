#!/bin/bash

# Common variables and functions used across scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yml"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Load YAML config
load_config() {
    if ! command -v yq &> /dev/null; then
        sudo dnf install -y yq
    fi
    eval "$(yq eval 'to_entries | .[] | "export " + .key + "=\"" + .value + "\""' "$CONFIG_FILE")"
}

log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOG_FILE}"
}

run_script() {
    local script=$1
    shift
    log "INFO" "Running ${script}..."
    if [ -x "${SCRIPT_DIR}/${script}" ]; then
        "${SCRIPT_DIR}/${script}" "$@"
    else
        log "ERROR" "Script ${script} not found or not executable"
        return 1
    fi
}

check_requirements() {
    local min_bash_version="4.0"
    if ((${BASH_VERSION%%.*} < ${min_bash_version%%.*})); then
        log "ERROR" "Requires Bash version $min_bash_version or higher"
        exit 1
    fi

    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "ERROR" "No network connectivity"
        exit 1
    fi
}
