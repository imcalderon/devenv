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

REM Move Python bindings from Library/lib/site-packages to Lib/site-packages
REM OCIO installs to CMAKE_INSTALL_PREFIX/lib/site-packages but conda expects PREFIX/Lib/site-packages
if exist "%LIBRARY_PREFIX%\lib\site-packages\PyOpenColorIO" (
    xcopy /E /I /Y "%LIBRARY_PREFIX%\lib\site-packages\PyOpenColorIO" "%SP_DIR%\PyOpenColorIO"
    rmdir /S /Q "%LIBRARY_PREFIX%\lib\site-packages\PyOpenColorIO"
)
