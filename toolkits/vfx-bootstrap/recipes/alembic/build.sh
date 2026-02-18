#!/bin/bash
set -euxo pipefail

# Alembic build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DUSE_TESTS=OFF
    -DUSE_BINARIES=ON
    -DUSE_EXAMPLES=OFF
    -DALEMBIC_SHARED_LIBS=ON
    -DALEMBIC_ILMBASE_LINK_STATIC=OFF
    -DILMBASE_ROOT="${PREFIX}"
    -DOPENEXR_ROOT="${PREFIX}"
)

if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
cmake --build . --parallel "${CPU_COUNT}"
cmake --install .
