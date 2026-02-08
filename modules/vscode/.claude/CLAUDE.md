# VS Code Module

## Purpose
Installs Visual Studio Code and configures extensions and settings.

## Key Files
| File | Purpose |
|------|---------|
| vscode.sh | Main implementation |
| config.json | Module configuration (runlevel 2) |

## Interface
- `install` — Installs VS Code, configured extensions, and default settings
- `remove` — Removes devenv-managed VS Code settings
- `verify` — Checks VS Code is available and extensions are installed
- `info` — Shows VS Code version and installed extensions

## Dependencies
None.

## Conventions
- In WSL, uses Windows-side VS Code with `code` command via PATH integration.
