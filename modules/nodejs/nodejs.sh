#!/bin/bash
# modules/nodejs/nodejs.sh - Node.js module implementation

# Load required utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/module.sh"
source "$SCRIPT_DIR/backup.sh"
source "$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "nodejs" || exit 1

# State file for tracking installation status
STATE_FILE="$HOME/.devenv/state/nodejs.state"

# Define module components
COMPONENTS=(
    "core"          # Base Node.js installation
    "nvm"           # Node Version Manager
    "packages"      # Global npm packages
    "config"        # Node.js configuration
)

# Display module information
show_module_info() {
    cat << 'EOF'

📦 Node.js Development Environment
==============================

Description:
-----------
Professional Node.js development environment with NVM, package management,
and essential development tools.

Benefits:
--------
✓ Version Management - NVM for multiple Node.js versions
✓ Package Management - NPM configuration and global tools
✓ Build Tools - Development essentials like webpack, babel
✓ Testing Framework - Jest and testing utilities

Components:
----------
1. Core Node.js
   - Latest LTS version
   - NPM package manager
   - NVM for version management

2. Global Packages
   - webpack/webpack-cli
   - babel-cli
   - eslint
   - prettier
   - grunt-cli

Quick Start:
-----------
1. Select Node version:
   $ nvm use 16

2. Install package:
   $ npm install

3. Run development:
   $ npm run dev

Aliases:
-------
n     : node
ni    : npm install
nr    : npm run
nrd   : npm run dev
nrb   : npm run build

Configuration:
-------------
Location: ~/.npmrc
Key files:
- .npmrc       : NPM configuration
- .nvmrc       : Node version file
- package.json : Project configuration

EOF

    # Show current installation status
    echo "Current Status:"
    echo "-------------"
    for component in "${COMPONENTS[@]}"; do
        if check_state "$component"; then
            echo "✓ $component: Installed"
            case "$component" in
                "core")
                    ensure_nvm_loaded
                    if command -v node &>/dev/null; then
                        echo "  Version: $(node --version)"
                    fi
                    ;;
                "nvm")
                    ensure_nvm_loaded
                    if command -v nvm &>/dev/null; then
                        echo "  NVM: $(nvm --version)"
                    fi
                    ;;
            esac
        else
            echo "✗ $component: Not installed"
        fi
    done
    echo
}
grovel_nodejs() {
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Component $component needs installation" "nodejs"
            status=1
        fi
    done
    
    return $status
}


# Install core Node.js and NVM
install_core() {
    # Install NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    
    # Load NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Install latest LTS version
    nvm install --lts
    nvm use --lts
    
    # Update npm
    npm install -g npm@latest
    
    return 0
}

# Install global packages
install_packages() {
    npm install -g webpack webpack-cli @babel/core @babel/cli eslint prettier grunt-cli
    return 0
}

# Configure Node.js
configure_nodejs() {
    # Configure npm
    npm config set save-exact true
    npm config set package-lock true
    
    # Add aliases
    add_module_aliases "nodejs" "npm" || return 1
    
    return 0
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
# Additional verification helper for package existence
verify_global_package() {
    local package=$1
    npm list -g "$package" &>/dev/null
}

# Additional verification helper for npm configuration
verify_npm_config() {
    local key=$1
    local expected=$2
    local value=$(npm config get "$key")
    [[ "$value" == "$expected" ]]
}
# Ensure NVM is loaded into the current shell session
ensure_nvm_loaded() {
    if command -v nvm &>/dev/null; then
        return 0
    fi
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        \. "$NVM_DIR/nvm.sh"
        return 0
    fi
    return 1
}

# Verify specific component
verify_component() {
    local component=$1
    case "$component" in
        "core")
            ensure_nvm_loaded
            command -v node &>/dev/null && command -v npm &>/dev/null
            ;;
        "nvm")
            ensure_nvm_loaded
            ;;
        "packages")
            # Check each required global package
            local packages=(webpack webpack-cli eslint prettier grunt-cli)
            for package in "${packages[@]}"; do
                if ! verify_global_package "$package"; then
                    return 1
                fi
            done
            return 0
            ;;
        "config")
            # Verify npm configuration settings
            [[ -f "$HOME/.npmrc" ]] && \
            verify_npm_config "save-exact" "true" && \
            verify_npm_config "package-lock" "true"
            ;;
        *)
            return 1
            ;;
    esac
    return $?
}

# Install specific component
install_component() {
    local component=$1
    if check_state "$component" && verify_component "$component"; then
        log "INFO" "Component $component already installed and verified" "nodejs"
        return 0
    fi
    
    case "$component" in
        "core")
            if install_core; then
                save_state "core" "installed"
                return 0
            fi
            ;;
        "nvm")
            # NVM is installed with core
            save_state "nvm" "installed"
            return 0
            ;;
        "packages")
            if install_packages; then
                save_state "packages" "installed"
                return 0
            fi
            ;;
        "config")
            if configure_nodejs; then
                save_state "config" "installed"
                return 0
            fi
            ;;
    esac
    return 1
}

# Main installation function
install_nodejs() {
    local force=${1:-false}
    
    if [[ "$force" == "true" ]] || ! grovel_nodejs &>/dev/null; then
        create_backup
    fi
    
    for component in "${COMPONENTS[@]}"; do
        if [[ "$force" == "true" ]] || ! check_state "$component" || ! verify_component "$component"; then
            log "INFO" "Installing component: $component" "nodejs"
            if ! install_component "$component"; then
                log "ERROR" "Failed to install component: $component" "nodejs"
                return 1
            fi
        else
            log "INFO" "Skipping already installed and verified component: $component" "nodejs"
        fi
    done
    
    show_module_info
    return 0
}
# Verify entire installation
verify_nodejs() {
    log "INFO" "Verifying Node.js installation..." "nodejs"
    local status=0
    
    for component in "${COMPONENTS[@]}"; do
        if ! verify_component "$component"; then
            log "ERROR" "Verification failed for component: $component" "nodejs"
            status=1
        fi
    done
    
    if [ $status -eq 0 ]; then
        log "INFO" "Node.js verification completed successfully" "nodejs"
        # Show installation details
        node --version
        npm --version
        nvm --version
    fi

    return $status
}


# Remove Node.js configuration
remove_nodejs() {
    log "INFO" "Removing Node.js configuration..." "nodejs"

    # Backup existing configurations
    [[ -f "$HOME/.npmrc" ]] && backup_file "$HOME/.npmrc" "nodejs"
    [[ -f "$HOME/.nvmrc" ]] && backup_file "$HOME/.nvmrc" "nodejs"

    # Remove global packages
    local packages=(webpack webpack-cli @babel/core @babel/cli eslint prettier grunt-cli)
    for package in "${packages[@]}"; do
        if verify_global_package "$package"; then
            npm uninstall -g "$package"
        fi
    done

    # Remove npm configuration
    npm config delete save-exact
    npm config delete package-lock

    # Remove aliases
    remove_module_aliases "nodejs" "npm"

    # Remove state file
    rm -f "$STATE_FILE"

    # Note: We don't remove NVM or Node.js itself for safety
    log "WARN" "NVM and Node.js were preserved. Run 'rm -rf ~/.nvm' to remove NVM completely." "nodejs"

    return 0
}

# Execute requested action
case "${1:-}" in
    grovel)
        grovel_nodejs
        ;;
    install)
        install_nodejs "${2:-false}"
        ;;
    verify)
        verify_nodejs
        ;;
    info)
        show_module_info
        ;;
    remove)
        remove_nodejs
        ;;
    *)
        log "ERROR" "Unknown action: ${1:-}" "nodejs"
        log "ERROR" "Usage: $0 {install|remove|verify|info} [--force]"
        exit 1
        ;;
esac