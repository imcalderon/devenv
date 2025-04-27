#!/bin/bash
# generate.sh - Cross-platform module generator

# Detect platform
detect_platform() {
    local platform="unknown"
    case "$(uname -s)" in
        Linux*)     platform="linux";;
        Darwin*)    platform="darwin";;
        CYGWIN*)    platform="windows";;
        MINGW*)     platform="windows";;
        MSYS*)      platform="windows";;
        *)          platform="unknown";;
    esac
    
    # Additional check for Windows environment
    if [[ "$platform" == "unknown" && -n "$WINDIR" ]]; then
        platform="windows"
    fi
    
    echo "$platform"
}

# Get absolute path of script
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$( cd -P "$( dirname "$source" )" && pwd )"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    local dir="$( cd -P "$( dirname "$source" )" && pwd )"
    echo "$dir"
}

# Check if module name is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <module_name>"
    exit 1
fi

MODULE_NAME="$1"

# Get script directory
SCRIPT_DIR=$(get_script_dir)
ROOT_DIR="$SCRIPT_DIR"
MODULE_DIR="$ROOT_DIR/modules/$MODULE_NAME"

# Create module directory
mkdir -p "$MODULE_DIR"

# Create directories for platform-specific implementations
mkdir -p "$MODULE_DIR/linux"
mkdir -p "$MODULE_DIR/darwin"
mkdir -p "$MODULE_DIR/windows"

# Create config.json from template
CONFIG_TEMPLATE="$ROOT_DIR/scripts/templates/modules/config.template.json"
CONFIG_FILE="$MODULE_DIR/config.json"

if [ -f "$CONFIG_TEMPLATE" ]; then
    # Replace placeholders in template
    sed "s/{{MODULE_NAME}}/$MODULE_NAME/g" "$CONFIG_TEMPLATE" > "$CONFIG_FILE"
else
    echo "Warning: Module template not found at $CONFIG_TEMPLATE"
    echo "Creating basic config.json..."
    
    # Create a basic config.json
    cat > "$CONFIG_FILE" << EOF
{
    "enabled": true,
    "runlevel": 3,
    "backup": {
        "paths": []
    },
    "global": {
        "shell": {
            "paths": {},
            "aliases": {}
        }
    },
    "platforms": {
        "linux": {
            "enabled": true
        },
        "darwin": {
            "enabled": true
        },
        "windows": {
            "enabled": true
        }
    }
}
EOF
fi

# Create platform-specific implementation scripts
BASH_TEMPLATE="$ROOT_DIR/scripts/templates/modules/module.sh"
PS1_TEMPLATE="$ROOT_DIR/scripts/templates/modules/module.ps1"

# Create bash implementation for Linux and macOS
if [ -f "$BASH_TEMPLATE" ]; then
    sed "s/example/$MODULE_NAME/g" "$BASH_TEMPLATE" > "$MODULE_DIR/$MODULE_NAME.sh"
    chmod +x "$MODULE_DIR/$MODULE_NAME.sh"
    
    # Create symbolic links for platform-specific implementations
    ln -sf "../$MODULE_NAME.sh" "$MODULE_DIR/linux/$MODULE_NAME.sh"
    ln -sf "../$MODULE_NAME.sh" "$MODULE_DIR/darwin/$MODULE_NAME.sh"
else
    echo "Warning: Bash module template not found at $BASH_TEMPLATE"
    echo "Creating basic shell implementation..."
    
    # Create basic shell implementation
    cat > "$MODULE_DIR/$MODULE_NAME.sh" << EOF
#!/bin/bash
# modules/$MODULE_NAME/$MODULE_NAME.sh - $MODULE_NAME module implementation

# Load required utilities
source "\$SCRIPT_DIR/logging.sh"
source "\$SCRIPT_DIR/json.sh"
source "\$SCRIPT_DIR/module.sh"
source "\$SCRIPT_DIR/backup.sh"
source "\$SCRIPT_DIR/alias.sh"

# Initialize module
init_module "$MODULE_NAME" || exit 1

# Your module implementation here
case "\${1:-