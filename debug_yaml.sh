#!/bin/bash
# debug_yaml.sh - YAML configuration debugger

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/yaml_parser.sh"

echo "=== YAML Configuration Debug ==="
echo ""

# Check raw enabled status for all modules
echo "1. Raw Module Status:"
echo "-------------------"
if [ -f "$SCRIPT_DIR/config.yaml" ]; then
    parse_yaml "$SCRIPT_DIR/config.yaml" | grep "_enabled="
else
    echo "[ERROR] config.yaml not found"
fi

echo ""
echo "2. Module Configuration Sections:"
echo "------------------------------"
if [ -f "$SCRIPT_DIR/config.yaml" ]; then
    grep -A1 "^[[:space:]]*[a-zA-Z]" "$SCRIPT_DIR/config.yaml" | grep -B1 "enabled:"
else
    echo "[ERROR] config.yaml not found"
fi