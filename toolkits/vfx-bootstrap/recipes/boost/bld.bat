@echo off
setlocal enabledelayedexpansion

REM Boost build script for vfx-bootstrap (Windows)
REM Boost uses its own build system (b2), not CMake

cd "%SRC_DIR%"

REM Bootstrap b2 for MSVC
call bootstrap.bat msvc
if errorlevel 1 exit /b 1

REM Build and install
b2 -j%CPU_COUNT% ^
    --prefix="%LIBRARY_PREFIX%" ^
    --build-dir=build ^
    variant=release ^
    link=shared ^
    runtime-link=shared ^
    threading=multi ^
    toolset=msvc-14.3 ^
    cxxflags="/std:c++17" ^
    address-model=64 ^
    python=%PY_VER% ^
    --without-mpi ^
    --without-graph_parallel ^
    install
if errorlevel 1 exit /b 1
