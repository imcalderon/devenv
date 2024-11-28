#!/bin/bash
# scripts/build.sh - Coordinate build processes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/common.sh"

# Build modes
BUILD_MODES=(
    "development"
    "production"
    "test"
)

# Default settings
DEFAULT_MODE="development"
DEFAULT_PORT=8080

# Parse command line arguments
parse_args() {
    MODE="$DEFAULT_MODE"
    PORT="$DEFAULT_PORT"
    DOCKER=0
    WATCH=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode=*)
                MODE="${1#*=}"
                ;;
            --port=*)
                PORT="${1#*=}"
                ;;
            --docker)
                DOCKER=1
                ;;
            --watch)
                WATCH=1
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# Show help message
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build and run the game project.

Options:
    --mode=MODE     Build mode: development, production, test (default: development)
    --port=PORT     Port to run dev server on (default: 8080)
    --docker        Build using Docker
    --watch         Watch for changes
    -h, --help      Show this help message

Examples:
    $(basename "$0") --mode=production
    $(basename "$0") --mode=development --port=3000 --watch
    $(basename "$0") --mode=production --docker
EOF
}

# Build project
build_project() {
    local mode="$1"
    local docker="$2"
    
    if [ "$docker" -eq 1 ]; then
        log_info "Building with Docker in $mode mode..."
        docker-compose build
    else
        log_info "Building in $mode mode..."
        npm run "build:$mode"
    fi
}

# Run development server
run_dev_server() {
    local port="$1"
    local docker="$2"
    local watch="$3"
    
    if [ "$docker" -eq 1 ]; then
        log_info "Starting Docker development server on port $port..."
        docker-compose up
    else
        if [ "$watch" -eq 1 ]; then
            log_info "Starting development server with watch mode on port $port..."
            npm run "dev" -- --port "$port"
        else
            log_info "Starting development server on port $port..."
            npm run "serve" -- --port "$port"
        fi
    fi
}

# Run tests
run_tests() {
    log_info "Running tests..."
    npm run test
}

# Main execution
main() {
    parse_args "$@"
    
    # Validate mode
    if [[ ! " ${BUILD_MODES[@]} " =~ " ${MODE} " ]]; then
        log_error "Invalid mode: $MODE"
        show_help
        exit 1
    }
    
    # Execute based on mode
    case "$MODE" in
        "development")
            build_project "$MODE" "$DOCKER"
            run_dev_server "$PORT" "$DOCKER" "$WATCH"
            ;;
        "production")
            build_project "$MODE" "$DOCKER"
            ;;
        "test")
            run_tests
            ;;
    esac
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi