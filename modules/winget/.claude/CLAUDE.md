# WinGet Module

## Purpose
Manages Windows packages via the Windows Package Manager (winget).

## Key Files
| File | Purpose |
|------|---------|
| winget.ps1 | Main implementation (Windows only) |
| config.json | Module configuration (runlevel 2) |

## Interface
- `install` — Installs configured packages via winget
- `remove` — Removes devenv-managed winget packages
- `verify` — Checks winget is available and packages are installed
- `info` — Shows winget version and installed package list

## Platform
Windows only.

## Dependencies
None.
