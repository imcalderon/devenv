#!/bin/bash
# lib/docker/compose_generator.sh - Docker Compose template generator
# Use environment variables set by devenv.sh, with fallback if running standalone
if [ -z "${ROOT_DIR:-}" ]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SCRIPT_DIR="$ROOT_DIR/lib"
fi

# Source dependencies using SCRIPT_DIR
source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/yaml_parser.sh"
source "${SCRIPT_DIR}/module_base.sh"

generate_compose_template() {
    local template_name=$1
    local output_dir=${2:-"$PWD"}
    
    if [ -z "$template_name" ]; then
        log "ERROR" "Template name is required"
        print_available_templates
        return 1
    }
    
    if [ ! -d "$output_dir" ]; then
        log "INFO" "Creating output directory: $output_dir"
        mkdir -p "$output_dir"
    fi
    
    case "$template_name" in
        "web")
            generate_web_template "$output_dir"
            ;;
        "python")
            generate_python_template "$output_dir"
            ;;
        "database")
            generate_database_template "$output_dir"
            ;;
        "full-stack")
            generate_fullstack_template "$output_dir"
            ;;
        *)
            log "ERROR" "Unknown template: $template_name"
            print_available_templates
            return 1
            ;;
    esac
}

print_available_templates() {
    echo "Available templates:"
    echo "  - web: Basic web application with Nginx and optional PHP/Node.js"
    echo "  - python: Python development environment with optional databases"
    echo "  - database: Multi-database setup (PostgreSQL, MySQL, MongoDB)"
    echo "  - full-stack: Complete development stack with web, API, and database services"
}

generate_python_template() {
    local output_dir=$1
    log "INFO" "Generating Python development environment in $output_dir"
    eval $(parse_yaml "$ROOT_DIR/config.yaml" "config_")
    
    # Create docker-compose.yml
    cat > "$output_dir/docker-compose.yml" << EOF
# Python Development Environment
version: '3.8'

services:
  app:
    build: 
      context: .
      dockerfile: Dockerfile
      args:
        USER_ID: \${USER_ID:-1000}
        GROUP_ID: \${GROUP_ID:-1000}
    volumes:
      - .:/app
      - ~/.ssh:/home/developer/.ssh:ro
      - ~/.gitconfig:/home/developer/.gitconfig:ro
    working_dir: /app
    # Container resource limits from config
    mem_limit: ${config_modules_docker_container_defaults_resources_memory_limit}
    mem_reservation: ${config_modules_docker_container_defaults_resources_memory_limit}
    cpu_shares: ${config_modules_docker_container_defaults_resources_cpu_shares}
    environment:
      - PYTHONUNBUFFERED=1
      - PYTHONDONTWRITEBYTECODE=1
      - DEVELOPMENT=1
    # Add your environment variables here
    env_file:
      - .env
    ports:
      - "8000:8000"  # For web applications
      - "5678:5678"  # For debugger
    user: "\${USER_ID:-1000}:\${GROUP_ID:-1000}"
    command: python main.py

  # Optional services
  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  # Uncomment if you need a database
  # db:
  #   image: postgres:13-alpine
  #   environment:
  #     - POSTGRES_DB=myapp
  #     - POSTGRES_USER=postgres
  #     - POSTGRES_PASSWORD=postgres
  #   volumes:
  #     - postgres_data:/var/lib/postgresql/data
  #   ports:
  #     - "5432:5432"

volumes:
  redis_data:
  # postgres_data:
EOF

    # Create Dockerfile
    cat > "$output_dir/Dockerfile" << EOF
FROM python:3.11-slim

# Create non-root user
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g \${GROUP_ID} developer && \\
    useradd -m -u \${USER_ID} -g developer -s /bin/bash developer

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    build-essential \\
    curl \\
    git \\
    openssh-client \\
    && rm -rf /var/lib/apt/lists/*

# Create and set working directory
WORKDIR /app
RUN chown developer:developer /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY --chown=developer:developer . .

# Switch to non-root user
USER developer

# Run the application
CMD ["python", "main.py"]
EOF

    # Create requirements.txt
    cat > "$output_dir/requirements.txt" << EOF
# Core dependencies
pytest>=7.0.0
black>=22.0.0
flake8>=4.0.0
python-dotenv>=0.19.0
debugpy>=1.6.0  # For VS Code debugging

# Web framework (uncomment if needed)
# fastapi>=0.68.0
# uvicorn>=0.15.0

# Database (uncomment if needed)
# sqlalchemy>=1.4.0
# alembic>=1.7.0
# psycopg2-binary>=2.9.0

# Redis (uncomment if needed)
# redis>=4.0.0
EOF

    # Create .env file
    cat > "$output_dir/.env" << EOF
# Development environment variables
DEBUG=True
ENVIRONMENT=development

# Database configuration
DATABASE_URL=postgresql://postgres:postgres@db:5432/myapp
REDIS_URL=redis://redis:6379/0

# Application settings
APP_SECRET_KEY=your-secret-key-here
LOG_LEVEL=DEBUG
EOF

    # Create .dockerignore
    cat > "$output_dir/.dockerignore" << EOF
# Version control
.git
.gitignore
.gitattributes

# Python
*.pyc
__pycache__
*.pyo
*.pyd
.Python
*.py[cod]
*$py.class
.pytest_cache
.coverage
htmlcov/
.tox/
.nox/
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover

# Environment
.env
.venv
env/
venv/
ENV/

# IDE
.idea
.vscode
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db
EOF

    # Create .vscode/launch.json for debugging
    mkdir -p "$output_dir/.vscode"
    cat > "$output_dir/.vscode/launch.json" << EOF
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Python: Remote Attach",
            "type": "python",
            "request": "attach",
            "connect": {
                "host": "localhost",
                "port": 5678
            },
            "pathMappings": [
                {
                    "localRoot": "\${workspaceFolder}",
                    "remoteRoot": "/app"
                }
            ]
        }
    ]
}
EOF

    # Create simple main.py
    cat > "$output_dir/main.py" << EOF
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

def main():
    print(f"Environment: {os.getenv('ENVIRONMENT', 'development')}")
    print(f"Debug mode: {os.getenv('DEBUG', 'True')}")

if __name__ == "__main__":
    main()
EOF

    # Create Makefile with common commands
    cat > "$output_dir/Makefile" << EOF
.PHONY: build up down logs shell test lint format clean

# Docker Compose commands
build:
	docker compose build

up:
	docker compose up

down:
	docker compose down

logs:
	docker compose logs -f

shell:
	docker compose exec app bash

# Development commands
test:
	docker compose exec app pytest

lint:
	docker compose exec app flake8 .

format:
	docker compose exec app black .

# Cleanup commands
clean:
	docker compose down -v
	find . -type d -name "__pycache__" -exec rm -r {} +
	find . -type f -name "*.pyc" -delete
EOF

    log "INFO" "Generated Python development environment in $output_dir"
    print_usage_instructions "python" "$output_dir"
}

print_usage_instructions() {
    local template=$1
    local output_dir=$2
    
    echo ""
    echo "🐳 Docker Compose Template Generated!"
    echo "=====================================>"
    echo ""
    
    case "$template" in
        "python")
            cat << EOF
📁 Project Structure:
------------------
${output_dir}/
├── .dockerignore    - Docker build exclusions
├── .env            - Environment variables
├── .vscode/        - VS Code configuration
├── Dockerfile      - Container definition
├── Makefile        - Common commands
├── docker-compose.yml - Service definitions
├── main.py         - Example application
└── requirements.txt - Python dependencies

🚀 Getting Started:
----------------
1. Review and customize .env with your settings
2. Install dependencies:
   make build

3. Start the environment:
   make up

4. Common Commands:
   make test     - Run tests
   make lint     - Check code style
   make format   - Format code
   make shell    - Open shell in container
   make logs     - View application logs

🔧 Development Workflow:
--------------------
1. Write code and tests
2. Run 'make format' to format code
3. Run 'make lint' to check style
4. Run 'make test' to run tests
5. Use 'make up' to run the application

🐞 Debugging:
----------
1. Add debugger entry point in your code:
   import debugpy; debugpy.listen(("0.0.0.0", 5678)); debugpy.wait_for_client()

2. Start debugging in VS Code with F5

📝 Notes:
-------
- Non-root user is configured for better security
- VS Code debugging is pre-configured
- Environment variables are loaded from .env
- Makefile provides common development commands
EOF
            ;;
    esac
    
    echo ""
    echo "For more information, check the documentation in each file."
    echo ""
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 <template-name> [output-directory]"
        print_available_templates
        exit 1
    fi
    
    generate_compose_template "$@"
fi