#!/bin/bash
# lib/secrets.sh - Secrets management for DevEnv
#
# Provides encrypted storage for credentials and API tokens.
# Uses openssl AES-256-CBC with PBKDF2 for encryption at rest.
# Secrets are stored in ~/.devenv/secrets/ with mode 700.
#
# Environment variable overrides:
#   DEVENV_SECRETS_KEY      - Encryption key (avoids interactive prompt)
#   DEVENV_SECRET_<KEY>     - Override any secret (e.g., DEVENV_SECRET_GIT_EMAIL)

set -euo pipefail

# Secret definitions: name, description, type, prompt
# Types: text, email, token, password
DEVENV_SECRET_DEFS=(
    "git_name|Git user name|text|Enter your Git name"
    "git_email|Git user email|email|Enter your Git email"
    "github_token|GitHub personal access token|token|Enter your GitHub token"
    "anthropic_api_key|Anthropic API key|token|Enter your Anthropic API key"
    "ssh_passphrase|SSH key passphrase|password|Enter SSH key passphrase"
    "docker_hub_token|Docker Hub access token|token|Enter your Docker Hub token"
    "npm_token|NPM auth token|token|Enter your NPM token"
    "pypi_token|PyPI API token|token|Enter your PyPI token"
)

SECRETS_DIR="${DEVENV_DATA_DIR:-$HOME/.devenv}/secrets"

# Initialize secrets directory with secure permissions
init_secrets() {
    if [[ ! -d "$SECRETS_DIR" ]]; then
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        log "INFO" "Initialized secrets directory: $SECRETS_DIR" "secrets"
    fi
}

# Get the encryption key from env var or interactive prompt
get_encryption_key() {
    if [[ -n "${DEVENV_SECRETS_KEY:-}" ]]; then
        echo "$DEVENV_SECRETS_KEY"
        return 0
    fi

    # Interactive prompt
    local key
    read -s -p "Enter secrets encryption key: " key
    echo >&2  # newline after hidden input
    if [[ -z "$key" ]]; then
        log "ERROR" "Encryption key cannot be empty" "secrets"
        return 1
    fi
    echo "$key"
}

# Store an encrypted secret
# Usage: set_secret <key> <value>
set_secret() {
    local key=$1
    local value=$2
    init_secrets

    local enc_key
    enc_key=$(get_encryption_key) || return 1

    local secret_file="$SECRETS_DIR/${key}.enc"
    echo -n "$value" | openssl enc -aes-256-cbc -pbkdf2 -salt \
        -pass "pass:$enc_key" -out "$secret_file" 2>/dev/null
    chmod 600 "$secret_file"
    log "INFO" "Stored secret: $key" "secrets"
}

# Retrieve a decrypted secret
# Usage: get_secret <key> [default]
# Checks env var override first, then encrypted file
get_secret() {
    local key=$1
    local default=${2:-}

    # Check environment variable override: DEVENV_SECRET_<KEY>
    local env_var="DEVENV_SECRET_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
    local env_value="${!env_var:-}"
    if [[ -n "$env_value" ]]; then
        echo "$env_value"
        return 0
    fi

    # Check encrypted file
    local secret_file="$SECRETS_DIR/${key}.enc"
    if [[ ! -f "$secret_file" ]]; then
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        return 1
    fi

    local enc_key
    enc_key=$(get_encryption_key) || return 1

    local value
    value=$(openssl enc -aes-256-cbc -pbkdf2 -d -salt \
        -pass "pass:$enc_key" -in "$secret_file" 2>/dev/null) || {
        log "ERROR" "Failed to decrypt secret: $key (wrong key?)" "secrets"
        return 1
    }
    echo "$value"
}

# Validate a secret value based on type
# Usage: validate_secret <key> <value> <type>
validate_secret() {
    local key=$1
    local value=$2
    local type=$3

    case "$type" in
        email)
            if [[ ! "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                log "WARN" "Invalid email format for $key" "secrets"
                return 1
            fi
            ;;
        token)
            if [[ ${#value} -lt 8 ]]; then
                log "WARN" "Token for $key seems too short (< 8 chars)" "secrets"
                return 1
            fi
            ;;
        password)
            if [[ ${#value} -lt 1 ]]; then
                log "WARN" "Password for $key is empty" "secrets"
                return 1
            fi
            ;;
        text)
            if [[ -z "$value" ]]; then
                log "WARN" "Value for $key is empty" "secrets"
                return 1
            fi
            ;;
    esac
    return 0
}

# Interactive wizard to collect secrets
secrets_wizard() {
    init_secrets
    echo ""
    echo "DevEnv Secrets Wizard"
    echo "====================="
    echo "Configure credentials for your development environment."
    echo "Press Enter to skip any secret, Ctrl+C to abort."
    echo ""

    for def in "${DEVENV_SECRET_DEFS[@]}"; do
        IFS='|' read -r key description type prompt <<< "$def"

        # Check if already stored
        local existing=""
        if [[ -f "$SECRETS_DIR/${key}.enc" ]]; then
            existing="[stored]"
        fi

        local value
        if [[ "$type" == "password" || "$type" == "token" ]]; then
            read -s -p "$prompt $existing: " value
            echo  # newline
        else
            read -p "$prompt $existing: " value
        fi

        if [[ -n "$value" ]]; then
            if validate_secret "$key" "$value" "$type"; then
                set_secret "$key" "$value"
            else
                echo "  Skipped (validation failed). You can retry with: devenv secrets set $key"
            fi
        elif [[ -n "$existing" ]]; then
            echo "  Keeping existing value."
        else
            echo "  Skipped."
        fi
    done

    echo ""
    echo "Secrets wizard complete. Use 'devenv secrets show' to review."
}

# Display stored secrets (masked)
secrets_show() {
    init_secrets
    echo ""
    echo "Stored Secrets"
    echo "=============="

    local found=false
    for def in "${DEVENV_SECRET_DEFS[@]}"; do
        IFS='|' read -r key description type prompt <<< "$def"

        # Check env override
        local env_var="DEVENV_SECRET_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
        local env_value="${!env_var:-}"

        if [[ -n "$env_value" ]]; then
            local masked="${env_value:0:3}***"
            printf "  %-20s %-30s %s (env override)\n" "$key" "$description" "$masked"
            found=true
        elif [[ -f "$SECRETS_DIR/${key}.enc" ]]; then
            printf "  %-20s %-30s %s\n" "$key" "$description" "[encrypted]"
            found=true
        else
            printf "  %-20s %-30s %s\n" "$key" "$description" "(not set)"
        fi
    done

    if [[ "$found" == "false" ]]; then
        echo "  No secrets stored. Run 'devenv secrets' to start the wizard."
    fi
    echo ""
}

# Remove stored secrets
# Usage: secrets_reset [key]
secrets_reset() {
    local key=${1:-}
    init_secrets

    if [[ -n "$key" ]]; then
        local secret_file="$SECRETS_DIR/${key}.enc"
        if [[ -f "$secret_file" ]]; then
            rm -f "$secret_file"
            log "INFO" "Removed secret: $key" "secrets"
        else
            log "WARN" "Secret not found: $key" "secrets"
        fi
    else
        read -p "Remove ALL stored secrets? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$SECRETS_DIR"/*.enc
            log "INFO" "All secrets removed" "secrets"
        fi
    fi
}

# Test decryption of all stored secrets
secrets_validate() {
    init_secrets
    local status=0

    echo "Validating stored secrets..."
    for def in "${DEVENV_SECRET_DEFS[@]}"; do
        IFS='|' read -r key description type prompt <<< "$def"

        if [[ -f "$SECRETS_DIR/${key}.enc" ]]; then
            if value=$(get_secret "$key" 2>/dev/null); then
                if validate_secret "$key" "$value" "$type"; then
                    echo "  $key: OK"
                else
                    echo "  $key: INVALID (decrypted but failed validation)"
                    status=1
                fi
            else
                echo "  $key: FAILED (decryption error)"
                status=1
            fi
        fi
    done

    if [[ $status -eq 0 ]]; then
        echo "All secrets valid."
    fi
    return $status
}

# Export secrets to env-var format file
# Usage: secrets_export <output_file>
secrets_export() {
    local output_file=${1:-}
    if [[ -z "$output_file" ]]; then
        log "ERROR" "Usage: devenv secrets export <file>" "secrets"
        return 1
    fi

    init_secrets
    local count=0

    {
        echo "# DevEnv secrets export - $(date -Iseconds)"
        echo "# Source this file or pass to 'devenv secrets import'"
        for def in "${DEVENV_SECRET_DEFS[@]}"; do
            IFS='|' read -r key description type prompt <<< "$def"
            if [[ -f "$SECRETS_DIR/${key}.enc" ]]; then
                local value
                value=$(get_secret "$key" 2>/dev/null) || continue
                local env_var="DEVENV_SECRET_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
                echo "export $env_var=\"$value\""
                ((count++))
            fi
        done
    } > "$output_file"

    chmod 600 "$output_file"
    log "INFO" "Exported $count secrets to $output_file" "secrets"
}

# Import secrets from env-var format file
# Usage: secrets_import <input_file>
secrets_import() {
    local input_file=${1:-}
    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        log "ERROR" "Usage: devenv secrets import <file>" "secrets"
        return 1
    fi

    init_secrets
    local count=0

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

        # Parse export VAR="value"
        if [[ "$line" =~ ^export[[:space:]]+DEVENV_SECRET_([A-Z_]+)=\"(.*)\"$ ]]; then
            local upper_key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            local key
            key=$(echo "$upper_key" | tr '[:upper:]' '[:lower:]')
            set_secret "$key" "$value"
            ((count++))
        fi
    done < "$input_file"

    log "INFO" "Imported $count secrets from $input_file" "secrets"
}

# Set a single secret interactively or with a value
# Usage: secrets_set <key> [value]
secrets_set() {
    local key=${1:-}
    local value=${2:-}

    if [[ -z "$key" ]]; then
        log "ERROR" "Usage: devenv secrets set <key> [value]" "secrets"
        return 1
    fi

    # Find definition for validation type
    local type="text"
    for def in "${DEVENV_SECRET_DEFS[@]}"; do
        IFS='|' read -r def_key description def_type prompt <<< "$def"
        if [[ "$def_key" == "$key" ]]; then
            type="$def_type"
            break
        fi
    done

    if [[ -z "$value" ]]; then
        if [[ "$type" == "password" || "$type" == "token" ]]; then
            read -s -p "Enter value for $key: " value
            echo
        else
            read -p "Enter value for $key: " value
        fi
    fi

    if [[ -z "$value" ]]; then
        log "ERROR" "No value provided" "secrets"
        return 1
    fi

    if validate_secret "$key" "$value" "$type"; then
        set_secret "$key" "$value"
    else
        log "ERROR" "Validation failed for $key" "secrets"
        return 1
    fi
}

# Main command dispatcher
# Usage: secrets_command <action> [args...]
secrets_command() {
    local action=${1:-wizard}
    shift || true

    case "$action" in
        wizard|"")
            secrets_wizard
            ;;
        show)
            secrets_show
            ;;
        set)
            secrets_set "$@"
            ;;
        reset)
            secrets_reset "$@"
            ;;
        validate)
            secrets_validate
            ;;
        export)
            secrets_export "$@"
            ;;
        import)
            secrets_import "$@"
            ;;
        *)
            echo "Usage: devenv secrets [wizard|show|set|reset|validate|export|import]"
            echo ""
            echo "Commands:"
            echo "  wizard    Interactive secrets collection (default)"
            echo "  show      Display stored secrets (masked)"
            echo "  set       Set a single secret: secrets set <key> [value]"
            echo "  reset     Remove secret(s): secrets reset [key]"
            echo "  validate  Test decryption of all stored secrets"
            echo "  export    Export secrets: secrets export <file>"
            echo "  import    Import secrets: secrets import <file>"
            return 1
            ;;
    esac
}
