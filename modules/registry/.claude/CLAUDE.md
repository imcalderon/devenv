# Registry Module

## Purpose
Manages Windows Registry settings for development environment configuration.

## Key Files
| File | Purpose |
|------|---------|
| registry.ps1 | Main implementation (Windows only) |
| config.json | Module configuration (runlevel 5) |

## Interface
- `install` — Applies configured registry settings (developer mode, long paths, etc.)
- `remove` — Reverts devenv-managed registry changes
- `verify` — Checks registry values match expected configuration
- `info` — Shows current registry settings status

## Platform
Windows only. Runlevel 5 (runs late, after other Windows modules).

## Dependencies
None.
