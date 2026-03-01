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
    -DCMAKE_INSTALL_BINDIR=bin ^
    -DCMAKE_INSTALL_LIBDIR=lib ^
    -DPXR_ENABLE_PYTHON_SUPPORT=ON ^
    -DPython_EXECUTABLE="%PYTHON%" ^
    -DPXR_BUILD_IMAGING=ON ^
    -DPXR_BUILD_USD_IMAGING=ON ^
    -DPXR_BUILD_USDVIEW=ON ^
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

REM --- Windows Post-Install Fixes ---

REM 1. Move USD DLLs to bin/ (cmake may still install some to lib/ despite BINDIR hint).
REM    Move (not copy) to ensure only one copy exists — duplicate DLLs cause
REM    DLL_INIT_FAILED when the USD plugin system loads them a second time.
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"
for %%f in ("%LIBRARY_LIB%\usd_*.dll") do (
    move /Y "%%f" "%LIBRARY_BIN%\"
)

REM 2. Fix plugInfo.json LibraryPath entries to point to bin/ instead of lib/.
REM    cmake generates these paths relative to the build-time DLL location (lib/),
REM    but after the move above the DLLs are in bin/.
"%PYTHON%" "%RECIPE_DIR%\fix_pluginfo.py" "%LIBRARY_PREFIX%"
if errorlevel 1 exit /b 1

REM 3. Move pxr python module to site-packages where Conda expects it
set "PYTHON_DEST=%PREFIX%\Lib\site-packages"
if not exist "%PYTHON_DEST%" mkdir "%PYTHON_DEST%"

REM USD usually installs to LIBRARY_PREFIX\lib\python or LIBRARY_PREFIX\python
if exist "%LIBRARY_PREFIX%\lib\python\pxr" (
    move "%LIBRARY_PREFIX%\lib\python\pxr" "%PYTHON_DEST%\"
) else if exist "%LIBRARY_PREFIX%\python\pxr" (
    move "%LIBRARY_PREFIX%\python\pxr" "%PYTHON_DEST%\"
)

REM 4. Install conda activation scripts so PXR_PLUGINPATH_NAME is set automatically.
REM    USD bakes PXR_INSTALL_LOCATION at build time; the activation script overrides
REM    this so plugins are found in the installed environment.
set "ACT_D=%PREFIX%\etc\conda\activate.d"
set "DEACT_D=%PREFIX%\etc\conda\deactivate.d"
if not exist "%ACT_D%" mkdir "%ACT_D%"
if not exist "%DEACT_D%" mkdir "%DEACT_D%"

REM Use %%CONDA_PREFIX%% so the variable expands at activation time, not build time
(echo @echo off
 echo set "PXR_PLUGINPATH_NAME=%%CONDA_PREFIX%%\Library\lib\usd;%%CONDA_PREFIX%%\Library\plugin\usd"
) > "%ACT_D%\usd-vars.bat"

(echo @echo off
 echo set "PXR_PLUGINPATH_NAME="
) > "%DEACT_D%\usd-vars.bat"

(echo $env:PXR_PLUGINPATH_NAME = "$env:CONDA_PREFIX\Library\lib\usd;$env:CONDA_PREFIX\Library\plugin\usd"
) > "%ACT_D%\usd-vars.ps1"

(echo $env:PXR_PLUGINPATH_NAME = ""
) > "%DEACT_D%\usd-vars.ps1"

exit /b 0