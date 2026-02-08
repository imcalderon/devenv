# WSL Contained Environment

Scripts for provisioning and managing an AlmaLinux 10 WSL environment.
All WSL data (disk image, source image, config, exports) lives under a single
configurable root directory for easy relocation, backup, and destruction.

## Directory Structure

All data is contained under `$WslRoot` (defaults to parent of devenv repo):

```
$WslRoot/
├── image/              # WSL disk image (ext4.vhdx)
├── distro/             # Source .wsl image for re-imports
│   └── AlmaLinux-10.1_x64.wsl
├── config/             # Generated .wslconfig
│   └── .wslconfig
└── exports/            # Backup exports
    └── AlmaLinux10-20260208-120000.tar
```

## Scripts

| Script | Purpose |
|--------|---------|
| `install-wsl.ps1` | First-time setup: download image, import, generate .wslconfig, bootstrap |
| `delete-wsl.ps1` | Clean destruction: terminate, unregister, remove disk image |
| `reset-wsl.ps1` | Factory reset: unregister + re-import from source image |
| `WSL_Image_Mover.ps1` | Relocate existing distro to `$WslRoot/image/` |
| `bootstrap-wsl.sh` | Minimal bootstrap: user, sudo, packages, Node.js, Claude Code |
| `setup-devenv.sh` | Full setup: clone devenv, run init, install tools |

## Lifecycle

### First-time install

```powershell
# From PowerShell as Administrator
.\wsl\install-wsl.ps1

# Customize
.\wsl\install-wsl.ps1 -WslRoot "E:\WSL\devenv" -Memory "16GB" -Username "myuser"
```

### Reset to clean state

```powershell
# Reset only (no bootstrap, no user)
.\wsl\reset-wsl.ps1

# Reset with bootstrap (creates user, installs packages)
.\wsl\reset-wsl.ps1 -Bootstrap

# Export backup first, then reset with bootstrap
.\wsl\reset-wsl.ps1 -Export -Bootstrap
```

### Delete entirely

```powershell
# Remove distro but keep source image for re-install
.\wsl\delete-wsl.ps1

# Remove everything including exports
.\wsl\delete-wsl.ps1 -RemoveAll
```

### Move existing distro

```powershell
# Relocate to contained directory structure
.\wsl\WSL_Image_Mover.ps1 -DistributionName "AlmaLinux10"
```

### Inside WSL

```bash
# After bootstrap, run full devenv setup
./wsl/setup-devenv.sh

# Or manually
cd ~/devenv && ./devenv init vfx
```

## Design Principles

- **Contained** — All data under one folder. Nothing scattered across `C:\Users\...`.
- **Minimal bootstrap** — Only install what's needed to run devenv (git, jq, curl, sudo, gh, node).
- **Devenv does the work** — All dev tooling (zsh, python, conda, etc.) comes from devenv modules.
- **Separate lifecycles** — Install, reset, and delete are distinct operations. Reset does NOT auto-bootstrap.
- **Portable** — Change `$WslRoot` to move everything to a different drive.

## Configuration

WSL settings in `config.json`:

```json
"wsl": {
  "enabled": true,
  "distribution": "AlmaLinux10",
  "default_root": "${DEVENV_ROOT}/..",
  "memory": "8GB",
  "swap": "4GB",
  "processors": 4,
  "auto_install": false
}
```

## Secrets

Bootstrap creates `~/.config/devenv/secrets.env`:

```bash
export GIT_USER_NAME=""
export GIT_USER_EMAIL=""
export GITHUB_TOKEN=""
export ANTHROPIC_API_KEY=""
```

For browser-based auth:
- GitHub: `gh auth login --web`
- Claude: Run `claude` then type `/login`

## Requirements

- Windows 10/11 with WSL2 enabled
- PowerShell 5.1+ (run as Administrator)
- Internet access (for image download on first install)
