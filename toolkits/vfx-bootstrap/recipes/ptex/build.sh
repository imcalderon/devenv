#!/bin/bash
set -euxo pipefail

# Ptex build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DPTEX_BUILD_SHARED_LIBS=ON
    -DPTEX_BUILD_STATIC_LIBS=OFF
    -DPTEX_BUILD_DOCS=OFF
)

if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
cmake --build . --parallel "${CPU_COUNT}"
cmake --install .
