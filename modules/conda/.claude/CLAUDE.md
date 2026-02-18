# Conda Module

## Purpose
Installs Miniconda for environment and package management.

## Key Files
| File | Purpose |
|------|---------|
| conda.sh | Main implementation |
| config.json | Module configuration (runlevel 4) |

## Interface
- `install` — Downloads and installs Miniconda, configures channels and shell integration
- `remove` — Removes Miniconda shell hooks from profile
- `verify` — Checks conda is available and base environment is functional
- `info` — Shows conda version, channels, and environment list

## Dependencies
None.

## Conventions
- Use `conda run -n <env>` for running commands in environments (never `conda activate`)
- Shell aliases: `ca` (activate), `ci` (install)
