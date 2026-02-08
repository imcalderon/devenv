# Node.js Module

## Purpose
Installs Node.js via nvm with version management and global packages.

## Key Files
| File | Purpose |
|------|---------|
| nodejs.sh | Main implementation |
| config.json | Module configuration (runlevel 3) |

## Interface
- `install` — Installs nvm, Node.js LTS, and configured global npm packages
- `remove` — Removes nvm configuration from shell
- `verify` — Checks nvm and node are available with correct versions
- `info` — Shows Node.js version, nvm status, and global packages

## Dependencies
None.
