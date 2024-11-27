#!/bin/bash

# Check if module name is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <module_name>"
    exit 1
fi

MODULE_NAME="$1"
MODULE_DIR="$ROOT_DIR/modules/$MODULE_NAME"

# Create module directory
mkdir -p "$MODULE_DIR"

# Copy and customize template
sed "s/example/$MODULE_NAME/g" "$ROOT_DIR/templates/module.sh" > "$MODULE_DIR/$MODULE_NAME.sh"

# Create initial config.json
cat > "$MODULE_DIR/config.json" << EOF
{
    "enabled": true,
    "runlevel": 1,
    "backup": {
        "paths": []
    },
    "shell": {
        "paths": {},
        "aliases": {}
    }
}
EOF

chmod +x "$MODULE_DIR/$MODULE_NAME.sh"
echo "Created new module: $MODULE_NAME"
echo "Please edit $MODULE_DIR/$MODULE_NAME.sh and $MODULE_DIR/config.json to customize"