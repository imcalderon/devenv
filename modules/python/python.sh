#!/bin/bash
# modules/python/python.sh - Python module implementation

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

# Display module information
show_module_info() {
    cat << 'EOF'

🐍 Python Development Environment
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
   $ fmt myfile.py

2. Run linting:
   $ lint myfile.py

3. Start Jupyter:
   $ jlab

4. Run Python:
   $ py script.py

Aliases:
-------
py     : python3              - Run Python interpreter
ipy    : ipython             - Enhanced Python REPL
pylab  : ipython --pylab     - IPython with plotting
jlab   : jupyter lab         - Start Jupyter Lab
lint   : pylint              - Run code linting
fmt    : black               - Format code
mypy   : mypy                - Type checking
pytest : pytest -v           - Run tests verbosely

Configuration:
-------------
Location: ~/.config/python
Key files:
- pylintrc       : Linting configuration
- pyproject.toml : Black and tool settings
- flake8         : Style checking rules

Tips:
----
• Use virtual environments for project isolation
• Run fmt before lint for best results
• Check types with mypy for better code quality
• Use pytest -v for detailed test output

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    local components=("core" "dev-tools" "code-quality" "data-science")
    local python_version=""
    
    if command -v python3 &>/dev/null; then
        python_version=$(python3 --version 2>/dev/null)
    fi
    
    for component in "${components[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    [[ -n "$python_version" ]] && echo "  Version: $python_version"
                    ;;
                "dev-tools")
                    if command -v ipython &>/dev/null; then
                        echo "  IPython: $(ipython --version 2>/dev/null)"
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
            command -v python3 &>/dev/null && 
            command -v pip &>/dev/null &&
            python3 -c "import venv" &>/dev/null
            ;;
        "dev-tools")
            python3 -c "import IPython, jupyter, notebook" &>/dev/null
            ;;
        "code-quality")
            python3 -c "import black, pylint, flake8, mypy" &>/dev/null
            ;;
        "data-science")
            python3 -c "import numpy, pandas, scipy" &>/dev/null
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
    
    local local_bin=$(get_module_config "python" ".shell.paths.local_bin")
    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    
    local_bin=$(eval echo "$local_bin")
    config_dir=$(eval echo "$config_dir")
    
    mkdir -p "$local_bin" "$config_dir"
    
    if [[ ! -d "$local_bin" ]] || [[ ! -d "$config_dir" ]]; then
        log "ERROR" "Failed to create required directories" "python"
        return 1
    fi
    
    return 0
}

# Install core Python component
install_core() {
    log "INFO" "Installing core Python..." "python"
    
    # Install Python if needed
    if ! command -v python3 &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip python3-venv python3-dev curl
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y python3 python3-pip python3-devel curl
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

    return 0
}

# Install Python packages by category
install_packages() {
    local category=$1
    local key=$2
    log "INFO" "Installing $category packages..." "python"
    
    local packages=($(get_module_config "python" "$key"))
    if [[ ${#packages[@]} -gt 0 ]]; then
        if ! python3 -m pip install --user --upgrade "${packages[@]}"; then
            log "ERROR" "Failed to install $category packages" "python"
            return 1
        fi
    fi
    
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
            if install_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "dev-tools")
            if install_packages "development" ".python.packages.development[]" && \
               install_packages "build" ".python.packages.build[]"; then
                save_state "dev-tools" "installed"
                return 0
            fi
            ;;
        "code-quality")
            if install_packages "linting" ".python.packages.linting[]" && \
               configure_tools; then
                save_state "code-quality" "installed"
                return 0
            fi
            ;;
        "data-science")
            if install_packages "data processing" ".python.packages.utils.data_processing.packages[]"; then
                save_state "data-science" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Configure development tools
configure_tools() {
    log "INFO" "Configuring Python development tools..." "python"

    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")

    mkdir -p "$config_dir"
    
    # Configure each tool
    configure_pylint "$config_dir" || return 1
    configure_black "$config_dir" || return 1
    configure_flake8 "$config_dir" || return 1
    
    return 0
}

# Install with state awareness
install_python() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_python &>/dev/null; then
        create_backup
    fi
    
    create_directories || return 1
    
    local components=("core" "dev-tools" "code-quality" "data-science")
    for component in "${components[@]}"; do
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
    
    # Add aliases
    add_module_aliases "python" "python" || return 1
    add_module_aliases "python" "tools" || return 1
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Configure tool-specific settings (helper functions)
configure_pylint() {
    local config_dir=$1
    local pylint_config="$config_dir/pylintrc"
    
    if [[ ! -f "$pylint_config" ]]; then
        pylint --generate-rcfile > "$pylint_config"
        
        local disabled_checks=($(get_module_config "python" ".python.config.pylint.disable[]"))
        local good_names=($(get_module_config "python" ".python.config.pylint.good-names[]"))
        local max_line_length=$(get_module_config "python" ".python.config.pylint.max-line-length")
        
        sed -i "s/^disable=.*/disable=$(IFS=,; echo "${disabled_checks[*]}")/" "$pylint_config"
        sed -i "s/^good-names=.*/good-names=$(IFS=,; echo "${good_names[*]}")/" "$pylint_config"
        sed -i "s/^max-line-length=.*/max-line-length=$max_line_length/" "$pylint_config"
    fi
}

configure_black() {
    local config_dir=$1
    local black_config="$config_dir/pyproject.toml"
    
    if [[ ! -f "$black_config" ]]; then
        cat > "$black_config" << EOF
[tool.black]
line-length = $(get_module_config "python" ".python.config.black.line-length")
target-version = ["py310"]
EOF
    fi
}

configure_flake8() {
    local config_dir=$1
    local flake8_config="$config_dir/flake8"
    
    if [[ ! -f "$flake8_config" ]]; then
        cat > "$flake8_config" << EOF
[flake8]
max-line-length = $(get_module_config "python" ".python.config.flake8.max-line-length")
ignore = $(get_module_config "python" ".python.config.flake8.ignore[]" | tr '\n' ',')
EOF
    fi
}

# Grovel checks existence and basic functionality
grovel_python() {
    local status=0
    
    local components=("core" "dev-tools" "code-quality" "data-science")
    for component in "${components[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "python"
            status=1
        fi
    done
    
    return $status
}

# Verify entire installation
verify_python() {
    local status=0
    
    local components=("core" "dev-tools" "code-quality" "data-science")
    for component in "${components[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "python"
            status=1
        fi
    done
    
    # Verify aliases
    if ! list_module_aliases "python" "python" &>/dev/null || \
       ! list_module_aliases "python" "tools" &>/dev/null; then
        log "ERROR" "Python aliases not configured" "python"
        status=1
    fi
    
    return $status
}

# Remove Python configuration
remove_python() {
    log "INFO" "Removing Python configuration..." "python"

    local config_dir=$(get_module_config "python" ".shell.paths.config_dir")
    config_dir=$(eval echo "$config_dir")
    
    # Backup configs
    for file in "$config_dir/pylintrc" "$config_dir/pyproject.toml" "$config_dir/flake8"; do
        [[ -f "$file" ]] && backup_file "$file" "python"
    done

    # Remove configuration files
    rm -f "$config_dir/pylintrc" "$config_dir/pyproject.toml" "$config_dir/flake8"

    # Remove aliases
    remove_module_aliases "python" "python"
    remove_module_aliases "python" "tools"

    # Remove state file
    rm -f "$STATE_FILE"

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