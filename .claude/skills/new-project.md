# /new-project — Scaffold a new project

## Usage
`/new-project <name> --type <type>`

## Description
Create a new project directory with scaffolded files from a workflow template.

## Steps
1. Parse the project name and type from the argument
2. Run `./devenv --new-project <name> --type <type>`
3. Report what was created — list the generated files
4. Suggest next steps based on the project type

## Available Types
- `vfx` — C++ project with CMakeLists.txt, Imath/OpenEXR deps
- `web:phaser` — Phaser 3 + TypeScript game with Vite
- `web:vanilla` — Vanilla TypeScript + Vite
- Use `./devenv --list-types` to see all options

## Examples
```bash
./devenv --new-project my-tool --type vfx
./devenv --new-project my-game --type web:phaser
./devenv --new-project my-app --type web:vanilla
```
