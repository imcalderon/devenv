# WSL Bootstrap Scripts

Scripts for provisioning a minimal WSL environment to run devenv.

## Philosophy

- **Minimal bootstrap** - Only install what's needed to run devenv (git, jq, curl, sudo)
- **Devenv does the work** - All dev tooling (zsh, python, nodejs, etc.) comes from devenv modules
- **Resetable baseline** - Quick to wipe and recreate from base image

## Files

| File | Purpose |
|------|---------|
| `bootstrap-wsl.sh` | Minimal bootstrap: user, sudo, git/jq/curl, secrets template |
| `setup-devenv.sh` | Full setup: clone devenv, install, Claude Code, gh CLI |
| `reset-wsl.ps1` | Windows automation: import image, run bootstrap, optionally full setup |

## Usage

### From Windows (PowerShell)

```powershell
# Quick reset (minimal + clone devenv)
.\wsl\reset-wsl.ps1

# Full automated setup
.\wsl\reset-wsl.ps1 -FullSetup

# Customize
.\wsl\reset-wsl.ps1 -DistroName "MyDevEnv" -Username "myuser" -FullSetup
```

### Manual Steps

```powershell
# 1. Import WSL image
wsl --import AlmaLinux10 E:\WSL\AlmaLinux10 E:\WSL\AlmaLinux-10.1_x64.wsl

# 2. Run bootstrap as root
wsl -d AlmaLinux10 --user root /mnt/e/WSL/devenv/wsl/bootstrap-wsl.sh

# 3. Restart WSL (applies wsl.conf)
wsl --shutdown

# 4. Run full setup as user
wsl -d AlmaLinux10 /mnt/e/WSL/devenv/wsl/setup-devenv.sh
```

## Secrets Management

Bootstrap creates `~/.config/devenv/secrets.env` with template:

```bash
export GIT_USER_NAME=""
export GIT_USER_EMAIL=""
export GITHUB_TOKEN=""
export ANTHROPIC_API_KEY=""
# export VAULT_ADDR=""
# export VAULT_TOKEN=""
```

Edit this file with your credentials. **Never commit secrets.env!**

For browser-based auth:
- GitHub: `gh auth login --web`
- Claude: Run `claude` then type `/login`

## Requirements

- Windows 10/11 with WSL2
- AlmaLinux 10 WSL image (or similar RHEL-based distro)
- PowerShell 5.1+ (for reset-wsl.ps1)

## Future

- HashiCorp Vault module for enterprise secrets management
- Support for other WSL distros (Ubuntu, Debian)
