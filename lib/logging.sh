# File: lib/logging.sh
#!/bin/bash

# Logging configuration and functions
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$HOME/.devenv/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/devenv_${TIMESTAMP}.log"

log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "${LOG_FILE}"
}

error_handler() {
    local line_no=$1
    local error_code=$2
    log "ERROR" "Error occurred in script at line: ${line_no}"
    log "ERROR" "Exit code: ${error_code}"
    exit "${error_code}"
}