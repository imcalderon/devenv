#!/bin/bash
set -euxo pipefail

# OpenVDB build script for vfx-bootstrap

mkdir -p build
cd build

CMAKE_ARGS=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_PREFIX_PATH="${PREFIX}"
    -DOPENVDB_BUILD_CORE=ON
    -DOPENVDB_BUILD_BINARIES=ON
    -DOPENVDB_BUILD_PYTHON_MODULE=ON
    -DOPENVDB_BUILD_UNITTESTS=OFF
    -DOPENVDB_BUILD_DOCS=OFF
    -DUSE_BLOSC=ON
    -DUSE_ZLIB=ON
    -DUSE_EXR=ON
    -DUSE_TBB=ON
    -DUSE_NUMPY=ON
    -DPython_EXECUTABLE="${PYTHON}"
    -DTBB_ROOT="${PREFIX}"
    -DBLOSC_ROOT="${PREFIX}"
    -DOpenEXR_ROOT="${PREFIX}"
    -DImath_ROOT="${PREFIX}"
    -DBOOST_ROOT="${PREFIX}"
)

if [[ "$OSTYPE" == "darwin"* ]]; then
    CMAKE_ARGS+=(
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
    )
fi

cmake "${SRC_DIR}" -G Ninja "${CMAKE_ARGS[@]}"
# OpenVDB instantiation TUs are extremely memory-heavy (~2GB each).
# Limit parallelism to avoid OOM/SIGPIPE in memory-constrained environments (WSL2).
PARALLEL_JOBS="${CPU_COUNT}"
if [[ "${PARALLEL_JOBS}" -gt 2 ]]; then
    PARALLEL_JOBS=2
fi
cmake --build . --parallel "${PARALLEL_JOBS}"
cmake --install .
