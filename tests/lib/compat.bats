#!/usr/bin/env bats
# Tests for lib/compat.sh

setup() {
    load '../test_helper'
}

@test "sed_inplace is defined as a function" {
    type sed_inplace | grep -q "function"
}

@test "sed_inplace replaces text in a file" {
    local tmpfile
    tmpfile=$(mktemp)
    echo "hello world" > "$tmpfile"

    sed_inplace 's/hello/goodbye/' "$tmpfile"

    result=$(cat "$tmpfile")
    [ "$result" = "goodbye world" ]
    rm -f "$tmpfile"
}

@test "sed_inplace handles multiple replacements" {
    local tmpfile
    tmpfile=$(mktemp)
    printf "line1\nline2\nline3\n" > "$tmpfile"

    sed_inplace '/line2/d' "$tmpfile"

    result=$(cat "$tmpfile")
    [ "$result" = "$(printf 'line1\nline3')" ]
    rm -f "$tmpfile"
}

@test "expand_vars is defined as a function" {
    type expand_vars | grep -q "function"
}

@test "expand_vars expands simple variables" {
    export TEST_VAR="expanded_value"

    result=$(echo '$TEST_VAR' | expand_vars)
    [ "$result" = "expanded_value" ]

    unset TEST_VAR
}

@test "expand_vars expands braced variables" {
    export TEST_VAR="braced_value"

    result=$(echo '${TEST_VAR}' | expand_vars)
    [ "$result" = "braced_value" ]

    unset TEST_VAR
}

@test "expand_vars preserves text without variables" {
    result=$(echo 'no variables here' | expand_vars)
    [ "$result" = "no variables here" ]
}

@test "expand_vars handles empty variables" {
    unset NONEXISTENT_VAR 2>/dev/null || true

    result=$(echo '${NONEXISTENT_VAR}' | expand_vars)
    [ "$result" = "" ]
}

@test "expand_vars expands paths with mixed content" {
    export MY_HOME="/home/testuser"

    result=$(echo '${MY_HOME}/.config/devenv' | expand_vars)
    [ "$result" = "/home/testuser/.config/devenv" ]

    unset MY_HOME
}
