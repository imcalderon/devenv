#!/bin/bash
# scripts/generate_phaser_game.sh - Creates a new Phaser game project

set -euo pipefail

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates/phaser"

# Load common utilities if available
if [ -f "$SCRIPT_DIR/utils/common.sh" ]; then
    source "$SCRIPT_DIR/utils/common.sh"
fi

# Default values
DEFAULT_GAME_NAME="phaser-game"
DEFAULT_GAME_TITLE="My Phaser Game"
DEFAULT_DESCRIPTION="A game built with Phaser 3"
DEFAULT_AUTHOR="$(git config --get user.name)"
DEFAULT_EMAIL="$(git config --get user.email)"

# Display help
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <game-name>

Creates a new Phaser game project with Node.js, Conda, and Docker configuration.

Options:
    -h, --help              Show this help message
    -t, --title            Game title (default: "My Phaser Game")
    -d, --description      Game description
    -a, --author           Author name
    -e, --email            Author email
    -f, --force            Override existing directory
    --no-git              Skip git initialization
    --no-conda            Skip conda environment setup
    --no-docker           Skip Docker configuration

Example:
    $(basename "$0") my-awesome-game -t "My Awesome Game" -d "A platformer game"
EOF
}

# Parse arguments
parse_args() {
    GAME_NAME="$DEFAULT_GAME_NAME"
    GAME_TITLE="$DEFAULT_GAME_TITLE"
    DESCRIPTION="$DEFAULT_DESCRIPTION"
    AUTHOR="$DEFAULT_AUTHOR"
    EMAIL="$DEFAULT_EMAIL"
    FORCE=0
    SETUP_GIT=1
    SETUP_CONDA=1
    SETUP_DOCKER=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--title)
                GAME_TITLE="$2"
                shift 2
                ;;
            -d|--description)
                DESCRIPTION="$2"
                shift 2
                ;;
            -a|--author)
                AUTHOR="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=1
                shift
                ;;
            --no-git)
                SETUP_GIT=0
                shift
                ;;
            --no-conda)
                SETUP_CONDA=0
                shift
                ;;
            --no-docker)
                SETUP_DOCKER=0
                shift
                ;;
            *)
                GAME_NAME="$1"
                shift
                ;;
        esac
    done
}

# Validate project name
validate_project_name() {
    if [[ ! "$GAME_NAME" =~ ^[a-zA-Z][-a-zA-Z0-9]+$ ]]; then
        echo "Error: Invalid project name. Use only letters, numbers, and hyphens, starting with a letter."
        exit 1
    fi

    if [ -d "$GAME_NAME" ] && [ "$FORCE" -eq 0 ]; then
        echo "Error: Directory $GAME_NAME already exists. Use --force to override."
        exit 1
    fi
}

# Create project structure
create_project_structure() {
    echo "Creating project structure..."
    
    mkdir -p "$GAME_NAME"/{src/{assets/{images,audio,maps},scripts/{states,entities,utils},css},tests,docs}

    # Create base files from templates
    for template in "$TEMPLATES_DIR"/*; do
        if [ -f "$template" ]; then
            filename="$(basename "$template")"
            sed -e "s|{{GAME_NAME}}|$GAME_NAME|g" \
                -e "s|{{GAME_TITLE}}|$GAME_TITLE|g" \
                -e "s|{{DESCRIPTION}}|$DESCRIPTION|g" \
                -e "s|{{AUTHOR}}|$AUTHOR|g" \
                -e "s|{{EMAIL}}|$EMAIL|g" \
                -e "s|{{YEAR}}|$(date +%Y)|g" \
                "$template" > "$GAME_NAME/$filename"
    done
}

# Setup Node.js configuration
setup_node() {
    echo "Setting up Node.js configuration..."
    
    cd "$GAME_NAME" || exit 1
    
    # Initialize npm
    npm init -y

    # Install dependencies
    npm install --save phaser
    npm install --save-dev \
        @babel/core @babel/preset-env \
        babel-loader \
        webpack webpack-cli webpack-dev-server \
        jest jest-environment-jsdom \
        eslint eslint-config-prettier prettier \
        copy-webpack-plugin html-webpack-plugin \
        css-loader style-loader \
        source-map-loader
}

# Setup Conda environment
setup_conda() {
    if [ "$SETUP_CONDA" -eq 1 ]; then
        echo "Setting up Conda environment..."
        
        cd "$GAME_NAME" || exit 1
        
        # Create conda environment
        conda create -y -n "$GAME_NAME" python=3.10
        
        # Create environment.yml
        cat > environment.yml << EOF
name: $GAME_NAME
channels:
  - defaults
  - conda-forge
dependencies:
  - python=3.10
  - pip
  - nodejs
  - pip:
    - pytest
    - black
    - flake8
EOF
    fi
}

# Setup Docker configuration
setup_docker() {
    if [ "$SETUP_DOCKER" -eq 1 ]; then
        echo "Setting up Docker configuration..."
        
        cd "$GAME_NAME" || exit 1
        
        # Create Dockerfile
        cat > Dockerfile << EOF
FROM node:16-slim as builder

WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

        # Create docker-compose.yml
        cat > docker-compose.yml << EOF
version: '3.8'
services:
  dev:
    build: 
      context: .
      target: builder
    ports:
      - "8080:8080"
    volumes:
      - .:/app
      - /app/node_modules
    command: npm run dev
    
  prod:
    build: .
    ports:
      - "80:80"
EOF

        # Create .dockerignore
        cat > .dockerignore << EOF
node_modules
dist
.git
.gitignore
.env
*.log
EOF
    fi
}

# Setup Git repository
setup_git() {
    if [ "$SETUP_GIT" -eq 1 ]; then
        echo "Initializing Git repository..."
        
        cd "$GAME_NAME" || exit 1
        
        git init
        git add .
        git commit -m "Initial commit"
    fi
}

# Main execution
main() {
    echo "Generating Phaser game project: $GAME_NAME"
    
    validate_project_name
    create_project_structure
    setup_node
    setup_conda
    setup_docker
    setup_git
    
    echo "Project successfully created at ./$GAME_NAME"
    echo "To get started:"
    echo "  cd $GAME_NAME"
    echo "  npm install"
    echo "  npm run dev"
}

# Execute
parse_args "$@"
main