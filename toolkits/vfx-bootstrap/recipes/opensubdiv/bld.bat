@echo off
setlocal enabledelayedexpansion

REM OpenSubdiv build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DNO_EXAMPLES=ON ^
    -DNO_TUTORIALS=ON ^
    -DNO_REGRESSION=ON ^
    -DNO_DOC=ON ^
    -DNO_OMP=ON ^
    -DNO_CUDA=ON ^
    -DNO_OPENCL=ON ^
    -DNO_PTEX=ON ^
    -DNO_OPENGL=ON ^
    -DNO_GLEW=ON ^
    -DNO_GLFW=ON ^
    -DNO_TBB=OFF ^
    -DTBB_LOCATION="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
