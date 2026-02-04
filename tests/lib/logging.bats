#!/usr/bin/env bats
# Tests for lib/logging.sh

setup() {
    load '../test_helper'
}

@test "log function exists" {
    type log | grep -q "function"
}

@test "log ERROR writes to stderr" {
    run bash -c 'source "$SCRIPT_DIR/compat.sh" && source "$SCRIPT_DIR/logging.sh" && log "ERROR" "test error" 2>&1'
    [[ "$output" == *"test error"* ]]
}

@test "log respects LOG_LEVEL filtering" {
    export LOG_LEVEL="ERROR"
    # DEBUG should be suppressed when level is ERROR
    run bash -c 'source "$SCRIPT_DIR/compat.sh" && source "$SCRIPT_DIR/logging.sh" && log "DEBUG" "debug msg" 2>&1'
    [[ "$output" != *"debug msg"* ]] || [ -z "$output" ]
}

@test "init_logging creates log directory" {
    local test_dir
    test_dir=$(mktemp -d)
    export DEFAULT_LOG_DIR="$test_dir/logs"

    source "$SCRIPT_DIR/logging.sh"

    [ -d "$test_dir/logs" ]
    rm -rf "$test_dir"
}

@test "LOG_FILE is set after init_logging" {
    source "$SCRIPT_DIR/logging.sh"
    [ -n "$LOG_FILE" ]
}
