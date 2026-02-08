#!/bin/bash
# modules/vault/vault.sh - Secrets management via OpenBao or HashiCorp Vault
#
# Installs OpenBao (open-source vault, MPL-2.0) by default.
# Provides encrypted secrets backend for lib/secrets.sh.
# Runs in dev mode for local development (no TLS, in-memory storage).

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="vault"

# --- Helpers ---

_vault_backend() {
    local backend
    backend=$(get_module_config "$MODULE_NAME" ".vault.backend" "openbao")
    echo "$backend"
}

_vault_version() {
    local version
    version=$(get_module_config "$MODULE_NAME" ".vault.version" "2.1.0")
    echo "$version"
}

_vault_cli() {
    local backend
    backend=$(_vault_backend)
    if [[ "$backend" == "openbao" ]]; then
        echo "bao"
    else
        echo "vault"
    fi
}

_vault_listen_addr() {
    local addr
    addr=$(get_module_config "$MODULE_NAME" ".vault.listen_address" "127.0.0.1:8200")
    echo "$addr"
}

_vault_secrets_path() {
    local path
    path=$(get_module_config "$MODULE_NAME" ".vault.secrets_path" "secret/devenv")
    echo "$path"
}

_is_vault_running() {
    local cli
    cli=$(_vault_cli)
    local addr
    addr=$(_vault_listen_addr)

    if command -v "$cli" &>/dev/null; then
        VAULT_ADDR="http://$addr" "$cli" status &>/dev/null
        return $?
    fi
    return 1
}

# --- Install ---

install_openbao() {
    local version
    version=$(_vault_version)

    log "INFO" "Installing OpenBao v${version}..." "$MODULE_NAME"

    local arch="amd64"
    case "$(uname -m)" in
        aarch64|arm64) arch="arm64" ;;
        x86_64)        arch="amd64" ;;
        *)
            log "ERROR" "Unsupported architecture: $(uname -m)" "$MODULE_NAME"
            return 1
            ;;
    esac

    local os="linux"
    case "$(uname -s)" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        *)
            log "ERROR" "Unsupported OS: $(uname -s)" "$MODULE_NAME"
            return 1
            ;;
    esac

    local url="https://github.com/openbao/openbao/releases/download/v${version}/bao_${version}_${os}_${arch}.tar.gz"
    local install_dir="${DEVENV_DATA_DIR:-$HOME/.devenv}/bin"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    mkdir -p "$install_dir"

    log "INFO" "Downloading from: $url" "$MODULE_NAME"
    if ! curl -sL "$url" -o "$tmp_dir/bao.tar.gz"; then
        log "ERROR" "Failed to download OpenBao" "$MODULE_NAME"
        rm -rf "$tmp_dir"
        return 1
    fi

    tar -xzf "$tmp_dir/bao.tar.gz" -C "$tmp_dir"
    if [[ -f "$tmp_dir/bao" ]]; then
        mv "$tmp_dir/bao" "$install_dir/bao"
        chmod +x "$install_dir/bao"
    else
        log "ERROR" "bao binary not found in archive" "$MODULE_NAME"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    # Ensure install_dir is in PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        export PATH="$install_dir:$PATH"
    fi

    log "INFO" "OpenBao v${version} installed to $install_dir/bao" "$MODULE_NAME"
}

install_hashicorp_vault() {
    log "INFO" "Installing HashiCorp Vault..." "$MODULE_NAME"

    if command -v dnf &>/dev/null; then
        sudo dnf install -y yum-utils
        sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
        sudo dnf install -y vault
    elif command -v apt-get &>/dev/null; then
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update && sudo apt-get install -y vault
    elif command -v brew &>/dev/null; then
        brew install vault
    else
        log "ERROR" "No supported package manager found" "$MODULE_NAME"
        return 1
    fi

    log "INFO" "HashiCorp Vault installed" "$MODULE_NAME"
}

setup_dev_server() {
    local cli
    cli=$(_vault_cli)
    local addr
    addr=$(_vault_listen_addr)
    local secrets_path
    secrets_path=$(_vault_secrets_path)

    if ! command -v "$cli" &>/dev/null; then
        log "ERROR" "$cli not found in PATH" "$MODULE_NAME"
        return 1
    fi

    # Check if already running
    if _is_vault_running; then
        log "INFO" "Vault dev server already running at $addr" "$MODULE_NAME"
        return 0
    fi

    log "INFO" "Starting dev server on $addr..." "$MODULE_NAME"

    # Create data directory for persistent dev mode
    local data_dir="${DEVENV_DATA_DIR:-$HOME/.devenv}/vault"
    mkdir -p "$data_dir"

    # Store root token for dev mode
    local token_file="$data_dir/dev-root-token"
    local root_token
    if [[ -f "$token_file" ]]; then
        root_token=$(cat "$token_file")
    else
        root_token="devenv-root-token-$(head -c 16 /dev/urandom | xxd -p)"
        echo "$root_token" > "$token_file"
        chmod 600 "$token_file"
    fi

    # Start dev server in background
    nohup "$cli" server -dev \
        -dev-listen-address="$addr" \
        -dev-root-token-id="$root_token" \
        > "$data_dir/server.log" 2>&1 &

    echo $! > "$data_dir/server.pid"
    sleep 2

    if _is_vault_running; then
        log "INFO" "Dev server started (PID: $(cat "$data_dir/server.pid"))" "$MODULE_NAME"

        # Seed secrets from secrets.local if available
        _seed_vault_from_local "$cli" "$addr" "$root_token" "$secrets_path"
    else
        log "ERROR" "Dev server failed to start. Check $data_dir/server.log" "$MODULE_NAME"
        return 1
    fi
}

_seed_vault_from_local() {
    local cli=$1
    local addr=$2
    local token=$3
    local secrets_path=$4
    local secrets_local="${DEVENV_ROOT:-.}/secrets.local"

    if [[ ! -f "$secrets_local" ]]; then
        return 0
    fi

    log "INFO" "Seeding vault from secrets.local..." "$MODULE_NAME"

    # Map secrets.local keys to vault paths
    declare -A key_map=(
        ["GIT_USER_NAME"]="git_name"
        ["GIT_USER_EMAIL"]="git_email"
        ["GITHUB_TOKEN"]="github_token"
        ["ANTHROPIC_API_KEY"]="anthropic_api_key"
        ["SSH_PASSPHRASE"]="ssh_passphrase"
        ["DOCKER_HUB_TOKEN"]="docker_hub_token"
        ["NPM_TOKEN"]="npm_token"
        ["PYPI_TOKEN"]="pypi_token"
    )

    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs 2>/dev/null) || continue
        [[ -z "$key" || "$key" == \#* ]] && continue
        value=$(echo "$value" | xargs 2>/dev/null | sed 's/^["'\''"]//;s/["'\''"]$//')
        [[ -z "$value" ]] && continue

        local vault_key="${key_map[$key]:-}"
        if [[ -n "$vault_key" ]]; then
            VAULT_ADDR="http://$addr" VAULT_TOKEN="$token" \
                "$cli" kv put "$secrets_path/$vault_key" value="$value" &>/dev/null && \
                log "INFO" "  Seeded: $vault_key" "$MODULE_NAME"
        fi
    done < "$secrets_local"
}

stop_dev_server() {
    local data_dir="${DEVENV_DATA_DIR:-$HOME/.devenv}/vault"
    local pid_file="$data_dir/server.pid"

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            log "INFO" "Stopped dev server (PID: $pid)" "$MODULE_NAME"
        fi
        rm -f "$pid_file"
    fi
}

# --- Module Interface ---

_action="${1:-}"

_do_install() {
    local backend
    backend=$(_vault_backend)

    if [[ "$backend" == "openbao" ]]; then
        install_openbao
    else
        install_hashicorp_vault
    fi

    local mode
    mode=$(get_module_config "$MODULE_NAME" ".vault.mode" "dev")
    if [[ "$mode" == "dev" ]]; then
        setup_dev_server
    fi
}

_do_remove() {
    stop_dev_server

    local cli
    cli=$(_vault_cli)
    local install_dir="${DEVENV_DATA_DIR:-$HOME/.devenv}/bin"
    local data_dir="${DEVENV_DATA_DIR:-$HOME/.devenv}/vault"

    if [[ -f "$install_dir/$cli" ]]; then
        rm -f "$install_dir/$cli"
        log "INFO" "Removed $cli binary" "$MODULE_NAME"
    fi

    if [[ -d "$data_dir" ]]; then
        rm -rf "$data_dir"
        log "INFO" "Removed vault data directory" "$MODULE_NAME"
    fi
}

_do_verify() {
    local cli
    cli=$(_vault_cli)

    if ! command -v "$cli" &>/dev/null; then
        log "ERROR" "$cli not found in PATH" "$MODULE_NAME"
        exit 1
    fi

    log "INFO" "$cli version: $("$cli" version 2>/dev/null || echo 'unknown')" "$MODULE_NAME"

    if _is_vault_running; then
        log "INFO" "Vault server is running" "$MODULE_NAME"
    else
        log "WARN" "Vault server is not running" "$MODULE_NAME"
    fi
}

_do_info() {
    local cli
    cli=$(_vault_cli)
    local backend
    backend=$(_vault_backend)
    local addr
    addr=$(_vault_listen_addr)

    echo "Vault Module"
    echo "  Backend:    $backend"
    echo "  CLI:        $cli"
    echo "  Address:    http://$addr"

    if command -v "$cli" &>/dev/null; then
        echo "  Version:    $("$cli" version 2>/dev/null || echo 'not installed')"
    else
        echo "  Version:    not installed"
    fi

    if _is_vault_running; then
        echo "  Status:     running"
    else
        echo "  Status:     stopped"
    fi

    local data_dir="${DEVENV_DATA_DIR:-$HOME/.devenv}/vault"
    if [[ -f "$data_dir/dev-root-token" ]]; then
        echo "  Token file: $data_dir/dev-root-token"
    fi
}

case "$_action" in
    install) _do_install ;;
    remove)  _do_remove ;;
    verify)  _do_verify ;;
    info)    _do_info ;;
    *)
        echo "Usage: vault.sh {install|remove|verify|info}"
        exit 1
        ;;
esac
