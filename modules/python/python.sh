#!/bin/bash
# modules/python/python.sh - Python module implementation with container support

set -euo pipefail
# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "python" || exit 1

# Set module-specific data directory
export DEVENV_PYTHON_DIR="${DEVENV_DATA_DIR}/python"

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/python.state"

# Components list for module
COMPONENTS=(
    "core"           # Base Python installation
    "venv"           # Virtual environment support
    "packages"       # Essential packages
    "linting"        # Code quality tools
    "config"         # Python configuration
    "container"      # Container configuration
)

# Display module information
show_module_info() {
    # Check if this module is containerized
    local container_info=""
    if type should_containerize >/dev/null 2>&1 && should_containerize "python"; then
        container_info="(Containerized)"
        local image=$(get_module_container_image "python")
        container_info="$container_info\nContainer image: $image"
    fi

    cat << EOF

🐍 Python Development Environment $container_info
==============================

Description:
-----------
Comprehensive Python development environment with linting, formatting, 
and essential data science & development tools.

Benefits:
--------
✓ Complete Development Toolkit - IPython, Jupyter, and VSCode integration
✓ Code Quality Tools - Black, Pylint, Flake8, and MyPy pre-configured
✓ Data Science Ready - NumPy, Pandas, SciPy pre-installed
✓ Documentation Tools - Sphinx and MkDocs support
✓ Testing Framework - PyTest with coverage and benchmarking

Components:
----------
1. Core Python
   - Python 3.10+ interpreter
   - pip package manager
   - venv/virtualenv support

2. Development Tools
   - IPython for enhanced REPL
   - Jupyter notebooks/lab
   - Build tools (setuptools, wheel)

3. Code Quality
   - Black formatter
   - Pylint linter
   - Flake8 style checker
   - MyPy type checker

4. Data Science
   - NumPy for numerical computing
   - Pandas for data analysis
   - SciPy for scientific computing

Quick Start:
-----------
1. Format code with Black:
   $ py-fmt myfile.py

2. Run linting:
   $ py-lint myfile.py

3. Start Jupyter:
   $ py-jupyter

4. Run Python:
   $ py script.py

EOF

    # If containerized, add container commands
    if type should_containerize >/dev/null 2>&1 && should_containerize "python"; then
        cat << 'EOF'
Container Commands:
-----------------
$ $HOME/.devenv/bin/devenv-container start python    # Start Python container
$ $HOME/.devenv/bin/devenv-container shell python    # Start a shell in the container
$ $HOME/.devenv/bin/devenv-container exec python pip list   # Run a command in container

EOF
    fi

    cat << 'EOF'
Aliases:
-------
py        : Run Python interpreter
py-pip    : Run pip package manager
py-venv   : Create a new virtual environment
py-ipython: Start IPython REPL
py-jupyter: Start Jupyter Lab
py-fmt    : Format code with Black
py-lint   : Run pylint
py-mypy   : Run mypy type checker
py-test   : Run pytest

Configuration:
-------------
Location: ~/.config/python
Key files:
- pyproject.toml : Black and tool settings
- pylintrc       : Linting configuration
- setup.cfg      : Development configuration

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if type should_containerize >/dev/null 2>&1 && should_containerize "python"; then
                        # Use container to get Python version
                        if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                            echo "  Version: $(docker exec devenv-python python3 --version 2>/dev/null)"
                        else
                            echo "  Version: (container not running)"
                        fi
                    else
                        # Check virtual environment
                        local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                        venv_dir=$(echo "$venv_dir" | expand_vars)
                        if [[ -f "$venv_dir/bin/python" ]]; then
                            echo "  Version: $("$venv_dir/bin/python" --version 2>/dev/null)"
                        else
                            echo "  Version: $(python3 --version 2>/dev/null)"
                        fi
                    fi
                    ;;
                "packages")
                    if type should_containerize >/dev/null 2>&1 && should_containerize "python"; then
                        if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                            echo "  Packages: $(docker exec devenv-python pip list --format=freeze | wc -l) installed"
                        else
                            echo "  Packages: (container not running)"
                        fi
                    else
                        # Check virtual environment
                        local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                        venv_dir=$(echo "$venv_dir" | expand_vars)
                        if [[ -f "$venv_dir/bin/pip" ]]; then
                            echo "  Packages: $("$venv_dir/bin/pip" list --format=freeze | wc -l) installed"
                        else
                            echo "  Packages: $(pip list --format=freeze | wc -l) installed"
                        fi
                    fi
                    ;;
                "container")
                    if type should_containerize >/dev/null 2>&1 && should_containerize "python"; then
                        if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                            echo "  Container: Running"
                        elif docker ps -qa --filter "name=devenv-python" &>/dev/null; then
                            echo "  Container: Stopped"
                        else
                            echo "  Container: Not created"
                        fi
                    else
                        # Check virtual environment
                        local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                        venv_dir=$(echo "$venv_dir" | expand_vars)
                        if [[ -d "$venv_dir" ]]; then
                            echo "  Virtual Env: $venv_dir"
                        else
                            echo "  Virtual Env: Not created"
                        fi
                    fi
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
    echo
}

# Save component state
save_state() {
    local component=$1
    local status=$2
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$component:$status:$(date +%s)" >> "$STATE_FILE"
}

# Check component state
check_state() {
    local component=$1
    if [[ -f "$STATE_FILE" ]]; then
        grep -q "^$component:installed:" "$STATE_FILE"
        return $?
    fi
    return 1
}

# Check if containerization is available and usable
check_container_functions() {
    # Check if required functions are available
    if ! type should_containerize >/dev/null 2>&1; then
        log "WARN" "Container functions not available, using virtual environment" "python"
        return 1
    fi
    
    # Check if Docker is available
    if ! command -v docker >/dev/null 2>&1; then
        log "WARN" "Docker not installed, using virtual environment" "python"
        return 1
    fi
    
    # Use Docker module's WSL verification function if available
    if type verify_docker_wsl_integration >/dev/null 2>&1; then
        # Check if function is available and running in WSL
        if type is_wsl >/dev/null 2>&1 && is_wsl; then
            log "INFO" "WSL environment detected, verifying Docker integration..." "python"
            
            # Test Docker connectivity using the Docker module's verification function
            if ! verify_docker_wsl_integration; then
                log "WARN" "Docker not properly configured in WSL. Using virtual environment instead." "python"
                log "INFO" "To fix Docker in WSL, run 'devenv.sh install docker' first." "python"
                return 1
            else
                log "INFO" "Docker in WSL is properly configured." "python"
            fi
        fi
    else
        # Fallback to basic Docker connectivity check with timeout
        if ! timeout 5 docker info >/dev/null 2>&1; then
            log "WARN" "Docker is not running or not accessible, using virtual environment" "python"
            return 1
        fi
    fi
    
    return 0
}

# Safe version of should_containerize
should_use_container() {
    local module=$1

    # Check if container functions are available
    if ! check_container_functions; then
        return 1
    fi

    # Use the existing function if available
    should_containerize "$module"
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            if should_use_container "python"; then
                # For containerized Python, verify the container image exists
                docker image inspect $(get_module_container_image "python") &>/dev/null
            else
                # For virtual env Python, verify python or venv exists
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(echo "$venv_dir" | expand_vars)
                [[ -f "$venv_dir/bin/python" ]] || command -v python3 &>/dev/null
            fi
            ;;
        "venv")
            if should_use_container "python"; then
                return 0
            else
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(echo "$venv_dir" | expand_vars)
                [[ -d "$venv_dir" ]] && [[ -f "$venv_dir/bin/python" ]]
            fi
            ;;
        "packages")
            if should_use_container "python"; then
                if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                    docker exec devenv-python python3 -c "import pip" &>/dev/null
                else
                    return 0
                fi
            else
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(echo "$venv_dir" | expand_vars)
                [[ -f "$venv_dir/bin/pip" ]]
            fi
            ;;
        "linting")
            if should_use_container "python"; then
                if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                    docker exec devenv-python python3 -c "import black, pylint, flake8, mypy" &>/dev/null
                else
                    return 0
                fi
            else
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(echo "$venv_dir" | expand_vars)
                "$venv_dir/bin/python" -c "import black, pylint, flake8, mypy" &>/dev/null
            fi
            ;;
        "config")
            local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
            config_dir=$(echo "$config_dir" | expand_vars)
            [[ -d "$config_dir" ]] && \
            [[ -f "$config_dir/pyproject.toml" ]] && \
            [[ -f "$config_dir/pylintrc" ]]
            ;;
        "container")
            if should_use_container "python"; then
                local image=$(get_module_container_image "python")
                docker image inspect "$image" &>/dev/null
            else
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(echo "$venv_dir" | expand_vars)
                [[ -d "$venv_dir" ]]
            fi
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Create required directories
create_directories() {
    log "INFO" "Creating required directories..." "python"

    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    local bin_dir=$(get_module_config "python" ".shell.paths.bin_dir")

    config_dir=$(echo "$config_dir" | expand_vars)
    venv_dir=$(echo "$venv_dir" | expand_vars)
    bin_dir=$(echo "$bin_dir" | expand_vars)

    # Create config and bin dirs, but only venv's PARENT (venv created by python3 -m venv)
    mkdir -p "$config_dir" "$(dirname "$venv_dir")" "$bin_dir"

    if [[ ! -d "$config_dir" ]] || [[ ! -d "$bin_dir" ]]; then
        log "ERROR" "Failed to create required directories" "python"
        return 1
    fi

    return 0
}

# Determine venv path based on mode
get_venv_path() {
    if [[ "${DEVENV_MODE:-}" == "Global" ]]; then
        echo "${DEVENV_PYTHON_DIR}/venv"
    else
        echo "${DEVENV_DATA_DIR:-$HOME/.devenv}/python/venv"
    fi
}

# Setup Python virtual environment
goto_venv_setup() {
    log "INFO" "Setting up Python virtual environment..." "python"

    if ! command -v python3 &>/dev/null; then
        log "INFO" "Installing Python using system package manager..." "python"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv python3-dev
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y python3 python3-pip python3-devel
        else
            log "ERROR" "Unsupported package manager" "python"
            return 1
        fi

        if ! command -v python3 &>/dev/null; then
            log "ERROR" "Failed to install Python3" "python"
            return 1
        fi
    fi

    local venv_dir=$(get_venv_path)

    if [[ ! -d "$venv_dir" ]]; then
        log "INFO" "Creating Python virtual environment in $venv_dir" "python"
        mkdir -p "$(dirname "$venv_dir")"
        python3 -m venv "$venv_dir"
    fi

    if [[ ! -f "$venv_dir/bin/activate" ]]; then
        log "ERROR" "Failed to create virtual environment at $venv_dir" "python"
        return 1
    fi

    log "INFO" "Activating virtual environment and updating pip" "python"
    source "$venv_dir/bin/activate"
    "$venv_dir/bin/pip" install --upgrade pip setuptools wheel

    log "INFO" "Python virtual environment setup complete at $venv_dir" "python"
    return 0
}

# Install core Python component
install_python_core() {
    log "INFO" "Installing Python core..." "python"

    if command -v docker &>/dev/null && should_use_container "python"; then
        log "INFO" "Using containerized Python..." "python"

        if ! command -v $HOME/.devenv/bin/devenv-container &>/dev/null; then
            log "WARN" "Container management tool not found, falling back to virtual environment" "python"
            goto_venv_setup
            return $?
        fi

        log "INFO" "Building Python container..." "python"
        if ! $HOME/.devenv/bin/devenv-container build python; then
            log "WARN" "Failed to build Python container, falling back to virtual environment" "python"
            goto_venv_setup
            return $?
        fi

        log "INFO" "Starting Python container..." "python"
        if ! $HOME/.devenv/bin/devenv-container start python; then
            log "WARN" "Failed to start Python container, falling back to virtual environment" "python"
            goto_venv_setup
            return $?
        fi

        log "INFO" "Python container setup complete" "python"
        return 0
    else
        log "INFO" "Docker not available or containerization not enabled, using virtual environment" "python"
        goto_venv_setup
        return $?
    fi
}

# Install Python packages
install_python_packages() {
    log "INFO" "Installing Python packages..." "python"

    if should_use_container "python"; then
        log "INFO" "Installing packages in Python container..." "python"

        if ! docker ps -q --filter "name=devenv-python" &>/dev/null; then
            log "ERROR" "Python container not running" "python"
            return 1
        fi

        local dev_packages=($(get_module_config "python" ".python.packages.development[]"))
        if [[ ${#dev_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing development packages in container..." "python"
            $HOME/.devenv/bin/devenv-container exec python pip install ${dev_packages[@]} || return 1
        fi

        local lint_packages=($(get_module_config "python" ".python.packages.linting[]"))
        if [[ ${#lint_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing linting packages in container..." "python"
            $HOME/.devenv/bin/devenv-container exec python pip install ${lint_packages[@]} || return 1
        fi

        log "INFO" "Package installation in container complete" "python"
    else
        log "INFO" "Installing Python packages in virtual environment..." "python"

        local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
        venv_dir=$(echo "$venv_dir" | expand_vars)

        if [[ ! -f "$venv_dir/bin/pip" ]]; then
            log "ERROR" "Virtual environment not found or incomplete" "python"
            return 1
        fi

        local dev_packages=($(get_module_config "python" ".python.packages.development[]"))
        if [[ ${#dev_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing development packages..." "python"
            "$venv_dir/bin/pip" install ${dev_packages[@]} || return 1
        fi

        local lint_packages=($(get_module_config "python" ".python.packages.linting[]"))
        if [[ ${#lint_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing linting packages..." "python"
            "$venv_dir/bin/pip" install ${lint_packages[@]} || return 1
        fi

        log "INFO" "Package installation complete" "python"
    fi

    return 0
}

# Configure Python development tools
configure_python_tools() {
    log "INFO" "Configuring Python development tools..." "python"

    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    config_dir=$(echo "$config_dir" | expand_vars)
    mkdir -p "$config_dir"

    # Configure Black
    cat > "$config_dir/pyproject.toml" << EOF
[tool.black]
line-length = $(get_module_config "python" ".python.config.black.line-length" "100")
target-version = ["py310"]
EOF

    # Configure Pylint
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    venv_dir=$(echo "$venv_dir" | expand_vars)

    if [[ -f "$venv_dir/bin/pylint" ]]; then
        "$venv_dir/bin/pylint" --generate-rcfile > "$config_dir/pylintrc" 2>/dev/null || true
    else
        cat > "$config_dir/pylintrc" << EOF
[MASTER]
ignore=CVS
persistent=yes

[MESSAGES CONTROL]
disable=raw-checker-failed,locally-disabled

[FORMAT]
max-line-length=100
EOF
    fi

    return 0
}

# Create Python command wrappers
create_python_wrappers() {
    log "INFO" "Creating Python command wrappers..." "python"

    local bin_dir=$(get_module_config "python" ".shell.paths.bin_dir")
    bin_dir=$(echo "$bin_dir" | expand_vars)
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    venv_dir=$(echo "$venv_dir" | expand_vars)

    mkdir -p "$bin_dir"

    # Create simple wrappers that use venv Python
    for cmd in py:python py-pip:pip py-ipython:ipython py-jupyter:jupyter py-fmt:black py-lint:pylint py-mypy:mypy py-test:pytest; do
        local name="${cmd%%:*}"
        local target="${cmd##*:}"
        
        cat > "$bin_dir/$name" << WRAPPER
#!/bin/bash
if [ -f "$venv_dir/bin/$target" ]; then
    "$venv_dir/bin/$target" "\$@"
else
    echo "$target not found. Install it with: py-pip install $target"
    exit 1
fi
WRAPPER
        chmod +x "$bin_dir/$name"
    done

    # Special case for py - fallback to python3
    cat > "$bin_dir/py" << WRAPPER
#!/bin/bash
if [ -f "$venv_dir/bin/python" ]; then
    "$venv_dir/bin/python" "\$@"
else
    python3 "\$@"
fi
WRAPPER
    chmod +x "$bin_dir/py"

    return 0
}

# Setup container for Python if needed
setup_python_container() {
    log "INFO" "Setting up Python container..." "python"

    if ! should_use_container "python"; then
        log "INFO" "Python containerization not enabled, skipping" "python"
        return 0
    fi

    if ! command -v docker &>/dev/null; then
        log "ERROR" "Docker not installed" "python"
        return 1
    fi

    if ! command -v $HOME/.devenv/bin/devenv-container &>/dev/null; then
        log "ERROR" "devenv-container not found" "python"
        return 1
    fi

    $HOME/.devenv/bin/devenv-container build python && \
    $HOME/.devenv/bin/devenv-container start python

    return $?
}
# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "python"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_python_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "venv")
            # venv is included in core Python or handled by container
            save_state "venv" "installed"
            return 0
            ;;
        "packages")
            if install_python_packages; then
                save_state "packages" "installed"
                return 0
            fi
            ;;
        "linting")
            # Linting tools are included in packages
            save_state "linting" "installed"
            return 0
            ;;
        "config")
            if configure_python_tools && create_python_wrappers; then
                save_state "config" "installed"
                return 0
            fi
            ;;
        "container")
            if setup_python_container; then
                save_state "container" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Check if Python is already installed and configured
grovel_python() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "python"
            status=1
        fi
    done
    
    return $status
}

# Install Python with all components
install_python() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_python &>/dev/null; then
        create_backup
    fi
    
    # Create necessary directories
    create_directories || return 1
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "python"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "python"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "python"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Verify Python installation
verify_python() {
    log "INFO" "Verifying Python installation..." "python"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "python"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "Python verification completed successfully" "python"
        
        # Show Python version
        if should_use_container "python"; then
            if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                log "INFO" "Python version: $(docker exec devenv-python python3 --version)" "python"
            else
                log "INFO" "Python container not running" "python"
            fi
        else
            # Virtual environment approach
            local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
            venv_dir=$(echo "$venv_dir" | expand_vars)
            if [[ -f "$venv_dir/bin/python" ]]; then
                log "INFO" "Python version: $("$venv_dir/bin/python" --version)" "python"
            else
                log "INFO" "Python virtual environment not activated" "python"
            fi
        fi
    fi
    
    return $status
}

# Remove Python configuration
remove_python() {
    log "INFO" "Removing Python configuration..." "python"
    
    # Stop and remove container if containerized
    if should_use_container "python"; then
        log "INFO" "Stopping and removing Python container..." "python"
        
        if command -v $HOME/.devenv/bin/devenv-container &>/dev/null; then
            $HOME/.devenv/bin/devenv-container stop python
            docker rm -f devenv-python 2>/dev/null
        fi
    fi
    
    # Remove virtual environment
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    venv_dir=$(echo "$venv_dir" | expand_vars)
    if [[ -d "$venv_dir" ]]; then
        log "INFO" "Removing Python virtual environment..." "python"
        rm -rf "$venv_dir"
    fi
    
    # Remove configuration files
    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    config_dir=$(echo "$config_dir" | expand_vars)
    rm -rf "$config_dir"
    
    # Remove command wrappers
    local bin_dir=$(get_module_config "python" ".shell.paths.bin_dir")
    bin_dir=$(echo "$bin_dir" | expand_vars)
    rm -f "$bin_dir/py"
    rm -f "$bin_dir/py-pip"
    rm -f "$bin_dir/py-venv"
    rm -f "$bin_dir/py-ipython"
    rm -f "$bin_dir/py-jupyter"
    rm -f "$bin_dir/py-fmt"
    rm -f "$bin_dir/py-lint"
    rm -f "$bin_dir/py-mypy"
    rm -f "$bin_dir/py-test"
    
    # Remove state file
    rm -f "$STATE_FILE"
    
    log "INFO" "Python configuration removed" "python"
    log "WARN" "Python system packages were preserved. Use system package manager to remove if needed." "python"
    return 0
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_python
        ;;
    install)
        install_python "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_python
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_python
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "python"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac
