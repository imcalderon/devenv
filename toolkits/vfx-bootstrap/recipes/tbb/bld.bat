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

REM oneTBB 2021.x build script for vfx-bootstrap (Windows)
REM Uses standard CMake build — oneTBB has root CMakeLists.txt

cd "%SRC_DIR%"

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
