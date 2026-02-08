# /init — Initialize a devenv workflow

## Usage
`/init <workflow>`

## Description
Initialize a development environment from a workflow definition. Equivalent to running `./devenv init <workflow>`.

## Steps
1. Run `./devenv init <workflow>` where `<workflow>` is the argument (e.g., `vfx`, `web`, `data-science`)
2. If no argument provided, run `./devenv workflows` to show available options
3. Report the result — which modules installed successfully and which failed

## Available Workflows
- `vfx` — VFX Platform (zsh, git, docker, python, conda, vfx)
- `web` — Web development (zsh, git, nodejs, vscode, docker)
- `data-science` — Data science (zsh, git, python, vscode, docker, conda)
- `game` — Game development (zsh, git, nodejs, vscode, docker)
