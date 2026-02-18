# Contributing to vfx-bootstrap

Thank you for your interest in contributing to vfx-bootstrap! This document provides guidelines and information for contributors.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/vfx-bootstrap.git
   cd vfx-bootstrap
   ```
3. Set up your development environment:
   ```bash
   ./bootstrap/bootstrap.sh
   ```

## Ways to Contribute

### Recipe Contributions

The most valuable contributions are cross-platform recipes for VFX packages:

1. **Porting existing recipes**: Help adapt recipes to work on multiple platforms
2. **New recipes**: Add recipes for VFX packages not yet included
3. **Recipe improvements**: Optimize build times, fix issues, improve compatibility

See [docs/recipe-porting.md](docs/recipe-porting.md) for recipe development guidelines.

### Code Contributions

- **Builder improvements**: Enhance the build system, caching, or CLI
- **Bootstrap scripts**: Improve platform detection and setup
- **Packager exporters**: Add new output formats or improve existing ones
- **Tests**: Expand test coverage

### Documentation

- Improve existing documentation
- Add tutorials or how-to guides
- Document platform-specific quirks

## Development Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation changes
- `recipe/package-name` - Recipe additions or updates

### Commit Messages

Use clear, descriptive commit messages:

```
Add OpenVDB recipe for VFX Platform 2024

- Cross-platform support (Ubuntu, Rocky Linux)
- Includes Blosc compression support
- Tested on WSL2 Ubuntu 22.04
```

### Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Test on at least one supported platform
4. Update documentation if needed
5. Submit a pull request with:
   - Clear description of changes
   - Testing performed
   - Platform(s) tested on

### Code Style

**Python**:
- Follow PEP 8
- Use type hints where practical
- Maximum line length: 100 characters

**Shell scripts**:
- Use `#!/usr/bin/env bash`
- Quote variables: `"${variable}"`
- Use `set -euo pipefail` at the start

**YAML (recipes)**:
- 2-space indentation
- Use conda selectors for platform-specific code

## Recipe Guidelines

### Cross-Platform Requirements

All recipes must:
1. Use conda's compiler packages (`{{ compiler('c') }}`)
2. Avoid hardcoded paths
3. Use platform selectors where needed (`# [unix]`, `# [win]`)
4. Be tested on at least Ubuntu

### Recipe Structure

```yaml
package:
  name: package-name
  version: "1.2.3"

source:
  url: https://example.com/package-1.2.3.tar.gz
  sha256: abc123...

build:
  number: 0
  run_exports:
    - {{ pin_subpackage('package-name', max_pin='x.x') }}

requirements:
  build:
    - {{ compiler('c') }}
    - {{ compiler('cxx') }}
    - cmake
    - ninja  # [unix]
  host:
    - python
  run:
    - python

test:
  commands:
    - test -f $PREFIX/lib/libpackage.so  # [linux]
    - test -f $PREFIX/lib/libpackage.dylib  # [osx]
```

### VFX Platform Compliance

Recipes must target specific VFX Platform versions. Check [docs/vfx-platform-2024.md](docs/vfx-platform-2024.md) for version requirements.

## Testing

### Running Tests

```bash
# Run all tests
pytest tests/

# Run specific test
pytest tests/test_recipes.py -k "test_boost"

# Test a recipe build
vfx-bootstrap build boost --platform vfx2024 --test
```

### CI Requirements

All pull requests must:
- Pass existing tests
- Not break builds on supported platforms
- Include tests for new functionality

## Reporting Issues

When reporting issues, include:
- Platform and version (e.g., Ubuntu 22.04 on WSL2)
- Python version
- Complete error output
- Steps to reproduce

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help newcomers learn

## Questions?

- Open a GitHub issue for questions
- Tag issues appropriately (`question`, `help-wanted`, etc.)

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
