# Python Module

## Purpose
Installs Python via pyenv with version management and development tools.

## Key Files
| File | Purpose |
|------|---------|
| python.sh | Main implementation |
| config.json | Module configuration (runlevel 2, depends on docker) |

## Interface
- `install` — Installs pyenv, Python versions, pip packages, and shell aliases
- `remove` — Removes pyenv configuration from shell
- `verify` — Checks pyenv and Python versions are available
- `info` — Shows installed Python versions and pyenv status

## Dependencies
docker (for containerized builds).
