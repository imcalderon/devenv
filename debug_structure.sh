#!/bin/bash
# debug_structure.sh - Debug helper for system structure

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/lib/yaml_parser.sh"
source "$SCRIPT_DIR/lib/logging.sh"

echo "=== System Structure Check ==="
echo ""

echo "1. Directory Structure:"
echo "----------------------"
tree "$SCRIPT_DIR" -L 3

echo ""
echo "2. Config File Check:"
echo "-------------------"
if [ -f "$SCRIPT_DIR/config.yaml" ]; then
    echo "[OK] config.yaml found"
    echo "Enabled modules in config:"
    for module in $(get_enabled_modules "$SCRIPT_DIR/config.yaml"); do
        echo "  - $module"
    done
else
    echo "[ERROR] config.yaml not found!"
fi

echo ""
echo "3. Module Script Check:"
echo "---------------------"
for module in $(get_enabled_modules "$SCRIPT_DIR/config.yaml"); do
    script_path="$SCRIPT_DIR/lib/$module/$module.sh"
    if [ -f "$script_path" ] && [ -x "$script_path" ]; then
        echo "[OK] Found and executable: $script_path"
    elif [ -f "$script_path" ]; then
        echo "[WARN] Found but not executable: $script_path"
        echo "      Fix with: chmod +x $script_path"
    else
        echo "[ERROR] Not found: $script_path"
        echo "        Expected location: $script_path"
    fi
done

echo ""
echo "4. Permission Check:"
echo "------------------"
for script in $(find "$SCRIPT_DIR/lib" -name "*.sh"); do
    if [ -x "$script" ]; then
        echo "[OK] Executable: $script"
    else
        echo "[WARN] Not executable: $script"
        echo "      Fix with: chmod +x $script"
    fi
done