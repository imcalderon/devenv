#!/bin/bash
# lib/logging.sh - Logging utility

# Get script directory even when sourced
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get global paths from config
get_log_path() {
    # Default log directory if config not found or parsing fails
    local default_log_dir="$HOME/.devenv/logs"
    local log_dir=""
    
    # Only try to parse config if yaml_parser is available and config exists
    local config_file="${CURRENT_DIR}/../config.yaml"
    if [ -f "$CURRENT_DIR/yaml_parser.sh" ] && [ -f "$config_file" ]; then
        source "$CURRENT_DIR/yaml_parser.sh"
        # Parse YAML and get log directory
        local config_paths=$(parse_yaml "$config_file" | grep "^config_modules__paths_logs=")
        if [ -n "$config_paths" ]; then
            log_dir=$(echo "$config_paths" | cut -d'"' -f2)
            # Expand any environment variables
            log_dir=$(eval echo "$log_dir")
        fi
    fi
    
    # Use default if log_dir is empty
    if [ -z "$log_dir" ]; then
        log_dir="$default_log_dir"
    fi
    
    echo "$log_dir"
}

# Initialize logging
init_logging() {
    local log_dir
    log_dir=$(get_log_path)
    
    # Ensure log_dir is not empty
    if [ -z "$log_dir" ]; then
        log_dir="$HOME/.devenv/logs"
    fi
    
    # Export for use by other functions
    export LOG_DIR="$log_dir"
    export LOG_FILE="${log_dir}/devenv_$(date +%Y%m%d).log"
    export LOG_LEVEL=${LOG_LEVEL:-"INFO"}
    
    # Create log directory if it doesn't exist
    mkdir -p "$log_dir" || { echo "ERROR: Failed to create log directory: $log_dir" >&2; return 1; }
    
    # Create symlink to latest log
    ln -sf "$LOG_FILE" "${log_dir}/latest.log"
}

# Initialize logging when the script is sourced
init_logging || { echo "ERROR: Logging initialization failed" >&2; exit 1; }

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure LOG_FILE is set
    if [ -z "${LOG_FILE}" ]; then
        echo "ERROR: LOG_FILE is not set" >&2
        return 1
    fi
    
    # Create log directory if it disappeared
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    
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

# Function to rotate logs
rotate_logs() {
    local max_days=${1:-30}  # Default to 30 days retention
    
    if [ -z "${LOG_DIR}" ]; then
        echo "ERROR: LOG_DIR is not set" >&2
        return 1
    fi
    
    find "$LOG_DIR" -name "devenv_*.log" -type f -mtime +$max_days -delete
    
    # Compress logs older than 7 days but younger than max_days
    find "$LOG_DIR" -name "devenv_*.log" -type f -mtime +7 -mtime -$max_days -exec gzip {} \;
}

# Function to get current log file path
get_current_log() {
    echo "${LOG_FILE}"
}

# If script is run directly, show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Usage: source $(basename $0)"
    echo "This script provides logging functions and should be sourced, not executed directly."
    exit 1
fi