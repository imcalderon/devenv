# Development Scripts

This directory contains utility scripts and templates for generating and managing development projects.

## Directory Structure

```
scripts/
├── build.sh                   # Build coordinator for projects
├── generate_phaser_game.sh    # Phaser game project generator
├── templates/                 # Project and module templates
│   ├── modules/              # Module generation templates
│   │   ├── generate.sh       # Module generator script
│   │   └── module.sh         # Base module template
│   └── phaser/               # Phaser game project templates
│       ├── .eslintrc.js      # ESLint configuration
│       ├── .prettierrc       # Prettier configuration
│       ├── README.md         # Project README template
│       ├── webpack.config.js # Webpack configuration
│       └── src/              # Source code templates
└── utils/
    └── common.sh             # Shared utility functions
```

## Core Scripts

### build.sh

Build coordinator that handles different build modes and environments.

```bash
./build.sh --mode=development --port=8080 --watch
./build.sh --mode=production --docker
```

### generate_phaser_game.sh

Generates a new Phaser game project with Node.js, Conda, and Docker configuration.

```bash
./generate_phaser_game.sh my-game --title "My Game" --description "A cool game"
```

## Templates

### DevEnv Module Templates

- `templates/modules/generate.sh`: Creates new development environment modules
- `templates/modules/module.sh`: Base template for module implementation

### Phaser Templates

- Project structure and configuration files
- Source code organization templates
- Build and development setup

## Utilities

### common.sh

Shared functions for scripts including:

- Environment validation
- Tool installation checks
- Logging utilities
- Common setup procedures

## Adding New Scripts

When adding new scripts, follow these conventions:

1. Place script files in the root `scripts/` directory
2. Add corresponding templates in `templates/<type>/`
3. Use common utilities from `utils/common.sh`
4. Follow naming convention: `generate_<type>.sh` for generators

### Template Types

To add support for a new project type:

1. Create a new directory under `templates/`
2. Add template files and directory structure
3. Create a generator script using `common.sh` utilities
4. Update this README

## Planned Additions

Future expansions may include:

- Debug harness scripts
- Additional project type generators
- Test automation scripts
- Deployment utilities
- CI/CD templates

## Usage Examples

### Generate a New Module

```bash
./templates/modules/generate.sh mymodule
```

### Create a Phaser Game

```bash
./generate_phaser_game.sh mygame \
  --title "My Game" \
  --description "An awesome game" \
  --author "Developer Name"
```

### Build Project

```bash
./build.sh --mode=development --watch
```

## Contributing

When adding new scripts:

1. Use the shared utilities in `common.sh`
2. Follow the existing naming conventions
3. Add appropriate templates
4. Update this README
5. Include usage examples

## Dependencies

Scripts may require:

- bash
- Node.js/npm
- Docker
- Conda
- Git

Check individual script requirements for details.
