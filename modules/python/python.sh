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
                        venv_dir=$(eval echo "$venv_dir")
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
                        venv_dir=$(eval echo "$venv_dir")
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
                        venv_dir=$(eval echo "$venv_dir")
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
    
    # Test Docker functionality
    if ! docker info >/dev/null 2>&1; then
        log "WARN" "Docker is not running or not accessible, using virtual environment" "python"
        return 1
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
                venv_dir=$(eval echo "$venv_dir")
                [[ -f "$venv_dir/bin/python" ]] || command -v python3 &>/dev/null
            fi
            ;;
        "venv")
            if should_use_container "python"; then
                # For containerized Python, assume venv is available
                return 0
            else
                # For virtual env Python, verify venv exists
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(eval echo "$venv_dir")
                [[ -d "$venv_dir" ]] && [[ -f "$venv_dir/bin/python" ]]
            fi
            ;;
        "packages")
            # Checking if necessary packages are installed
            if should_use_container "python"; then
                # For containerized Python, check container
                if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                    docker exec devenv-python python3 -c "import pip" &>/dev/null
                else
                    # Container not running, but consider it verified
                    return 0
                fi
            else
                # For virtual env Python
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(eval echo "$venv_dir")
                [[ -f "$venv_dir/bin/pip" ]]
            fi
            ;;
        "linting")
            # Check linting tools
            if should_use_container "python"; then
                # For containerized Python, check container
                if docker ps -q --filter "name=devenv-python" &>/dev/null; then
                    docker exec devenv-python python3 -c "import black, pylint, flake8, mypy" &>/dev/null
                else
                    # Container not running, but consider it verified
                    return 0
                fi
            else
                # For virtual env Python
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(eval echo "$venv_dir")
                "$venv_dir/bin/python" -c "import black, pylint, flake8, mypy" &>/dev/null
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
            # Check container or virtual env configuration
            if should_use_container "python"; then
                # Image should exist
                local image=$(get_module_container_image "python")
                docker image inspect "$image" &>/dev/null
            else
                # Virtual env should exist
                local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
                venv_dir=$(eval echo "$venv_dir")
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
    
    if should_use_container "python"; then
        # For containerized Python, use the container management script
        log "INFO" "Using containerized Python..." "python"
        
        # Check for Docker installation
        if ! command -v docker &>/dev/null; then
            log "ERROR" "Docker not installed, required for containerized Python" "python"
            log "WARN" "Attempting to install Docker module..." "python"
            
            # Try to install Docker module
            if [[ -f "$DEVENV_ROOT/devenv.sh" ]]; then
                "$DEVENV_ROOT/devenv.sh" install docker
                
                # Check if Docker was installed successfully
                if ! command -v docker &>/dev/null; then
                    log "ERROR" "Failed to install Docker, falling back to virtual environment" "python"
                    # Continue with virtual environment approach
                else
                    log "INFO" "Docker installed successfully" "python"
                fi
            else
                log "ERROR" "Failed to install Docker, falling back to virtual environment" "python"
                # Continue with virtual environment approach
            fi
        fi
        
        # Check for devenv-container script
        if ! command -v devenv-container &>/dev/null; then
            local bin_dir="${DEVENV_ROOT}/data/bin"
            if [[ -x "${DEVENV_ROOT}/modules/docker/bin/devenv-container" ]]; then
                # Copy the script to bin directory if it exists
                mkdir -p "$bin_dir"
                cp "${DEVENV_ROOT}/modules/docker/bin/devenv-container" "$bin_dir/"
                chmod +x "$bin_dir/devenv-container"
                export PATH="$PATH:$bin_dir"
            else
                log "ERROR" "devenv-container not found, falling back to virtual environment" "python"
                # Continue with virtual environment approach without containerization
            fi
        fi
        
        # Final check if we can still use containerization
        if ! command -v docker &>/dev/null || ! command -v devenv-container &>/dev/null; then
            # If we got here, we couldn't set up containerization, so fall back to venv
            goto_venv_setup
            return $?
        fi
        
        # Build the container
        log "INFO" "Building Python container..." "python"
        if ! devenv-container build python; then
            log "ERROR" "Failed to build Python container, falling back to virtual environment" "python"
            goto_venv_setup
            return $?
        fi
        
        # Start the container
        log "INFO" "Starting Python container..." "python"
        if ! devenv-container start python; then
            log "ERROR" "Failed to start Python container, falling back to virtual environment" "python"
            goto_venv_setup
            return $?
        fi
        
        log "INFO" "Python container setup complete" "python"
    else
        # For non-containerized Python, use a virtual environment
        goto_venv_setup
    fi
    
    return 0
}

# Setup Python virtual environment (used as fallback or primary approach)
goto_venv_setup() {
    log "INFO" "Setting up Python virtual environment..." "python"
    
    # Make sure Python is installed
    if ! command -v python3 &>/dev/null; then
        log "INFO" "Installing Python..." "python"
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
    
    # Create virtual environment
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    venv_dir=$(eval echo "$venv_dir")
    
    # Create virtual environment if it doesn't exist
    if [[ ! -d "$venv_dir" ]]; then
        log "INFO" "Creating Python virtual environment in $venv_dir" "python"
        if ! python3 -m venv "$venv_dir"; then
            # If venv module isn't available, try to install it
            if command -v apt-get &>/dev/null; then
                log "INFO" "Installing python3-venv package..." "python"
                sudo apt-get install -y python3-venv
                
                # Try creating the virtual environment again
                if ! python3 -m venv "$venv_dir"; then
                    log "ERROR" "Failed to create virtual environment" "python"
                    return 1
                fi
            else
                log "ERROR" "Failed to create virtual environment" "python"
                return 1
            fi
        fi
    fi
    
    # Activate and update the virtual environment
    if [[ -f "$venv_dir/bin/activate" ]]; then
        log "INFO" "Activating virtual environment..." "python"
        source "$venv_dir/bin/activate"
        
        # Update pip, setuptools, and wheel
        log "INFO" "Updating pip in virtual environment..." "python"
        "$venv_dir/bin/pip" install --upgrade pip setuptools wheel
    else
        log "ERROR" "Virtual environment activation script not found" "python"
        return 1
    fi
    
    log "INFO" "Python virtual environment setup complete" "python"
    return 0
}

# Install Python packages
install_python_packages() {
    log "INFO" "Installing Python packages..." "python"
    
    if should_use_container "python"; then
        # For containerized Python, install packages in the container
        log "INFO" "Installing packages in Python container..." "python"
        
        # Check if container is running
        if ! docker ps -q --filter "name=devenv-python" &>/dev/null; then
            log "ERROR" "Python container not running" "python"
            return 1
        fi
        
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
        # For non-containerized Python, use the virtual environment
        log "INFO" "Installing Python packages in virtual environment..." "python"
        
        local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
        venv_dir=$(eval echo "$venv_dir")
        
        # Ensure virtual environment exists
        if [[ ! -f "$venv_dir/bin/pip" ]]; then
            log "ERROR" "Virtual environment not found or incomplete" "python"
            return 1
        fi
        
        # Development packages
        local dev_packages=($(get_module_config "python" ".python.packages.development[]"))
        if [[ ${#dev_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing development packages in virtual environment..." "python"
            "$venv_dir/bin/pip" install ${dev_packages[@]} || return 1
        fi
        
        # Linting packages
        local lint_packages=($(get_module_config "python" ".python.packages.linting[]"))
        if [[ ${#lint_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing linting packages in virtual environment..." "python"
            "$venv_dir/bin/pip" install ${lint_packages[@]} || return 1
        fi
        
        # Data science packages
        local data_packages=($(get_module_config "python" ".python.packages.utils.data_processing.packages[]"))
        if [[ ${#data_packages[@]} -gt 0 ]]; then
            log "INFO" "Installing data science packages in virtual environment..." "python"
            "$venv_dir/bin/pip" install ${data_packages[@]} || return 1
        fi
        
        log "INFO" "Package installation in virtual environment complete" "python"
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
        # Create pylintrc from template or generate it
        if should_use_container "python"; then
            # For containerized Python, use the container to generate pylintrc
            devenv-container exec python pylint --generate-rcfile > "$config_dir/pylintrc"
        else
            # For non-containerized Python, use virtual environment
            local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
            venv_dir=$(eval echo "$venv_dir")
            
            if [[ -f "$venv_dir/bin/pylint" ]]; then
                "$venv_dir/bin/pylint" --generate-rcfile > "$config_dir/pylintrc"
            else
                # If pylint not installed yet, create a minimal template
                cat > "$config_dir/pylintrc" << EOF
[MASTER]
ignore=CVS
persistent=yes
load-plugins=

[MESSAGES CONTROL]
disable=raw-checker-failed,locally-disabled

[REPORTS]
output-format=text
reports=yes
evaluation=10.0 - ((float(5 * error + warning + refactor + convention) / statement) * 10)

[BASIC]
good-names=i,j,k,ex,Run,_
bad-names=foo,bar,baz

[FORMAT]
max-line-length=100
EOF
            fi
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

# Create Python command wrappers
create_python_wrappers() {
    log "INFO" "Creating Python command wrappers..." "python"
    
    local bin_dir=$(get_module_config "python" ".shell.paths.bin_dir")
    bin_dir=$(eval echo "$bin_dir")
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    venv_dir=$(eval echo "$venv_dir")
    
    mkdir -p "$bin_dir"
    
    # Python wrapper
    cat > "$bin_dir/py" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run Python in container
    devenv-container exec python python "\$@"
elif [ -f "$venv_dir/bin/python" ]; then
    # Run Python from virtual environment
    "$venv_dir/bin/python" "\$@"
else
    # Fallback to system Python as last resort
    python3 "\$@"
fi
EOF
    chmod +x "$bin_dir/py"
    
    # Pip wrapper
    cat > "$bin_dir/py-pip" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run pip in container
    devenv-container exec python pip "\$@"
elif [ -f "$venv_dir/bin/pip" ]; then
    # Run pip from virtual environment
    "$venv_dir/bin/pip" "\$@"
else
    # Fallback to system pip as last resort
    python3 -m pip "\$@"
fi
EOF
    chmod +x "$bin_dir/py-pip"
    
    # Venv wrapper
    cat > "$bin_dir/py-venv" << EOF
#!/bin/bash

if [ -z "\$1" ]; then
    echo "Usage: \$0 <venv_name>"
    exit 1
fi

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Create venv in container
    devenv-container exec python python -m venv "\$1"
elif [ -f "$venv_dir/bin/python" ]; then
    # Create venv using Python from main virtual environment
    "$venv_dir/bin/python" -m venv "\$1"
else
    # Create venv using system Python
    python3 -m venv "\$1"
fi
EOF
    chmod +x "$bin_dir/py-venv"
    
    # IPython wrapper
    cat > "$bin_dir/py-ipython" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run IPython in container
    devenv-container exec python ipython "\$@"
elif [ -f "$venv_dir/bin/ipython" ]; then
    # Run IPython from virtual environment
    "$venv_dir/bin/ipython" "\$@"
else
    echo "IPython not installed. Run 'py-pip install ipython' to install it."
    exit 1
fi
EOF
    chmod +x "$bin_dir/py-ipython"
    
    # Jupyter wrapper
    cat > "$bin_dir/py-jupyter" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Start Jupyter in container with port forwarding
    docker exec -it -p 8888:8888 devenv-python jupyter lab --ip 0.0.0.0 --no-browser
elif [ -f "$venv_dir/bin/jupyter" ]; then
    # Run Jupyter from virtual environment
    "$venv_dir/bin/jupyter" lab "\$@"
else
    echo "Jupyter not installed. Run 'py-pip install jupyterlab' to install it."
    exit 1
fi
EOF
    chmod +x "$bin_dir/py-jupyter"
    
    # Black formatter wrapper
    cat > "$bin_dir/py-fmt" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run Black in container
    devenv-container exec python black "\$@"
elif [ -f "$venv_dir/bin/black" ]; then
    # Run Black from virtual environment
    "$venv_dir/bin/black" "\$@"
else
    echo "Black not installed. Run 'py-pip install black' to install it."
    exit 1
fi
EOF
    chmod +x "$bin_dir/py-fmt"
    
    # Pylint wrapper
    cat > "$bin_dir/py-lint" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run Pylint in container
    devenv-container exec python pylint "\$@"
elif [ -f "$venv_dir/bin/pylint" ]; then
    # Run Pylint from virtual environment
    "$venv_dir/bin/pylint" "\$@"
else
    echo "Pylint not installed. Run 'py-pip install pylint' to install it."
    exit 1
fi
EOF
    chmod +x "$bin_dir/py-lint"
    
    # MyPy wrapper
    cat > "$bin_dir/py-mypy" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run MyPy in container
    devenv-container exec python mypy "\$@"
elif [ -f "$venv_dir/bin/mypy" ]; then
    # Run MyPy from virtual environment
    "$venv_dir/bin/mypy" "\$@"
else
    echo "MyPy not installed. Run 'py-pip install mypy' to install it."
    exit 1
fi
EOF
    chmod +x "$bin_dir/py-mypy"
    
    # PyTest wrapper
    cat > "$bin_dir/py-test" << EOF
#!/bin/bash

# Check if Python is containerized
if command -v devenv-container &>/dev/null && type should_containerize &>/dev/null && should_containerize "python" && \\
   docker ps -q --filter "name=devenv-python" &>/dev/null; then
    # Run PyTest in container
    devenv-container exec python pytest "\$@"
elif [ -f "$venv_dir/bin/pytest" ]; then
    # Run PyTest from virtual environment
    "$venv_dir/bin/pytest" "\$@"
else
    echo "PyTest not installed. Run 'py-pip install pytest' to install it."
    exit 1
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
    
    if ! should_use_container "python"; then
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
            venv_dir=$(eval echo "$venv_dir")
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
        
        if command -v devenv-container &>/dev/null; then
            devenv-container stop python
            docker rm -f devenv-python 2>/dev/null
        fi
    fi
    
    # Remove virtual environment
    local venv_dir=$(get_module_config "python" ".shell.paths.venv_dir")
    venv_dir=$(eval echo "$venv_dir")
    if [[ -d "$venv_dir" ]]; then
        log "INFO" "Removing Python virtual environment..." "python"
        rm -rf "$venv_dir"
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