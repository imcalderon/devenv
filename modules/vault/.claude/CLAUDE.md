# Vault Module

## Purpose
Installs and manages a secrets backend (OpenBao or HashiCorp Vault) for encrypted credential storage. Integrates with `lib/secrets.sh` as an optional backend — when vault is running, `get_secret` checks vault automatically.

## Key Files
| File | Purpose |
|------|---------|
| vault.sh | Main implementation |
| config.json | Module configuration (runlevel 4, disabled by default) |

## Interface
- `install` — Downloads and installs OpenBao (default) or HashiCorp Vault, starts dev server
- `remove` — Stops server, removes binary and data directory
- `verify` — Checks CLI is installed and server is running
- `info` — Shows backend, version, address, and server status

## Backend Options
- **OpenBao** (default) — Open-source fork of Vault, MPL-2.0 license, CLI: `bao`
- **HashiCorp Vault** — BSL license, CLI: `vault`

Set in config.json: `"vault.backend": "openbao"` or `"vault.backend": "hashicorp"`

## Secrets Integration
`lib/secrets.sh` checks secrets in this priority order:
1. Environment variables (`DEVENV_SECRET_<KEY>`)
2. `secrets.local` file (plaintext, gitignored)
3. Vault/OpenBao (if running)
4. Encrypted files (`~/.devenv/secrets/*.enc`)

## Dev Mode
By default, runs in dev mode (in-memory storage, no TLS). Good for local development.
On install, seeds vault from `secrets.local` if present.

## Data Paths
- Binary: `~/.devenv/bin/bao`
- Server log: `~/.devenv/vault/server.log`
- PID file: `~/.devenv/vault/server.pid`
- Root token: `~/.devenv/vault/dev-root-token`

## Dependencies
None. Module is disabled by default — enable in config.json.
