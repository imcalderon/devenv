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

REM TBB build script for vfx-bootstrap (Windows)
REM TBB 2020.3 uses Make (not CMake). oneTBB 2021+ uses CMake.

REM Detect if this is classic TBB (Make-based) or oneTBB (CMake-based)
if exist "%SRC_DIR%\CMakeLists.txt" (
    REM oneTBB 2021+ (CMake-based)
    mkdir build
    cd build

    cmake "%SRC_DIR%" ^
        -G Ninja ^
        -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
        -DCMAKE_BUILD_TYPE=Release ^
        -DCMAKE_PREFIX_PATH="%LIBRARY_PREFIX%" ^
        -DTBB_TEST=OFF ^
        -DTBB_STRICT=OFF
    if errorlevel 1 exit /b 1

    cmake --build . --parallel %CPU_COUNT%
    if errorlevel 1 exit /b 1

    cmake --install .
    if errorlevel 1 exit /b 1
) else (
    REM Classic TBB 2020.x
    REM Try CMake build if available
    if exist "%SRC_DIR%\cmake\TBBBuild.cmake" (
        mkdir build
        cd build

        cmake "%SRC_DIR%" ^
            -G Ninja ^
            -DCMAKE_INSTALL_PREFIX="%LIBRARY_PREFIX%" ^
            -DCMAKE_BUILD_TYPE=Release ^
            -DTBB_BUILD_TESTS=OFF
        if errorlevel 1 goto manual_install

        cmake --build . --parallel %CPU_COUNT%
        if errorlevel 1 goto manual_install

        cmake --install .
        if errorlevel 1 goto manual_install
        goto done
    )

    :manual_install
    REM Manual installation for classic TBB without CMake support
    cd "%SRC_DIR%"

    REM Install headers
    if not exist "%LIBRARY_PREFIX%\include\tbb" mkdir "%LIBRARY_PREFIX%\include\tbb"
    xcopy /E /Y /I include\tbb "%LIBRARY_PREFIX%\include\tbb"
    if errorlevel 1 exit /b 1

    REM Build with MSBuild if build files exist
    if exist "%SRC_DIR%\build\vs2013\makefile.sln" (
        msbuild build\vs2013\makefile.sln /p:Configuration=Release /p:Platform=x64
        if errorlevel 1 exit /b 1
    )

    REM Create cmake config for downstream packages
    if not exist "%LIBRARY_PREFIX%\lib\cmake\TBB" mkdir "%LIBRARY_PREFIX%\lib\cmake\TBB"

    (
        echo # Minimal TBB CMake config for classic TBB 2020.x ^(Windows^)
        echo get_filename_component^(_tbb_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE^)
        echo.
        echo add_library^(TBB::tbb SHARED IMPORTED^)
        echo set_target_properties^(TBB::tbb PROPERTIES
        echo     INTERFACE_INCLUDE_DIRECTORIES "${_tbb_root}/include"
        echo     IMPORTED_IMPLIB "${_tbb_root}/lib/tbb.lib"
        echo     IMPORTED_LOCATION "${_tbb_root}/bin/tbb.dll"
        echo ^)
        echo.
        echo add_library^(TBB::tbbmalloc SHARED IMPORTED^)
        echo set_target_properties^(TBB::tbbmalloc PROPERTIES
        echo     INTERFACE_INCLUDE_DIRECTORIES "${_tbb_root}/include"
        echo     IMPORTED_IMPLIB "${_tbb_root}/lib/tbbmalloc.lib"
        echo     IMPORTED_LOCATION "${_tbb_root}/bin/tbbmalloc.dll"
        echo ^)
        echo.
        echo set^(TBB_FOUND TRUE^)
        echo set^(TBB_VERSION "2020.3"^)
    ) > "%LIBRARY_PREFIX%\lib\cmake\TBB\TBBConfig.cmake"

    :done
)
