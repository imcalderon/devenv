#!/usr/bin/env bash
# Test bootstrap script functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Testing vfx-bootstrap scripts..."
echo "================================"

# Test 1: Check bootstrap.sh syntax
echo -n "Test 1: bootstrap.sh syntax... "
if bash -n "$PROJECT_ROOT/bootstrap/bootstrap.sh"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 2: Check platform scripts syntax
echo -n "Test 2: Platform scripts syntax... "
for script in "$PROJECT_ROOT"/bootstrap/platforms/*.sh; do
    if ! bash -n "$script"; then
        echo "FAIL ($script)"
        exit 1
    fi
done
echo "PASS"

# Test 3: Check module scripts syntax
echo -n "Test 3: Module scripts syntax... "
for script in "$PROJECT_ROOT"/bootstrap/modules/*.sh; do
    if ! bash -n "$script"; then
        echo "FAIL ($script)"
        exit 1
    fi
done
echo "PASS"

# Test 4: Check recipe build scripts syntax
echo -n "Test 4: Recipe build.sh scripts syntax... "
for script in "$PROJECT_ROOT"/recipes/*/build.sh; do
    if [[ -f "$script" ]]; then
        if ! bash -n "$script"; then
            echo "FAIL ($script)"
            exit 1
        fi
    fi
done
echo "PASS"

echo ""
echo "All bootstrap tests passed!"
