@echo off
setlocal enabledelayedexpansion

REM Activate MSVC environment
set "VSWHERE=%BUILD_PREFIX%\Library\bin\vswhere.exe"
if not exist "%VSWHERE%" set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VSINSTALL=%%i"
if defined VSINSTALL (
    call "%VSINSTALL%\VC\Auxiliary\Build\vcvarsall.bat" amd64
    if errorlevel 1 exit /b 1
)

REM MaterialX build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DMATERIALX_BUILD_PYTHON=ON ^
    -DMATERIALX_BUILD_VIEWER=OFF ^
    -DMATERIALX_BUILD_GRAPH_EDITOR=OFF ^
    -DMATERIALX_BUILD_TESTS=OFF ^
    -DMATERIALX_BUILD_GEN_GLSL=ON ^
    -DMATERIALX_BUILD_GEN_OSL=ON ^
    -DMATERIALX_BUILD_GEN_MDL=OFF ^
    -DMATERIALX_PYTHON_VERSION="%PY_VER%" ^
    -DPYTHON_EXECUTABLE="%PYTHON%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
