# Git Module

## Purpose
Configures Git with user identity, aliases, and default settings.

## Key Files
| File | Purpose |
|------|---------|
| git.sh | Main implementation |
| config.json | Module configuration (runlevel 2) |

## Interface
- `install` — Configures git user name/email, default branch, aliases, and credential helper
- `remove` — Removes devenv-managed git config entries
- `verify` — Checks git is installed and user identity is configured
- `info` — Shows git version and current configuration

## Dependencies
None.
