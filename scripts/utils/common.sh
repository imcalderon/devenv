# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log levels
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required tools
check_requirements() {
    local missing=0
    
    # Required tools
    local tools=("node" "npm" "git")
    
    # Optional tools
    local opt_tools=("conda" "docker" "code")
    
    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            log_error "$tool is required but not installed."
            missing=1
        fi
    done
    
    for tool in "${opt_tools[@]}"; do
        if ! command_exists "$tool"; then
            log_warn "$tool is recommended but not installed."
        fi
    done
    
    return $missing
}

# Update development tools
update_tools() {
    log_info "Updating development tools..."
    
    # Update npm and global packages
    if command_exists npm; then
        npm install -g npm@latest
        npm update -g
    fi
    
    # Update conda if available
    if command_exists conda; then
        conda update -n base -c defaults conda -y
    fi
}

# Setup VSCode workspace
setup_vscode_workspace() {
    local project_dir="$1"
    
    if [ ! -d "$project_dir" ]; then
        log_error "Project directory does not exist: $project_dir"
        return 1
    fi
    
    if ! command_exists code; then
        log_warn "VSCode not found. Skipping workspace setup."
        return 0
    fi
    
    # Create VSCode workspace settings
    mkdir -p "$project_dir/.vscode"
    
    # Create settings.json
    cat > "$project_dir/.vscode/settings.json" << EOF
{
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
        "source.fixAll.eslint": true
    },
    "files.exclude": {
        "**/.git": true,
        "**/node_modules": true,
        "**/dist": true
    }
}
EOF

    # Create launch.json for debugging
    cat > "$project_dir/.vscode/launch.json" << EOF
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "chrome",
            "request": "launch",
            "name": "Launch Chrome against localhost",
            "url": "http://localhost:8080",
            "webRoot": "\${workspaceFolder}/src"
        }
    ]
}
EOF

    log_info "VSCode workspace configured successfully"
}

# Setup Docker development environment
setup_docker_dev() {
    local project_dir="$1"
    
    if [ ! -d "$project_dir" ]; then
        log_error "Project directory does not exist: $project_dir"
        return 1
    fi
    
    if ! command_exists docker; then
        log_warn "Docker not found. Skipping environment setup."
        return 0
    fi
    
    # Create development Dockerfile
    cat > "$project_dir/Dockerfile.dev" << EOF
FROM node:16-slim

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .

EXPOSE 8080
CMD ["npm", "run", "dev"]
EOF
    
    log_info "Docker development environment configured successfully"
}

# Create Conda development environment
setup_conda_env() {
    local project_dir="$1"
    local env_name="$2"
    
    if [ ! -d "$project_dir" ]; then
        log_error "Project directory does not exist: $project_dir"
        return 1
    fi
    
    if ! command_exists conda; then
        log_warn "Conda not found. Skipping environment setup."
        return 0
    fi
    
    # Create conda environment
    conda create -n "$env_name" python=3.10 nodejs -y
    
    # Create environment.yml
    cat > "$project_dir/environment.yml" << EOF
name: $env_name
channels:
  - defaults
  - conda-forge
dependencies:
  - python=3.10
  - nodejs>=16
  - pip
  - pip:
    - pytest
    - black
    - flake8
EOF
    
    log_info "Conda environment configured successfully"
}

# Export project version and metadata
get_project_metadata() {
    local project_dir="$1"
    
    if [ ! -d "$project_dir" ]; then
        log_error "Project directory does not exist: $project_dir"
        return 1
    fi
    
    if [ ! -f "$project_dir/package.json" ]; then
        log_error "package.json not found"
        return 1
    }
    
    local version=$(node -p "require('./package.json').version")
    echo "$version"
}

# Main function for utility commands
main() {
    local command="$1"
    shift
    
    case "$command" in
        "check")
            check_requirements
            ;;
        "update")
            update_tools
            ;;
        "setup-vscode")
            setup_vscode_workspace "$1"
            ;;
        "setup-docker")
            setup_docker_dev "$1"
            ;;
        "setup-conda")
            setup_conda_env "$1" "$2"
            ;;
        "version")
            get_project_metadata "$1"
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Available commands: check, update, setup-vscode, setup-docker, setup-conda, version"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi