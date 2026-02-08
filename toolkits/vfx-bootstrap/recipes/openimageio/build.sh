#!/bin/bash
set -euxo pipefail

# OpenImageIO build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"

    # Python bindings
    -DUSE_PYTHON=ON
    -DPYTHON_EXECUTABLE="${PYTHON}"

    # Feature toggles
    -DUSE_OPENCOLORIO=ON
    -DUSE_QT=OFF
    -DINSTALL_FONTS=OFF

    # Testing / docs
    -DBUILD_TESTING=OFF
    -DOIIO_BUILD_TESTS=OFF
    -DOIIO_BUILD_TOOLS=ON

    # Library paths
    -DBOOST_ROOT="${PREFIX}"
    -DOpenEXR_ROOT="${PREFIX}"
    -DImath_ROOT="${PREFIX}"
    -DOpenColorIO_ROOT="${PREFIX}"
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
