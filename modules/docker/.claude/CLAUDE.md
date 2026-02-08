# Docker Module

## Purpose
Installs and configures Docker Engine for containerized development.

## Key Files
| File | Purpose |
|------|---------|
| docker.sh | Main implementation |
| config.json | Module configuration (runlevel 2) |

## Interface
- `install` — Installs Docker Engine, adds user to docker group, configures daemon
- `remove` — Removes Docker configuration managed by devenv
- `verify` — Checks Docker daemon is running and user has permissions
- `info` — Shows Docker version and container status

## Dependencies
None.
