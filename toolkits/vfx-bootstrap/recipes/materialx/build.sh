#!/bin/bash
set -euxo pipefail

# MaterialX build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DMATERIALX_BUILD_PYTHON=ON
    -DMATERIALX_BUILD_VIEWER=OFF
    -DMATERIALX_BUILD_GRAPH_EDITOR=OFF
    -DMATERIALX_BUILD_TESTS=OFF
    -DMATERIALX_BUILD_GEN_GLSL=ON
    -DMATERIALX_BUILD_GEN_OSL=ON
    -DMATERIALX_BUILD_GEN_MDL=OFF
    -DMATERIALX_PYTHON_VERSION="${PY_VER}"
    -DPYTHON_EXECUTABLE="${PYTHON}"
)

if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
cmake --build . --parallel "${CPU_COUNT}"
cmake --install .
