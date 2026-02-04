#!/usr/bin/env bats
# Tests for lib/json.sh

setup() {
    load '../test_helper'
    source "$SCRIPT_DIR/json.sh"
}

@test "get_json_value extracts simple values" {
    local tmpfile
    tmpfile=$(mktemp --suffix=.json)
    echo '{"name": "test", "version": "1.0"}' > "$tmpfile"

    result=$(get_json_value "$tmpfile" ".name")
    [ "$result" = "test" ]

    rm -f "$tmpfile"
}

@test "get_json_value returns default for missing keys" {
    local tmpfile
    tmpfile=$(mktemp --suffix=.json)
    echo '{"name": "test"}' > "$tmpfile"

    result=$(get_json_value "$tmpfile" ".missing" "default_val")
    [ "$result" = "default_val" ]

    rm -f "$tmpfile"
}

@test "get_json_value handles nested values" {
    local tmpfile
    tmpfile=$(mktemp --suffix=.json)
    echo '{"outer": {"inner": "nested_value"}}' > "$tmpfile"

    result=$(get_json_value "$tmpfile" ".outer.inner")
    [ "$result" = "nested_value" ]

    rm -f "$tmpfile"
}

@test "validate_json accepts valid JSON" {
    local tmpfile
    tmpfile=$(mktemp --suffix=.json)
    echo '{"valid": true}' > "$tmpfile"

    run validate_json "$tmpfile"
    [ "$status" -eq 0 ]

    rm -f "$tmpfile"
}

@test "validate_json rejects invalid JSON" {
    local tmpfile
    tmpfile=$(mktemp --suffix=.json)
    echo '{invalid json' > "$tmpfile"

    run validate_json "$tmpfile"
    [ "$status" -ne 0 ]

    rm -f "$tmpfile"
}
