#!/bin/bash
set -euxo pipefail

# Boost build script for vfx-bootstrap

# Configure b2 build
./bootstrap.sh \
    --prefix="${PREFIX}" \
    --with-python="${PYTHON}" \
    --with-icu="${PREFIX}" \
    --with-toolset=gcc

# Build and install
./b2 \
    -j"${CPU_COUNT}" \
    --prefix="${PREFIX}" \
    --build-dir=build \
    variant=release \
    link=shared \
    runtime-link=shared \
    threading=multi \
    cxxflags="-std=c++17 ${CXXFLAGS}" \
    linkflags="${LDFLAGS}" \
    python="${PY_VER}" \
    --without-mpi \
    --without-graph_parallel \
    install

# Fix rpaths on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    for lib in "${PREFIX}"/lib/libboost_*.dylib; do
        install_name_tool -id "@rpath/$(basename "$lib")" "$lib"
    done
fi
