#!/bin/bash
set -euxo pipefail

# USD build script for vfx-bootstrap
# This is the primary build target of the project

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"

    # Python configuration
    -DPXR_ENABLE_PYTHON_SUPPORT=ON
    -DPYTHON_EXECUTABLE="${PYTHON}"
    -DPXR_PYTHON_SHEBANG="${PREFIX}/bin/python"
    -DPXR_USE_PYTHON_3=ON

    # Feature flags
    -DPXR_BUILD_IMAGING=ON
    -DPXR_BUILD_USD_IMAGING=ON
    -DPXR_BUILD_USDVIEW=ON
    -DPXR_BUILD_ALEMBIC_PLUGIN=ON
    -DPXR_BUILD_DRACO_PLUGIN=OFF
    -DPXR_BUILD_EMBREE_PLUGIN=OFF
    -DPXR_BUILD_PRMAN_PLUGIN=OFF
    -DPXR_BUILD_DOCUMENTATION=OFF
    -DPXR_BUILD_TESTS=OFF
    -DPXR_BUILD_EXAMPLES=OFF
    -DPXR_BUILD_TUTORIALS=OFF

    # MaterialX support
    -DPXR_ENABLE_MATERIALX_SUPPORT=ON
    -DMATERIALX_ROOT="${PREFIX}"

    # OpenSubdiv
    -DPXR_ENABLE_OPENSUBDIV_SUPPORT=ON
    -DOPENSUBDIV_ROOT_DIR="${PREFIX}"

    # OpenVDB
    -DPXR_ENABLE_OPENVDB_SUPPORT=ON
    -DOPENVDB_ROOT="${PREFIX}"

    # Ptex
    -DPXR_ENABLE_PTEX_SUPPORT=ON
    -DPTEX_LOCATION="${PREFIX}"

    # OpenColorIO / OpenImageIO (auto-detected via CMAKE_PREFIX_PATH)
    -DOPENCOLORIO_ROOT="${PREFIX}"
    -DOPENIMAGEIO_ROOT="${PREFIX}"

    # OpenEXR
    -DOPENEXR_LOCATION="${PREFIX}"

    # TBB
    -DTBB_ROOT_DIR="${PREFIX}"

    # Boost
    -DBOOST_ROOT="${PREFIX}"
)

# Platform-specific settings
if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
        -DCMAKE_INSTALL_RPATH="@loader_path/../lib"
        -DPXR_BUILD_OPENGL_ENABLED=ON
    )
else
    CMAKE_ARGS+=(
        -DCMAKE_INSTALL_RPATH="\$ORIGIN/../lib"
        -DPXR_BUILD_OPENGL_ENABLED=ON
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
cmake --build . --parallel "${CPU_COUNT}"
cmake --install .

# Fix Python module permissions
chmod -R u+w "${PREFIX}"/lib/python*/site-packages/pxr || true
