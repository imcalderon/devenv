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

REM OpenSubdiv build script for vfx-bootstrap (Windows)

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
    -DNO_EXAMPLES=ON ^
    -DNO_TUTORIALS=ON ^
    -DNO_REGRESSION=ON ^
    -DNO_DOC=ON ^
    -DNO_OMP=ON ^
    -DNO_CUDA=ON ^
    -DNO_OPENCL=ON ^
    -DNO_DX=ON ^
    -DNO_PTEX=ON ^
    -DNO_OPENGL=OFF ^
    -DNO_GLFW=ON ^
    -DNO_GLEW=ON ^
    -DNO_TBB=OFF ^
    -DTBB_LOCATION="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
