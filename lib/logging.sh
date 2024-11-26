#!/bin/bash
# lib/logging.sh - Logging utilities

# Default configurations
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_LOG_DIR="$HOME/.devenv/logs"

# Initialize logging
init_logging() {
    # Get log directory from module config if available
    local module_name=${1:-}
    local log_dir="$DEFAULT_LOG_DIR"
    
    if [[ -n "$module_name" && -f "$MODULES_DIR/$module_name/config.json" ]]; then
        log_dir=$(get_json_value "$MODULES_DIR/$module_name/config.json" '.logging.dir' "$DEFAULT_LOG_DIR")
    fi
    
    # Create log directory
    mkdir -p "$log_dir" || {
        echo "ERROR: Failed to create log directory: $log_dir" >&2
        return 1
    }
    
    # Set up log file with module prefix if applicable
    local prefix=${module_name:+${module_name}_}
    export LOG_FILE="${log_dir}/devenv_${prefix}$(date +%Y%m%d).log"
    export LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    
    # Create symlink to latest log
    ln -sf "$LOG_FILE" "${log_dir}/${prefix}latest.log"
}

# Logging function with severity levels and colors
log() {
    local level=$1
    local message=$2
    local module=${3:-}
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure LOG_FILE is set
    if [[ -z "${LOG_FILE}" ]]; then
        echo "ERROR: LOG_FILE is not set" >&2
        return 1
    fi
    
    # Format message with optional module prefix
    local log_message="[$timestamp] [$level]${module:+ [$module]} $message"
    
    # Write to log file
    echo "$log_message" >> "$LOG_FILE"
    
    # Console output with colors
    case $level in
        "ERROR")
            echo -e "\e[31m[$level]${module:+ [$module]} $message\e[0m" >&2
            ;;
        "WARN")
            echo -e "\e[33m[$level]${module:+ [$module]} $message\e[0m"
            ;;
        "INFO")
            echo -e "\e[32m[$level]${module:+ [$module]} $message\e[0m"
            ;;
        "DEBUG")
            [[ "$LOG_LEVEL" == "DEBUG" ]] && echo -e "\e[36m[$level]${module:+ [$module]} $message\e[0m"
            ;;
        *)
            echo "[$level]${module:+ [$module]} $message"
            ;;
    esac
}

# Initialize logging on source
init_logging || {
    echo "ERROR: Failed to initialize logging" >&2
    return 1
}
