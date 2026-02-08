#!/bin/bash
set -euxo pipefail

# OpenSubdiv build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DNO_EXAMPLES=ON
    -DNO_TUTORIALS=ON
    -DNO_REGRESSION=ON
    -DNO_DOC=ON
    -DNO_OMP=ON
    -DNO_CUDA=ON
    -DNO_OPENCL=ON
    -DNO_PTEX=ON
    -DNO_OPENGL=ON
    -DNO_GLEW=ON
    -DNO_GLFW=ON
    -DNO_TBB=OFF
    -DTBB_LOCATION="${PREFIX}"
)

if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
        -DNO_METAL=ON
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
cmake --build . --parallel "${CPU_COUNT}"
cmake --install .
