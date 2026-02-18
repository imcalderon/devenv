#!/bin/bash
set -euxo pipefail

# OpenEXR build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DBUILD_SHARED_LIBS=ON
    -DOPENEXR_INSTALL_TOOLS=ON
    -DOPENEXR_INSTALL_EXAMPLES=OFF
    -DBUILD_TESTING=OFF
)

# Platform-specific settings
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
