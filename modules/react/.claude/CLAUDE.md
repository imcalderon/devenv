# React Module

## Purpose
Installs React development tools and global npm packages for web development.

## Key Files
| File | Purpose |
|------|---------|
| react.sh | Main implementation |
| config.json | Module configuration (runlevel 3, requires node >= 16) |

## Interface
- `install` — Installs create-react-app, TypeScript, ESLint, Prettier, Storybook globally
- `remove` — Removes global npm packages
- `verify` — Checks required global packages are available
- `info` — Shows installed React toolchain versions

## Dependencies
Node.js >= 16, npm >= 7.
