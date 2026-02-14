@echo off
setlocal enabledelayedexpansion

REM OpenColorIO build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DOCIO_BUILD_PYTHON=ON ^
    -DPython_EXECUTABLE="%PYTHON%" ^
    -DPython_FIND_STRATEGY=LOCATION ^
    -DOCIO_PYTHON_VERSION="3.11" ^
    -DOCIO_BUILD_APPS=ON ^
    -DOCIO_BUILD_TESTS=OFF ^
    -DOCIO_BUILD_GPU_TESTS=OFF ^
    -DOCIO_BUILD_DOCS=OFF ^
    -DOCIO_INSTALL_EXT_PACKAGES=MISSING
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
