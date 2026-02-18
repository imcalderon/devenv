# /build — Build a VFX package

## Usage
`/build <package>`

## Description
Build a VFX Platform package using the vfx-bootstrap build system.

## Steps
1. Run `conda run -n vfx-build python -m builder.cli build <package> -v`
2. Monitor the build output for errors
3. If the build fails, check `~/Development/vfx/builds/logs/` for detailed logs
4. On success, the package will be in `~/Development/vfx/builds/linux-64/`

## Available Packages
Run `conda run -n vfx-build python -m builder.cli list` to see all recipes.

Build order: imath -> openexr -> opencolorio -> tbb -> opensubdiv -> boost -> openvdb -> ptex -> openimageio -> materialx -> alembic -> usd

## Debugging
- SHA256 mismatch: `curl -sL <url> | sha256sum`
- Build env: `conda-bld/<pkg>_<timestamp>/_h_env_*`
- Work dir: `conda-bld/<pkg>_<timestamp>/work/`
