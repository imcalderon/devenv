@echo off
:: DevEnv Windows Installer
:: This batch file downloads and runs the DevEnv installer script
setlocal

echo DevEnv Windows Installer
echo ========================
echo.

:: Check for administrative privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Error: This script requires administrative privileges.
    echo Please right-click and select "Run as administrator".
    pause
    exit /b 1
)

:: Create temp directory
set TEMP_DIR=%TEMP%\devenv_installer
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

:: Download installer script
echo Downloading installer script...
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://https://github.com/imcalderon/devenv/install.ps1' -OutFile '%TEMP_DIR%\install.ps1'}"
if %errorLevel% neq 0 (
    echo Error: Failed to download installer script.
    pause
    exit /b 1
)

:: Ask user for installation options
echo.
echo Please select your WSL distribution:
echo 1) Ubuntu-20.04 (recommended)
echo 2) Ubuntu-22.04
echo 3) Debian
echo 4) Custom
set /p DISTRO_CHOICE="Enter your choice (1-4): "

set DISTRIBUTION=Ubuntu-20.04
if "%DISTRO_CHOICE%"=="2" set DISTRIBUTION=Ubuntu-22.04
if "%DISTRO_CHOICE%"=="3" set DISTRIBUTION=Debian
if "%DISTRO_CHOICE%"=="4" (
    set /p DISTRIBUTION="Enter the distribution name: "
)

echo.
echo Please specify your projects directory:
echo 1) E:\proj (recommended)
echo 2) Custom
set /p PROJECTS_CHOICE="Enter your choice (1-2): "

set PROJECTS_DIR=E:\proj
if "%PROJECTS_CHOICE%"=="2" (
    set /p PROJECTS_DIR="Enter the projects directory path: "
)

echo.
echo Force installation? (This will overwrite existing configurations)
echo 1) No (recommended)
echo 2) Yes
set /p FORCE_CHOICE="Enter your choice (1-2): "

set FORCE=false
if "%FORCE_CHOICE%"=="2" set FORCE=true

:: Run the PowerShell installer script
echo.
echo Starting installation...
echo Distribution: %DISTRIBUTION%
echo Projects Directory: %PROJECTS_DIR%
echo Force Installation: %FORCE%
echo.
echo This may take several minutes. Please be patient.
echo.

powershell -ExecutionPolicy Bypass -File "%TEMP_DIR%\install.ps1" -Distribution "%DISTRIBUTION%" -ProjectsDir "%PROJECTS_DIR%" -Force:%FORCE%

:: Clean up
rmdir /s /q "%TEMP_DIR%" >nul 2>&1

echo.
echo Installation completed. Press any key to exit...
pause >nul
exit /b 0