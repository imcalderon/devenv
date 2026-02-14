@echo off
setlocal enabledelayedexpansion

REM Alembic build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DUSE_TESTS=OFF ^
    -DUSE_BINARIES=ON ^
    -DUSE_EXAMPLES=OFF ^
    -DALEMBIC_SHARED_LIBS=ON ^
    -DALEMBIC_ILMBASE_LINK_STATIC=OFF ^
    -DILMBASE_ROOT="%LIBRARY_PREFIX%" ^
    -DOPENEXR_ROOT="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
