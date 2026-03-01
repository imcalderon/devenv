@echo on
setlocal enabledelayedexpansion

REM Boost build script for vfx-bootstrap on Windows

cd "%SRC_DIR%"

REM Bootstrap b2
REM Explicitly pass vc143 to avoid vcunk error on newer VS versions
call bootstrap.bat vc143
if %ERRORLEVEL% neq 0 exit /b 1

@echo on

REM Build and install
.\b2 install ^
    --prefix="%LIBRARY_PREFIX%" ^
    --build-dir=build ^
    toolset=msvc ^
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
    --with-python ^
    -sNO_BZIP2=1 ^
    -sZLIB_INCLUDE="%LIBRARY_INC%" ^
    -sZLIB_LIBPATH="%LIBRARY_LIB%" ^
    -j%CPU_COUNT%
if %ERRORLEVEL% neq 0 exit /b 1

REM Copy DLLs to bin for runtime PATH
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"
for %%f in ("%LIBRARY_LIB%\boost_*.dll") do (
    copy /Y "%%f" "%LIBRARY_BIN%\"
)
