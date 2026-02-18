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

REM OpenImageIO build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DCMAKE_CXX_STANDARD=17 ^
    -DCMAKE_CXX_FLAGS="/utf-8 /EHsc" ^
    -DUSE_PYTHON=ON ^
    -DPython_EXECUTABLE="%PYTHON%" ^
    -DPython_FIND_STRATEGY=LOCATION ^
    -DUSE_OPENCOLORIO=ON ^
    -DUSE_OPENVDB=ON ^
    -DUSE_PTEX=ON ^
    -DUSE_QT=OFF ^
    -DINSTALL_FONTS=OFF ^
    -DBUILD_TESTING=OFF ^
    -DOIIO_BUILD_TESTS=OFF ^
    -DOIIO_BUILD_TOOLS=ON ^
    -DBOOST_ROOT="%LIBRARY_PREFIX%" ^
    -DTBB_ROOT="%LIBRARY_PREFIX%" ^
    -DOpenEXR_ROOT="%LIBRARY_PREFIX%" ^
    -DImath_ROOT="%LIBRARY_PREFIX%" ^
    -DOpenColorIO_ROOT="%LIBRARY_PREFIX%" ^
    -DOpenVDB_ROOT="%LIBRARY_PREFIX%" ^
    -DPtex_ROOT="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

cmake --build . --parallel %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1

REM Move Python bindings to correct site-packages location
if exist "%LIBRARY_PREFIX%\lib\site-packages\OpenImageIO" (
    xcopy /E /I /Y "%LIBRARY_PREFIX%\lib\site-packages\OpenImageIO" "%SP_DIR%\OpenImageIO"
    rmdir /S /Q "%LIBRARY_PREFIX%\lib\site-packages\OpenImageIO"
)
if exist "%LIBRARY_PREFIX%\lib\python%PY_VER%\site-packages\OpenImageIO" (
    xcopy /E /I /Y "%LIBRARY_PREFIX%\lib\python%PY_VER%\site-packages\OpenImageIO" "%SP_DIR%\OpenImageIO"
    rmdir /S /Q "%LIBRARY_PREFIX%\lib\python%PY_VER%\site-packages\OpenImageIO"
)
