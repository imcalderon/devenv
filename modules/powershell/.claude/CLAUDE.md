# PowerShell Module

## Purpose
Configures PowerShell profile and modules on Windows.

## Key Files
| File | Purpose |
|------|---------|
| powershell.ps1 | Main implementation (Windows only) |
| config.json | Module configuration (runlevel 1) |

## Interface
- `install` — Configures PowerShell profile, installs modules, sets execution policy
- `remove` — Removes devenv-managed profile entries
- `verify` — Checks PowerShell version and profile configuration
- `info` — Shows PowerShell version and installed modules

## Platform
Windows only.

## Dependencies
None.
