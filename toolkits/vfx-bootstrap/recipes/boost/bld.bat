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
