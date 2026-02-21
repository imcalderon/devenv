# C++ Conventions

- Use C++17 standard (VFX Platform 2024 requirement)
- Use VFX Platform namespaces (Imath::, OpenEXR::, pxr:: for USD)
- Prefer CMake targets over raw include/link paths
- Use `find_package()` for all VFX dependencies
- Use Ninja generator for faster builds
