#!/bin/bash
# lib/logging.sh - Logging utility

LOG_FILE="${SCRIPT_DIR:-$(pwd)}/setup.log"
LOG_LEVEL=${LOG_LEVEL:-"INFO"}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Log to console with colors
    case $level in
        "ERROR")
            echo -e "\e[31m[$level] $message\e[0m" >&2
            ;;
        "WARN")
            echo -e "\e[33m[$level] $message\e[0m"
            ;;
        "INFO")
            echo -e "\e[32m[$level] $message\e[0m"
            ;;
        "DEBUG")
            [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "\e[36m[$level] $message\e[0m"
            ;;
        *)
            echo "[$level] $message"
            ;;
    esac
}