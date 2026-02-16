@echo on
setlocal enabledelayedexpansion

REM Boost build script for vfx-bootstrap (Windows)
REM Uses same vswhere MSVC activation as imath recipe.
REM Aligned with OpenUSD build_usd.py boost build approach.

cd "%SRC_DIR%"

REM Activate MSVC environment (same as imath bld.bat)
set "VSWHERE=%BUILD_PREFIX%\Library\bin\vswhere.exe"
if not exist "%VSWHERE%" set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -property installationPath`) do set "VSINSTALL=%%i"
if defined VSINSTALL (
    call "%VSINSTALL%\VC\Auxiliary\Build\vcvarsall.bat" amd64
    if errorlevel 1 exit /b 1
)

REM Verify cl.exe is available
where cl.exe
if %ERRORLEVEL% neq 0 (
    echo ERROR: cl.exe not found on PATH after MSVC activation
    exit /b 1
)

REM Write user-config.jam with Python config only (no MSVC entry needed)
REM b2 auto-detects MSVC from the activated environment.
REM See https://github.com/boostorg/build/issues/194
echo using python > "%SRC_DIR%\user-config.jam"
echo : %PY_VER% >> "%SRC_DIR%\user-config.jam"
echo : %PYTHON:\=\\% >> "%SRC_DIR%\user-config.jam"
echo : %PREFIX:\=\\%\\include >> "%SRC_DIR%\user-config.jam"
echo : %PREFIX:\=\\%\\libs >> "%SRC_DIR%\user-config.jam"
echo ; >> "%SRC_DIR%\user-config.jam"
copy /Y "%SRC_DIR%\user-config.jam" "%USERPROFILE%\user-config.jam"

REM Bootstrap b2
call bootstrap.bat
if %ERRORLEVEL% neq 0 exit /b 1

@echo on

REM Build and install
REM toolset=msvc-14.3 = VC toolset version, matching OpenUSD build_usd.py
REM --layout=system gives clean lib names (boost_system.lib)
.\b2 install ^
    --prefix="%LIBRARY_PREFIX%" ^
    --build-dir=build ^
    toolset=msvc-14.3 ^
    address-model=64 ^
    variant=release ^
    threading=multi ^
    link=shared ^
    runtime-link=shared ^
    cxxstd=17 ^
    --layout=system ^
    --with-atomic ^
    --with-chrono ^
    --with-date_time ^
    --with-filesystem ^
    --with-iostreams ^
    --with-program_options ^
    --with-regex ^
    --with-system ^
    --with-thread ^
    -sNO_BZIP2=1 ^
    -sZLIB_INCLUDE="%LIBRARY_INC%" ^
    -sZLIB_LIBPATH="%LIBRARY_LIB%" ^
    -j%CPU_COUNT%
if %ERRORLEVEL% neq 0 exit /b 1
