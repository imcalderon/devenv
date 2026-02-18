#!/usr/bin/env bats
# tests/modules/vfx.bats - VFX module tests (consolidated repo)

setup() {
    # Set up test environment
    export TEST_DIR="$(mktemp -d)"
    export HOME="$TEST_DIR/home"
    export DEVENV_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export DEVENV_DATA_DIR="$HOME/.devenv"
    export SCRIPT_DIR="$DEVENV_ROOT/lib"
    export MODULES_DIR="$DEVENV_ROOT/modules"
    export CONFIG_FILE="$DEVENV_ROOT/config.json"

    mkdir -p "$HOME"
    mkdir -p "$HOME/.devenv/state"
    mkdir -p "$HOME/.config/zsh/modules"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- Config validation tests ---

@test "vfx module config.json is valid JSON" {
    run jq empty "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
}

@test "vfx module config has correct runlevel" {
    run jq -r '.runlevel' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "vfx module config has required dependencies" {
    run jq -r '.dependencies[]' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "conda"
    echo "$output" | grep -q "docker"
    echo "$output" | grep -q "git"
}

@test "vfx module config has conda env name" {
    run jq -r '.conda.env_name' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    [ "$output" = "vfx-build" ]
}

@test "vfx module config has VFX Platform versions" {
    run jq -r '.vfx_platform | keys[]' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "2024"
    echo "$output" | grep -q "2025"
}

@test "vfx module config has vfx aliases" {
    run jq -r '.shell.aliases.vfx | keys[]' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "vfx-build"
    echo "$output" | grep -q "vfx-package"
    echo "$output" | grep -q "vfx-list"
}

@test "vfx module config has recipe aliases" {
    run jq -r '.shell.aliases.recipes | keys[]' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "vfx-recipe"
    echo "$output" | grep -q "vfx-deps"
}

@test "vfx aliases use conda run prefix" {
    local build_cmd
    build_cmd=$(jq -r '.shell.aliases.vfx."vfx-build"' "$DEVENV_ROOT/modules/vfx/config.json")
    [[ "$build_cmd" == *"conda run"* ]]
    [[ "$build_cmd" == *"vfx-build"* ]]
}

@test "vfx module config has build deps for linux" {
    run jq -r '.build_deps.linux.apt[]' "$DEVENV_ROOT/modules/vfx/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "cmake"
    echo "$output" | grep -q "ninja-build"
}

# --- Top-level config tests ---

@test "config.json is valid JSON" {
    run jq empty "$DEVENV_ROOT/config.json"
    [ "$status" -eq 0 ]
}

@test "config has vfx_platform template" {
    run jq -r '.templates.vfx_platform.description' "$DEVENV_ROOT/config.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VFX"* ]]
}

@test "vfx_platform template includes vfx module" {
    run jq -r '.templates.vfx_platform.modules.linux[]' "$DEVENV_ROOT/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "vfx"
    echo "$output" | grep -q "conda"
}

@test "vfx is in linux module order" {
    run jq -r '.platforms.linux.modules.order[]' "$DEVENV_ROOT/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "vfx"
}

@test "vfx is in linux available modules" {
    run jq -r '.platforms.linux.modules.available[]' "$DEVENV_ROOT/config.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "vfx"
}

# --- Script tests ---

@test "vfx.sh exists" {
    [ -f "$DEVENV_ROOT/modules/vfx/vfx.sh" ]
}

@test "vfx.sh has correct shebang" {
    head -1 "$DEVENV_ROOT/modules/vfx/vfx.sh" | grep -q "#!/bin/bash"
}

@test "devenv entry point exists and is executable" {
    [ -x "$DEVENV_ROOT/devenv" ]
}

# --- Consolidated structure tests ---

@test "vfx-bootstrap exists under toolkits" {
    [ -d "$DEVENV_ROOT/toolkits/vfx-bootstrap" ]
    [ -f "$DEVENV_ROOT/toolkits/vfx-bootstrap/setup.py" ]
}

@test "vfx-bootstrap has builder module" {
    [ -d "$DEVENV_ROOT/toolkits/vfx-bootstrap/builder" ]
}

@test "vfx-bootstrap has packager module" {
    [ -d "$DEVENV_ROOT/toolkits/vfx-bootstrap/packager" ]
}

@test "vfx-bootstrap has recipes" {
    [ -d "$DEVENV_ROOT/toolkits/vfx-bootstrap/recipes" ]
}

# --- VFX Platform version spec tests ---

@test "VFX 2024 has required specs" {
    for key in python boost tbb openexr usd; do
        run jq -r ".vfx_platform.\"2024\".${key}" "$DEVENV_ROOT/modules/vfx/config.json"
        [ "$status" -eq 0 ]
        [ "$output" != "null" ]
    done
}

@test "VFX 2025 has required specs" {
    for key in python boost tbb openexr usd; do
        run jq -r ".vfx_platform.\"2025\".${key}" "$DEVENV_ROOT/modules/vfx/config.json"
        [ "$status" -eq 0 ]
        [ "$output" != "null" ]
    done
}

# --- Bootstrap path test ---

@test "vfx.sh references toolkits/vfx-bootstrap path" {
    grep -q "toolkits/vfx-bootstrap" "$DEVENV_ROOT/modules/vfx/vfx.sh"
}
