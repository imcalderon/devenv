#!/bin/bash
# modules/react/react.sh - React module implementation

# Load required utilities
source "$SCRIPT_DIR/compat.sh"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "react" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/react.state"

# Define module components
COMPONENTS=(
    "core"          # Base React tooling
    "typescript"    # TypeScript support
    "testing"       # Testing frameworks
    "storybook"     # Component development
    "tooling"       # Development tools
)

# Display module information
show_module_info() {
    cat << 'EOF'

⚛️ React Development Environment
===========================

Description:
-----------
Complete React development environment with TypeScript,
testing frameworks, and component development tools.

Components:
----------
1. Core React
   - Create React App
   - React Router
   - State Management

2. TypeScript Configuration
   - Strict type checking
   - Path aliases
   - Type definitions

3. Testing Framework
   - Jest
   - React Testing Library
   - MSW for mocking

4. Development Tools
   - Storybook
   - Chrome DevTools
   - React DevTools

Quick Start:
-----------
1. Create project:
   $ cra my-app

2. Start development:
   $ rstart

3. Run tests:
   $ rtest

4. Build project:
   $ rbuild

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    if command -v create-react-app &>/dev/null; then
                        echo "  CRA Version: $(create-react-app --version)"
                    fi
                    ;;
                "storybook")
                    if command -v storybook &>/dev/null; then
                        echo "  Storybook Version: $(storybook --version)"
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
            command -v create-react-app &>/dev/null && \
            command -v react-scripts &>/dev/null
            ;;
        "typescript")
            command -v tsc &>/dev/null
            ;;
        "testing")
            verify_testing_setup
            ;;
        "storybook")
            command -v storybook &>/dev/null
            ;;
        "tooling")
            verify_tooling_setup
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Verify testing setup
verify_testing_setup() {
    npm list --global jest &>/dev/null && \
    npm list --global @testing-library/react &>/dev/null && \
    npm list --global msw &>/dev/null
}

# Verify tooling setup
verify_tooling_setup() {
    npm list --global eslint &>/dev/null && \
    npm list --global prettier &>/dev/null && \
    verify_vscode_extensions
}

# Verify VSCode extensions
verify_vscode_extensions() {
    command -v code &>/dev/null || return 0
    
    local required_extensions=(
        "dbaeumer.vscode-eslint"
        "esbenp.prettier-vscode"
        "dsznajder.es7-react-js-snippets"
        "ms-vscode.vscode-typescript-next"
    )
    
    for ext in "${required_extensions[@]}"; do
        code --list-extensions | grep -q "^$ext$" || return 1
    done
    return 0
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "react"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_core_react; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "typescript")
            if install_typescript; then
                save_state "typescript" "installed"
                return 0
            fi
            ;;
        "testing")
            if install_testing; then
                save_state "testing" "installed"
                return 0
            fi
            ;;
        "storybook")
            if install_storybook; then
                save_state "storybook" "installed"
                return 0
            fi
            ;;
        "tooling")
            if install_tooling; then
                save_state "tooling" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Install core React tooling
install_core_react() {
    log "INFO" "Installing core React tools..." "react"
    
    # Install updated dependencies
    npm install -g create-react-app@latest react-scripts@latest || return 1
    
    # Create npmrc to handle legacy peer deps
    echo "legacy-peer-deps=true" > "$HOME/.npmrc"
    
    # Add aliases
    add_module_aliases "react" "core" || return 1
    
    return 0
}

# Install TypeScript support
install_typescript() {
    log "INFO" "Installing TypeScript support..." "react"
    
    npm install -g typescript @types/react @types/react-dom || return 1
    
    # Configure TypeScript defaults
    create_tsconfig || return 1
    
    return 0
}

# Install testing frameworks
install_testing() {
    log "INFO" "Installing testing frameworks..." "react"
    
    npm install -g \
        jest \
        @testing-library/react \
        @testing-library/jest-dom \
        @testing-library/user-event \
        msw || return 1
    
    # Add testing aliases
    add_module_aliases "react" "testing" || return 1
    
    return 0
}

# Install Storybook
install_storybook() {
    log "INFO" "Installing Storybook..." "react"
    
    npm install -g storybook @storybook/react || return 1
    
    # Add Storybook aliases
    add_module_aliases "react" "storybook" || return 1
    
    return 0
}

# Install development tooling
install_tooling() {
    log "INFO" "Installing development tools..." "react"
    
    # Install updated ESLint and related packages
    npm install -g \
        @eslint/config-array \
        @eslint/object-schema \
        eslint@latest \
        prettier@latest \
        eslint-config-react-app@latest \
        eslint-plugin-react@latest \
        eslint-plugin-react-hooks@latest || return 1
    
    # Install updated Babel plugins
    npm install -g \
        @babel/plugin-transform-private-methods \
        @babel/plugin-transform-numeric-separator \
        @babel/plugin-transform-optional-chaining \
        @babel/plugin-transform-nullish-coalescing-operator \
        @babel/plugin-transform-class-properties || return 1
    
    install_vscode_extensions || return 1
    create_eslint_config || return 1
    create_prettier_config || return 1
    
    return 0
}

# Create TypeScript configuration
create_tsconfig() {
    local tsconfig=$(get_module_config "react" ".typescript.config")
    [[ -z "$tsconfig" ]] && return 0
    
    echo "$tsconfig" > "$HOME/.tsconfig.base.json"
    return 0
}

# Create ESLint configuration
create_eslint_config() {
    local eslint_config=$(get_module_config "react" ".eslint.config")
    [[ -z "$eslint_config" ]] && return 0
    
    echo "$eslint_config" > "$HOME/.eslintrc.base.json"
    return 0
}

# Create Prettier configuration
create_prettier_config() {
    local prettier_config=$(get_module_config "react" ".prettier.config")
    [[ -z "$prettier_config" ]] && return 0
    
    echo "$prettier_config" > "$HOME/.prettierrc.base.json"
    return 0
}

# Install VSCode extensions
install_vscode_extensions() {
    [[ ! -x "$(command -v code)" ]] && return 0
    
    local extensions=($(get_module_config "react" ".vscode.extensions[]"))
    for ext in "${extensions[@]}"; do
        code --install-extension "$ext" --force
    done
    
    return 0
}

# Grovel checks existence and basic functionality
grovel_react() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "react"
            status=1
        fi
    done
    
    return $status
}

# Install with state awareness
install_react() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_react &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "react"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "react"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "react"
        fi
    done
    
    # Show module information after successful installation
    show_module_info
    
    return 0
}

# Remove React configuration
remove_react() {
    log "INFO" "Removing React configuration..." "react"

    # Backup existing configurations
    backup_file "$HOME/.tsconfig.base.json" "react"
    backup_file "$HOME/.eslintrc.base.json" "react"
    backup_file "$HOME/.prettierrc.base.json" "react"

    # Remove configurations
    rm -f "$HOME/.tsconfig.base.json"
    rm -f "$HOME/.eslintrc.base.json"
    rm -f "$HOME/.prettierrc.base.json"

    # Remove aliases
    remove_module_aliases "react" "core"
    remove_module_aliases "react" "testing"
    remove_module_aliases "react" "storybook"

    # Remove global packages
    npm uninstall -g create-react-app react-scripts typescript storybook

    # Remove state file
    rm -f "$STATE_FILE"

    return 0
}

# Verify entire installation
verify_react() {
    log "INFO" "Verifying React installation..." "react"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "react"
            status=1
        fi
    done
    
    return $status
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_react
        ;;
    install)
        install_react "${2:-false}"  # Optional force parameter
        ;;
    verify)
        verify_react
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_react
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "react"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac