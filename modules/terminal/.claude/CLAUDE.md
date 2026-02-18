# Windows Terminal Module

## Purpose
Configures Windows Terminal with profiles and settings.

## Key Files
| File | Purpose |
|------|---------|
| terminal.ps1 | Main implementation (Windows only) |
| config.json | Module configuration (runlevel 0) |

## Interface
- `install` — Configures Windows Terminal profiles, color schemes, and defaults
- `remove` — Removes devenv-managed Terminal settings
- `verify` — Checks Windows Terminal is installed and configured
- `info` — Shows Terminal version and profile list

## Platform
Windows only. Runlevel 0 (runs first).

## Dependencies
None.
