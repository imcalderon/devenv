#!/bin/bash
# lib/compat.sh - Cross-platform compatibility utilities

# Portable sed in-place editing (handles GNU sed vs BSD sed differences)
# Usage: sed_inplace 'sed-expression' file
sed_inplace() {
    if sed --version 2>/dev/null | grep -q 'GNU'; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# Portable environment variable expansion
# Falls back to a pure-bash implementation if envsubst is not available
expand_vars() {
    if command -v envsubst &>/dev/null; then
        envsubst
    else
        # Pure-bash fallback: expand $VAR and ${VAR} patterns from environment
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            while [[ "$line" =~ \$\{([a-zA-Z_][a-zA-Z_0-9]*)\} ]]; do
                local varname="${BASH_REMATCH[1]}"
                line="${line/\$\{$varname\}/${!varname:-}}"
            done
            while [[ "$line" =~ \$([a-zA-Z_][a-zA-Z_0-9]*) ]]; do
                local varname="${BASH_REMATCH[1]}"
                line="${line/\$$varname/${!varname:-}}"
            done
            printf '%s\n' "$line"
        done
    fi
}
