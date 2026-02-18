#!/bin/bash
set -euxo pipefail

# TBB build script for vfx-bootstrap
# TBB 2020.3 uses GNU Make (not CMake). oneTBB 2021+ uses CMake.

# Detect if this is classic TBB (Make-based) or oneTBB (CMake-based)
if [[ -f "${SRC_DIR}/CMakeLists.txt" ]]; then
    # oneTBB 2021+ (CMake-based)
    mkdir -p build
    cd build

    cmake "${SRC_DIR}" \
        -G Ninja \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DTBB_TEST=OFF \
        -DTBB_STRICT=OFF

    cmake --build . --parallel "${CPU_COUNT}"
    cmake --install .
else
    # Classic TBB 2020.x (Make-based)
    cd "${SRC_DIR}"

    make -j"${CPU_COUNT}" tbb tbbmalloc tbbproxy

    # Install headers
    mkdir -p "${PREFIX}/include"
    cp -r include/tbb "${PREFIX}/include/"

    # Install libraries
    mkdir -p "${PREFIX}/lib"

    # Find the build output directory (varies by platform)
    BUILD_DIR=$(find build -maxdepth 1 -name "*release" -type d | head -1)
    if [[ -z "$BUILD_DIR" ]]; then
        echo "ERROR: Could not find TBB build output directory"
        ls -la build/
        exit 1
    fi

    # Copy shared libraries
    for lib in "${BUILD_DIR}"/libtbb*.so*; do
        if [[ -f "$lib" ]]; then
            cp -P "$lib" "${PREFIX}/lib/"
        fi
    done

    # Create cmake config for downstream packages
    mkdir -p "${PREFIX}/lib/cmake/TBB"
    cat > "${PREFIX}/lib/cmake/TBB/TBBConfig.cmake" << 'CMAKEOF'
# Minimal TBB CMake config for classic TBB 2020.x
get_filename_component(_tbb_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

add_library(TBB::tbb SHARED IMPORTED)
set_target_properties(TBB::tbb PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_tbb_root}/include"
    IMPORTED_LOCATION "${_tbb_root}/lib/libtbb.so.2"
)

add_library(TBB::tbbmalloc SHARED IMPORTED)
set_target_properties(TBB::tbbmalloc PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_tbb_root}/include"
    IMPORTED_LOCATION "${_tbb_root}/lib/libtbbmalloc.so.2"
)

add_library(TBB::tbbmalloc_proxy SHARED IMPORTED)
set_target_properties(TBB::tbbmalloc_proxy PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_tbb_root}/include"
    IMPORTED_LOCATION "${_tbb_root}/lib/libtbbmalloc_proxy.so.2"
)

set(TBB_FOUND TRUE)
set(TBB_VERSION "2020.3")
CMAKEOF
fi

# Fix rpaths on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    for lib in "${PREFIX}"/lib/libtbb*.dylib; do
        if [[ -f "$lib" ]]; then
            install_name_tool -id "@rpath/$(basename "$lib")" "$lib"
        fi
    done
fi
