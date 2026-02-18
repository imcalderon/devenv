# ZSH Module

## Purpose
Installs and configures ZSH as the default shell with XDG-compliant configuration, vi-mode keybindings, and essential plugins.

## Key Files
| File | Purpose |
|------|---------|
| zsh.sh | Main implementation |
| config.json | Module configuration (runlevel 1, no dependencies) |

## Interface
- `install` -- Installs ZSH, creates XDG directory structure, configures .zshenv/.zshrc, sets up prompt, vi-mode keybindings, completion system, plugins, and changes the default shell to ZSH.
- `remove` -- Backs up and removes ZSH configuration files, changes shell back to bash, removes state file.
- `verify` -- Checks each component: ZSH binary exists, config files present, plugins installed, ZSH is default shell.
- `info` -- Displays module description, component status, ZSH version, and available aliases.
- `finalize` -- Explicitly changes the login shell to ZSH if not already done.

## Dependencies
None (runlevel 1 -- first module to install).

## Components
1. **core** -- Base ZSH installation via apt/dnf
2. **config** -- .zshenv (environment vars, XDG paths) and .zshrc (options, sourcing)
3. **prompt** -- Custom minimal prompt with git info via vcs_info
4. **keybindings** -- Vi-mode with text objects, surround, and editor integration
5. **completion** -- Full ZSH completion system with case-insensitive matching
6. **plugins** -- zsh-syntax-highlighting and zsh-history-substring-search (cloned from GitHub)
7. **shellchange** -- Sets ZSH as the user default login shell via chsh

## Conventions
- XDG-compliant paths: config in `~/.config/zsh`, cache in `~/.cache/zsh`, data in `~/.local/share/zsh`.
- Module aliases are written to `~/.config/zsh/modules/*.zsh` and sourced from .zshrc.
- State tracked in `~/.devenv/state/zsh.state` with component:status:timestamp format.
