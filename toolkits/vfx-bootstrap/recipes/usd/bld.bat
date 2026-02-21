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

REM USD 24.11 build script for vfx-bootstrap (Windows)
REM This is the primary build target of the project

REM Clear conda-build's CMAKE_GENERATOR so -G Ninja takes effect
set "CMAKE_GENERATOR="
set "CMAKE_GENERATOR_PLATFORM="
set "CMAKE_GENERATOR_TOOLSET="

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DPXR_ENABLE_PYTHON_SUPPORT=ON ^
    -DPython_EXECUTABLE="%PYTHON%" ^
    -DPXR_BUILD_IMAGING=ON ^
    -DPXR_BUILD_USD_IMAGING=ON ^
    -DPXR_BUILD_USDVIEW=OFF ^
    -DPXR_BUILD_ALEMBIC_PLUGIN=ON ^
    -DPXR_BUILD_DRACO_PLUGIN=OFF ^
    -DPXR_BUILD_EMBREE_PLUGIN=OFF ^
    -DPXR_BUILD_PRMAN_PLUGIN=OFF ^
    -DPXR_BUILD_DOCUMENTATION=OFF ^
    -DPXR_BUILD_TESTS=OFF ^
    -DPXR_BUILD_EXAMPLES=OFF ^
    -DPXR_BUILD_TUTORIALS=OFF ^
    -DPXR_ENABLE_MATERIALX_SUPPORT=ON ^
    -DPXR_ENABLE_OPENSUBDIV_SUPPORT=ON ^
    -DPXR_ENABLE_OPENVDB_SUPPORT=ON ^
    -DPXR_ENABLE_PTEX_SUPPORT=ON ^
    -DPXR_BUILD_OPENGL_ENABLED=ON ^
    -DTBB_ROOT="%LIBRARY_PREFIX%" ^
    -DBOOST_ROOT="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1

REM Copy USD DLLs to bin/ for runtime PATH
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"
for %%f in ("%LIBRARY_LIB%\usd_*.dll") do copy /Y "%%f" "%LIBRARY_BIN%\"
