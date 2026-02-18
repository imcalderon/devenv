#!/bin/bash
set -euxo pipefail

# OpenColorIO build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"

    # Python bindings
    -DOCIO_BUILD_PYTHON=ON
    -DPython_EXECUTABLE="${PYTHON}"
    -DPython_FIND_STRATEGY=LOCATION
    -DOCIO_PYTHON_VERSION="3.11"

    # Applications
    -DOCIO_BUILD_APPS=ON

    # Testing / docs
    -DOCIO_BUILD_TESTS=OFF
    -DOCIO_BUILD_GPU_TESTS=OFF
    -DOCIO_BUILD_DOCS=OFF

    # Use bundled deps for small internal libraries (pystring, minizip-ng,
    # yaml-cpp) to avoid version mismatch issues. External packages like
    # imath, openexr, expat, lcms2 are provided by conda.
    -DOCIO_INSTALL_EXT_PACKAGES=MISSING
)

if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
        -DCMAKE_INSTALL_RPATH="@loader_path/../lib"
    )
else
    CMAKE_ARGS+=(
        -DCMAKE_INSTALL_RPATH="\$ORIGIN/../lib"
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
cmake --build . --parallel "${CPU_COUNT}"
cmake --install .
