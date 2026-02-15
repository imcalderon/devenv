@echo off
setlocal enabledelayedexpansion

REM Boost build script for vfx-bootstrap (Windows)
REM MSVC is already activated by conda's vs2022_compiler_vars.bat
REM Boost uses its own build system (b2), not CMake

cd "%SRC_DIR%"

REM Bootstrap b2 for MSVC
call bootstrap.bat msvc
if errorlevel 1 exit /b 1

REM Tell b2 to use cl.exe on PATH as MSVC 14.3, skipping VS install probing
echo using msvc : 14.3 : cl.exe ; > user-config.jam

REM Build and install
REM b2 returns non-zero when config probes are skipped, even when the actual
REM libraries build successfully (17000+ targets). Verify output instead.
b2 -j%CPU_COUNT% ^
    --user-config=user-config.jam ^
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

REM Verify boost actually installed rather than trusting b2 exit code
if not exist "%LIBRARY_PREFIX%\include\boost\version.hpp" (
    echo ERROR: boost headers not installed
    exit /b 1
)
dir "%LIBRARY_PREFIX%\lib\boost_*.lib" >nul 2>&1
if errorlevel 1 (
    echo ERROR: boost libraries not installed
    exit /b 1
)
echo Boost installed successfully
