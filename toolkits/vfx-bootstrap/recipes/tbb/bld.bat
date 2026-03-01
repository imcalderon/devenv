@echo off
setlocal enabledelayedexpansion

REM oneTBB 2021.x build script for vfx-bootstrap on Windows

mkdir build
cd build

cmake -G Ninja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DTBB_TEST=OFF ^
    -DTBB_STRICT=OFF ^
    ..
if errorlevel 1 exit /b 1

cmake --build . --config Release -j %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install . --config Release
if errorlevel 1 exit /b 1
