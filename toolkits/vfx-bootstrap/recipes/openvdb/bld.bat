@echo off
setlocal enabledelayedexpansion

REM OpenVDB build script for vfx-bootstrap (Windows)

mkdir build
cd build

cmake "%SRC_DIR%" ^
    -G Ninja ^
    -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
    -DOPENVDB_BUILD_CORE=ON ^
    -DOPENVDB_BUILD_BINARIES=ON ^
    -DOPENVDB_BUILD_PYTHON_MODULE=ON ^
    -DOPENVDB_BUILD_UNITTESTS=OFF ^
    -DOPENVDB_BUILD_DOCS=OFF ^
    -DUSE_BLOSC=ON ^
    -DUSE_ZLIB=ON ^
    -DUSE_EXR=ON ^
    -DUSE_TBB=ON ^
    -DUSE_NUMPY=ON ^
    -DPython_EXECUTABLE="%PYTHON%" ^
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
