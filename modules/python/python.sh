#!/bin/bash
# modules/python/python.sh - Python module implementation with container support

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "python" || exit 1

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
    if should_containerize "python"; then
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
    if should_containerize "python"; then
        cat << 'EOF'
Container Commands:
-----------------
$ devenv-container start python    # Start Python container
$ devenv-container shell python    # Start a shell in the container
$ devenv-container exec python pip list   # Run a command in container

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
                    if command -v python3 &>/dev/null; then
                        if should_containerize "python"; then
                            # Use container to get Python version
                            if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                                echo "  Version: $(docker exec devenv-python python3 --version 2>/dev/null)"
                            else
                                echo "  Version: (container not running)"
                            fi
                        else
                            echo "  Version: $(python3 --version 2>/dev/null)"
                        fi
                    fi
                    ;;
                "packages")
                    if command -v pip &>/dev/null; then
                        if should_containerize "python"; then
                            if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                                echo "  Packages: $(docker exec devenv-python pip list --format=freeze | wc -l) installed"
                            else
                                echo "  Packages: (container not running)"
                            fi
                        else
                            echo "  Packages: $(pip list --format=freeze | wc -l) installed"
                        fi
                    fi
                    ;;
                "container")
                    if should_containerize "python"; then
                        if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                            echo "  Container: Running"
                        elif docker ps -qa --filter "name=devenv-python" &>/dev/null; then
                            echo "  Container: Stopped"
                        else
                            echo "  Container: Not created"
                        fi
                    else
                        echo "  Container: Not enabled"
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

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            if should_containerize "python"; then
                # For containerized Python, verify the container image exists
                docker image inspect $(get_module_container_image "python") &>/dev/null
            else
                # For native Python, verify the command exists
                command -v python3 &>/dev/null
            fi
            ;;
        "venv")
            if should_containerize "python"; then
                # For containerized Python, assume venv is available
                return 0
            else
                # For native Python, verify venv module
                python3 -c "import venv" &>/dev/null
            fi
            ;;
        "packages")
            # Checking if necessary packages are installed
            if should_containerize "python"; then
                # For containerized Python, check container
                if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                    docker exec devenv-python python3 -c "import pip" &>/dev/null
                else
                    # Container not running, but consider it verified
                    return 0
                fi
            else
                # For native Python
                python3 -c "import pip" &>/dev/null
            fi
            ;;
        "linting")
            # Check linting tools
            if should_containerize "python"; then
                # For containerized Python, check container
                if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                    docker exec devenv-python python3 -c "import black, pylint, flake8, mypy" &>/dev/null
                else
                    # Container not running, but consider it verified
                    return 0
                fi
            else
                # For native Python
                python3 -c "import black, pylint, flake8, mypy" &>/dev/null
            fi
            ;;
        "config")
            # Check Python configuration
            local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
            config_dir=$(eval echo "$config_dir")
            [[ -d "$config_dir" ]] && \
            [[ -f "$config_dir/pyproject.toml" ]] && \
            [[ -f "$config_dir/pylintrc" ]]
            ;;
        "container")
            # Check container configuration
            if should_containerize "python"; then
                # Image should exist
                local image=$(get_module_container_image "python")
                docker image inspect "$image" &>/dev/null
            else
                # Container not required
                return 0
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
    
    config_dir=$(eval echo "$config_dir")
    venv_dir=$(eval echo "$venv_dir")
    bin_dir=$(eval echo "$bin_dir")
    
    mkdir -p "$config_dir" "$venv_dir" "$bin_dir"
    
    if [[ ! -d "$config_dir" ]] || [[ ! -d "$venv_dir" ]] || [[ ! -d "$bin_dir" ]]; then
        log "ERROR" "Failed to create required directories" "python"
        return 1
    fi
    
    return 0
}

# Install core Python component
install_python_core() {
    log "INFO" "Installing Python core..." "python"
    
    if should_containerize "python"; then
        # For containerized Python, use the container management script
        log "INFO" "Using containerized Python..." "python"
        
        # Make sure Docker module is installed
        if ! command -v docker &>/dev/null; then
            log "ERROR" "Docker not installed, required for containerized Python" "python"
            return 1
        fi
        
        # Create container for Python
        if ! command -v devenv-container &>/dev/null; then
            log "ERROR" "devenv-container not found, please install Docker module first" "python"
            return 1
        fi
        
        # Build the container
        if ! devenv-container build python; then
            log "ERROR" "Failed to build Python container" "python"
            return 1
        fi
        
        # Start the container
        if ! devenv-container start python; then
            log "ERROR" "Failed to start Python container" "python"
            return 1
        fi
        
        log "INFO" "Python container setup complete" "python"
    else
        # For native Python, install the packages
        log "INFO" "Installing native Python..." "python"
        
        # Install Python if needed
        if ! command -v python3 &>/dev/null; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get update
                sudo apt-get install -y python3 python3-pip python3-venv python3-dev
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y python3 python3-pip python3-devel
            else
                log "ERROR" "Unsupported package manager" "python"
                return 1
            fi
        fi
        
        # Verify pip installation
        if ! python3 -c "import pip" &>/dev/null; then
            log "INFO" "Installing pip manually..." "python"
            curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
            if ! python3 /tmp/get-pip.py --user; then
                log "ERROR" "Failed to install pip" "python"
                rm -f /tmp/get-pip.py
                return 1
            fi
            rm -f /tmp/get-pip.py
        fi
        
        python3 -m pip install --user --upgrade pip setuptools wheel
        
        log "INFO" "Native Python installation complete" "python"
    fi
    
    return 0
}

# Install Python packages
install_python_packages() {
    log "INFO" "Installing Python packages..." "python"
    
    if should_containerize "python"; then
        # For containerized Python, install packages in the container
        log "INFO" "Installing packages in Python container..." "python"
        
        # Development packages
        local dev_packages=($(get_module_config "python" ".python.packages.development[]"))
        if [[ ${#dev_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing development packages in container..." "python"
            if ! devenv-container exec python pip install ${dev_packages[@]}; then
                log "ERROR" "Failed to install development packages in container" "python"
                return 1
            fi
        fi
        
        # Linting packages
        local lint_packages=($(get_module_config "python" ".python.packages.linting[]"))
        if [[ ${#lint_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing linting packages in container..." "python"
            if ! devenv-container exec python pip install ${lint_packages[@]}; then
                log "ERROR" "Failed to install linting packages in container" "python"
                return 1
            fi
        fi
        
        # Data science packages
        local data_packages=($(get_module_config "python" ".python.packages.utils.data_processing.packages[]"))
        if [[ ${#data_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing data science packages in container..." "python"
            if ! devenv-container exec python pip install ${data_packages[@]}; then
                log "ERROR" "Failed to install data science packages in container" "python"
                return 1
            fi
        fi
        
        log "INFO" "Package installation in container complete" "python"
    else
        # For native Python, install the packages on the host
        log "INFO" "Installing Python packages natively..." "python"
        
        # Development packages
        local dev_packages=($(get_module_config "python" ".python.packages.development[]"))
        if [[ ${#dev_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing development packages..." "python"
            python3 -m pip install --user ${dev_packages[@]} || return 1
        fi
        
        # Linting packages
        local lint_packages=($(get_module_config "python" ".python.packages.linting[]"))
        if [[ ${#lint_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing linting packages..." "python"
            python3 -m pip install --user ${lint_packages[@]} || return 1
        fi
        
        # Data science packages
        local data_packages=($(get_module_config "python" ".python.packages.utils.data_processing.packages[]"))
        if [[ ${#data_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing data science packages..." "python"
            python3 -m pip install --user ${data_packages[@]} || return 1
        fi
        
        log "INFO" "Native package installation complete" "python"
    fi
    
    return 0
}

# Configure Python development tools
configure_python_tools() {
    log "INFO" "Configuring Python development tools..." "python"
    
    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    # Create configuration files
    mkdir -p "$config_dir"
    
    # Configure Black with pyproject.toml
    local black_config=$(get_module_config "python" ".python.config.black")
    if [[ -n "$black_config" ]]; then
        cat > "$config_dir/pyproject.toml" << EOF
[tool.black]
line-length = $(get_module_config "python" ".python.config.black.line-length" "100")
target-version = ["py310"]
EOF
    fi
    
    # Configure Pylint
    local pylint_config=$(get_module_config "python" ".python.config.pylint")
    if [[ -n "$pylint_config" ]]; then
        # Create pylintrc
        if should_containerize "python"; then
            # For containerized Python, use the container to generate pylintrc
            devenv-container exec python pylint --generate-rcfile > "$config_dir/pylintrc"
        else
            # For native Python, use pylint directly
            pylint --generate-rcfile > "$config_dir/pylintrc"
        fi
        
        # Update pylintrc with configuration
        local disabled_checks=$(get_module_config "python" ".python.config.pylint.disable[]" | tr -s '\n' ',')
        local good_names=$(get_module_config "python" ".python.config.pylint.good-names[]" | tr -s '\n' ',')
        local max_line_length=$(get_module_config "python" ".python.config.pylint.max-line-length" "100")
        
        sed -i "s/^disable=.*/disable=$disabled_checks/" "$config_dir/pylintrc"
        sed -i "s/^good-names=.*/good-names=$good_names/" "$config_dir/pylintrc"
        sed -i "s/^max-line-length=.*/max-line-length=$max_line_length/" "$config_dir/pylintrc"
    fi
    
    # Configure Flake8
    local flake8_config=$(get_module_config "python" ".python.config.flake8")
    if [[ -n "$flake8_config" ]]; then
        local flake8_ignore=$(get_module_config "python" ".python.config.flake8.ignore[]" | tr -s '\n' ',')
        local flake8_max_line=$(get_module_config "python" ".python.config.flake8.max-line-length" "100")
        
        cat > "$config_dir/flake8" << EOF
[flake8]
max-line-length = $flake8_max_line
ignore = $flake8_ignore
EOF
    fi
    
    return 0
}

# Create Python command wrappers for containerized Python
create_python_wrappers() {
    log "INFO" "Creating Python command wrappers..." "python"
    
    local bin_dir=$(get_module_config "python" ".shell.paths.bin_dir")
    bin_dir=$(eval echo "$bin_dir")
    
    mkdir -p "$bin_dir"
    
    # Python wrapper
    cat > "$bin_dir/py" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run Python in container
    devenv-container exec python python "$@"
else
    # Run Python natively
    python3 "$@"
fi
EOF
    chmod +x "$bin_dir/py"
    
    # Pip wrapper
    cat > "$bin_dir/py-pip" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run pip in container
    devenv-container exec python pip "$@"
else
    # Run pip natively
    python3 -m pip "$@"
fi
EOF
    chmod +x "$bin_dir/py-pip"
    
    # Venv wrapper
    cat > "$bin_dir/py-venv" << 'EOF'
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <venv_name>"
    exit 1
fi

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Create venv in container
    devenv-container exec python python -m venv "$1"
else
    # Create venv natively
    python3 -m venv "$1"
fi
EOF
    chmod +x "$bin_dir/py-venv"
    
    # IPython wrapper
    cat > "$bin_dir/py-ipython" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run IPython in container
    devenv-container exec python ipython "$@"
else
    # Run IPython natively
    if command -v ipython &>/dev/null; then
        ipython "$@"
    else
        echo "IPython not installed. Run 'py-pip install ipython' to install it."
        exit 1
    fi
fi
EOF
    chmod +x "$bin_dir/py-ipython"
    
    # Jupyter wrapper
    cat > "$bin_dir/py-jupyter" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Start Jupyter in container with port forwarding
    docker exec -it -p 8888:8888 devenv-python jupyter lab --ip 0.0.0.0 --no-browser
else
    # Run Jupyter natively
    if command -v jupyter &>/dev/null; then
        jupyter lab "$@"
    else
        echo "Jupyter not installed. Run 'py-pip install jupyterlab' to install it."
        exit 1
    fi
fi
EOF
    chmod +x "$bin_dir/py-jupyter"
    
    # Black formatter wrapper
    cat > "$bin_dir/py-fmt" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run Black in container
    devenv-container exec python black "$@"
else
    # Run Black natively
    if command -v black &>/dev/null; then
        black "$@"
    else
        echo "Black not installed. Run 'py-pip install black' to install it."
        exit 1
    fi
fi
EOF
    chmod +x "$bin_dir/py-fmt"
    
    # Pylint wrapper
    cat > "$bin_dir/py-lint" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run Pylint in container
    devenv-container exec python pylint "$@"
else
    # Run Pylint natively
    if command -v pylint &>/dev/null; then
        pylint "$@"
    else
        echo "Pylint not installed. Run 'py-pip install pylint' to install it."
        exit 1
    fi
fi
EOF
    chmod +x "$bin_dir/py-lint"
    
    # MyPy wrapper
    cat > "$bin_dir/py-mypy" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run MyPy in container
    devenv-container exec python mypy "$@"
else
    # Run MyPy natively
    if command -v mypy &>/dev/null; then
        mypy "$@"
    else
        echo "MyPy not installed. Run 'py-pip install mypy' to install it."
        exit 1
    fi
fi
EOF
    chmod +x "$bin_dir/py-mypy"
    
    # PyTest wrapper
    cat > "$bin_dir/py-test" << 'EOF'
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && \
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run PyTest in container
    devenv-container exec python pytest "$@"
else
    # Run PyTest natively
    if command -v pytest &>/dev/null; then
        pytest "$@"
    else
        echo "PyTest not installed. Run 'py-pip install pytest' to install it."
        exit 1
    fi
fi
EOF
    chmod +x "$bin_dir/py-test"
    
    # Add bin directory to PATH if not already
    if ! grep -q "$bin_dir" "$HOME/.bashrc"; then
        echo "export PATH=\"$bin_dir:\$PATH\"" >> "$HOME/.bashrc"
    fi
    
    # Add to ZSH too if it exists
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "$bin_dir" "$HOME/.zshrc"; then
        echo "export PATH=\"$bin_dir:\$PATH\"" >> "$HOME/.zshrc"
    fi
    
    return 0
}

# Setup container for Python if needed
setup_python_container() {
    log "INFO" "Setting up Python container..." "python"
    
    if ! should_containerize "python"; then
        log "INFO" "Python containerization not enabled, skipping" "python"
        return 0
    fi
    
    # Ensure Docker is installed
    if ! command -v docker &>/dev/null; then
        log "ERROR" "Docker not installed, required for containerized Python" "python"
        return 1
    fi
    
    # Ensure devenv-container is available
    if ! command -v devenv-container &>/dev/null; then
        log "ERROR" "devenv-container not found, please install Docker module first" "python"
        return 1
    fi
    
    # Build Python container
    log "INFO" "Building Python container..." "python"
    if ! devenv-container build python; then
        log "ERROR" "Failed to build Python container" "python"
        return 1
    fi
    
    # Start Python container
    log "INFO" "Starting Python container..." "python"
    if ! devenv-container start python; then
        log "ERROR" "Failed to start Python container" "python"
        return 1
    fi
    
    log "INFO" "Python container setup complete" "python"
    return 0
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
            # venv is included in core Python
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
        if should_containerize "python"; then
            if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                log "INFO" "Python version: $(docker exec devenv-python python3 --version)" "python"
            else
                log "INFO" "Python container not running" "python"
            fi
        else
            log "INFO" "Python version: $(python3 --version)" "python"
        fi
    fi
    
    return $status
}

# Remove Python configuration
remove_python() {
    log "INFO" "Removing Python configuration..." "python"
    
    # Stop and remove container if containerized
    if should_containerize "python"; then
        log "INFO" "Stopping and removing Python container..." "python"
        
        if command -v devenv-container &>/dev/null; then
            devenv-container stop python
            docker rm -f devenv-python 2>/dev/null
        fi
    fi
    
    # Remove configuration files
    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    rm -rf "$config_dir"
    
    # Remove command wrappers
    local bin_dir=$(get_module_config "python" ".shell.paths.bin_dir")
    bin_dir=$(eval echo "$bin_dir")
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
    log "WARN" "Python packages were preserved. Use 'pip uninstall' to remove specific packages." "python"
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