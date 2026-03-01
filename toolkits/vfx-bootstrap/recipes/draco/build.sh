#!/bin/bash
set -ex

mkdir build
cd build

cmake ${CMAKE_ARGS} 
    -DCMAKE_BUILD_TYPE=Release 
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" 
    -DBUILD_SHARED_LIBS=ON 
    -DDRACO_FAST=ON 
    -G Ninja 
    ..

cmake --build . --config Release
cmake --install .
