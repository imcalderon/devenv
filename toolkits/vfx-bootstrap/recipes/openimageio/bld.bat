@echo off
setlocal enabledelayedexpansion

REM OpenImageIO build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DUSE_PYTHON=ON ^
    -DPYTHON_EXECUTABLE="%PYTHON%" ^
    -DUSE_OPENCOLORIO=ON ^
    -DUSE_QT=OFF ^
    -DINSTALL_FONTS=OFF ^
    -DBUILD_TESTING=OFF ^
    -DOIIO_BUILD_TESTS=OFF ^
    -DOIIO_BUILD_TOOLS=ON ^
    -DBOOST_ROOT="%LIBRARY_PREFIX%" ^
    -DOpenEXR_ROOT="%LIBRARY_PREFIX%" ^
    -DImath_ROOT="%LIBRARY_PREFIX%" ^
    -DOpenColorIO_ROOT="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
