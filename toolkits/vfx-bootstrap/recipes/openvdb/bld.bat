@echo off
setlocal enabledelayedexpansion

REM MSVC is activated by conda via vs2022_compiler_vars.bat before bld.bat runs.
REM Only call vcvarsall.bat directly if cl.exe is not yet on PATH.
where cl.exe >nul 2>&1
if %errorlevel% neq 0 (
    set "VSWHERE=%BUILD_PREFIX%\Library\bin\vswhere.exe"
    if not exist "!VSWHERE!" set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -property installationPath`) do set "VSINSTALL=%%i"
    if defined VSINSTALL call "!VSINSTALL!\VC\Auxiliary\Build\vcvarsall.bat" amd64
)
where cl.exe >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: MSVC compiler ^(cl.exe^) not found.
    echo Please install VS 2022 Build Tools with the C++ workload:
    echo   winget install Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --includeRecommended"
    exit /b 1
)

REM OpenVDB build script for vfx-bootstrap (Windows)
REM Python module disabled on Windows: pyGrid.h uses POSIX ssize_t which MSVC
REM lacks. Core C++ library builds fine; downstream packages (OIIO, USD) only
REM need the C++ lib. Revisit when OpenVDB upstream fixes MSVC Python support.

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DOPENVDB_BUILD_CORE=ON ^
    -DOPENVDB_BUILD_BINARIES=ON ^
    -DOPENVDB_BUILD_PYTHON_MODULE=OFF ^
    -DOPENVDB_BUILD_UNITTESTS=OFF ^
    -DOPENVDB_BUILD_DOCS=OFF ^
    -DUSE_BLOSC=ON ^
    -DUSE_ZLIB=ON ^
    -DUSE_EXR=ON ^
    -DUSE_TBB=ON ^
    -DTBB_ROOT="%LIBRARY_PREFIX%" ^
    -DBLOSC_ROOT="%LIBRARY_PREFIX%" ^
    -DOpenEXR_ROOT="%LIBRARY_PREFIX%" ^
    -DImath_ROOT="%LIBRARY_PREFIX%" ^
    -DBOOST_ROOT="%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

REM OpenVDB template instantiations are extremely memory-heavy (~2GB each).
REM Limit parallelism to avoid OOM.
set PARALLEL_JOBS=%CPU_COUNT%
if %PARALLEL_JOBS% GTR 2 set PARALLEL_JOBS=2

cmake --build . --parallel %PARALLEL_JOBS%
if errorlevel 1 exit /b 1

cmake --install .
if errorlevel 1 exit /b 1
