#Requires -Version 5.1
<#
.SYNOPSIS
    mkInstaller Module for DevEnv - Windows implementation
.DESCRIPTION
    Sets up the mkInstaller system and its dependency ModernArchive.
#>

param (
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'grovel')]
    [string]$Action,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Initialization
$libPath = Join-Path $env:DEVENV_ROOT "lib\windows"
$requiredModules = @('logging.ps1', 'json.ps1', 'module.ps1', 'backup.ps1', 'alias.ps1')

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $libPath $module
    if (Test-Path $modulePath) {
        . $modulePath
    } else {
        Write-Error "Required module not found: $modulePath"
        exit 1
    }
}

$script:ModuleName = "mkinstaller"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:InstallPath = [System.Environment]::ExpandEnvironmentVariables((Get-ModuleConfig $script:ModuleName ".install_path"))
$script:ArchivePath = [System.Environment]::ExpandEnvironmentVariables((Get-ModuleConfig $script:ModuleName ".modern_archive_path"))

$script:Components = @(
    'modern_archive',   # C++ Self-extracting archive tool
    'mkinstaller_core', # Python installer builder
    'db_init',          # Database initialization
    'aliases'           # Command aliases
)
#endregion

#region State Management
function Save-ComponentState {
    param([string]$Component, [string]$Status)
    $stateDir = Split-Path $script:StateFile -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }
    $timestamp = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
    Add-Content -Path $script:StateFile -Value "$Component`:$Status`:$timestamp"
    Write-LogInfo "Saved state for component: $Component ($Status)" $script:ModuleName
}

function Test-ComponentState {
    param([string]$Component)
    if (Test-Path $script:StateFile) {
        $content = Get-Content $script:StateFile
        return ($content -match "^$Component`:installed:")
    }
    return $false
}

function Test-Component {
    param([string]$Component)
    switch ($Component) {
        'modern_archive' {
            $exePath = Join-Path $script:ArchivePath "build\Release\archive.exe"
            return (Test-Path $exePath)
        }
        'mkinstaller_core' {
            return (Test-Path (Join-Path $script:InstallPath "run_installer_build.py"))
        }
        'db_init' {
            return (Test-Path (Join-Path $script:InstallPath "installer.db"))
        }
        'aliases' {
            $aliasesFile = Join-Path (Get-AliasesDirectory) "aliases.ps1"
            return (Test-Path $aliasesFile) -and (Get-ModuleAliases $script:ModuleName)
        }
        default { return $false }
    }
}
#endregion

#region Component Installation
function Install-ModernArchive {
    Write-LogInfo "Ensuring ModernArchive is built..." $script:ModuleName
    
    if (-not (Test-Path $script:ArchivePath)) {
        Write-LogInfo "Cloning ModernArchive..." $script:ModuleName
        & gh repo clone imcalderon/ModernArchive $script:ArchivePath
    }

    $buildDir = Join-Path $script:ArchivePath "build"
    if (-not (Test-Path $buildDir)) {
        New-Item -Path $buildDir -ItemType Directory -Force | Out-Null
    }

    # Locate and activate Visual Studio environment
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) {
            $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $vcvars) {
                Write-LogInfo "Activating VS environment: $vcvars" $script:ModuleName
                
                # Capture environment variables from cmd /c call
                $cmdOutput = cmd.exe /c "`"$vcvars`" >nul && set"
                
                foreach ($line in $cmdOutput) {
                    if ($line -match "^(.*?)=(.*)$") {
                        $name = $matches[1]
                        $value = $matches[2]
                        # Only set if not already set or different (to avoid read-only var errors)
                        try {
                            if (-not (Test-Path "env:\$name") -or (Get-Content "env:\$name" -ErrorAction SilentlyContinue) -ne $value) {
                                Set-Item -Path "env:\$name" -Value $value -ErrorAction SilentlyContinue
                            }
                        } catch {}
                    }
                }
            }
        }
    }

    Write-LogInfo "Building ModernArchive with CMake..." $script:ModuleName
    Push-Location $buildDir
    try {
        $condaPrefix = Join-Path $env:USERPROFILE "miniconda3\Library"
        & cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$condaPrefix"
        & cmake --build . --config Release
    } finally {
        Pop-Location
    }

    if (Test-Component 'modern_archive') {
        Write-LogInfo "ModernArchive built successfully" $script:ModuleName
        return $true
    }
    return $false
}

function Install-MkInstallerCore {
    Write-LogInfo "Ensuring mkInstaller is ready..." $script:ModuleName
    
    if (-not (Test-Path $script:InstallPath)) {
        Write-LogInfo "Cloning mkInstaller..." $script:ModuleName
        & gh repo clone imcalderon/mkInstaller $script:InstallPath
    }

    Write-LogInfo "Installing Python dependencies..." $script:ModuleName
    $reqFile = Join-Path $script:InstallPath "requirements.txt"
    & python -m pip install -r $reqFile --quiet

    # Patch the hardcoded path in make_pfw.py
    $makePfwFile = Join-Path $script:InstallPath "actions\make_pfw.py"
    if (Test-Path $makePfwFile) {
        $exePath = Join-Path $script:ArchivePath "build\Release\archive.exe"
        $content = Get-Content $makePfwFile -Raw
        # Replace the hardcoded path with the expanded one (escaping backslashes for python string)
        $escapedExePath = $exePath -replace "\\", "\\\\"
        $search = [regex]::Escape("DEFAULT_ARCHIVE_EXE = r'E:\proj\ModernArchive\build\Release\archive.exe'")
        $newContent = $content -replace $search, "DEFAULT_ARCHIVE_EXE = r'$escapedExePath'"
        Set-Content -Path $makePfwFile -Value $newContent -Encoding UTF8
        Write-LogInfo "Patched ModernArchive path in mkInstaller" $script:ModuleName
    }

    return $true
}

function Install-DbInit {
    Write-LogInfo "Initializing mkInstaller database..." $script:ModuleName
    
    $condaPython = Join-Path $env:USERPROFILE "miniconda3\python.exe"
    
    # Ensure dependencies are installed (redundant check but safe)
    $reqFile = Join-Path $script:InstallPath "requirements.txt"
    & $condaPython -m pip install -r $reqFile --quiet

    Push-Location $script:InstallPath
    try {
        Write-LogInfo "Running db.init_db..." $script:ModuleName
        $output = & $condaPython -m db.init_db 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Database initialization failed: $output" $script:ModuleName
            return $false
        }
        Write-LogInfo "Database initialized: $output" $script:ModuleName
    } finally {
        Pop-Location
    }
    return $true
}

function Install-AliasesComponent {
    Write-LogInfo "Configuring mkInstaller aliases..." $script:ModuleName
    return Add-ModuleAliases $script:ModuleName "installer"
}
#endregion

#region Main Module Functions
function Install-Component {
    param([string]$Component)
    if ((Test-ComponentState $Component) -and (Test-Component $Component) -and -not $Force) {
        return $true
    }
    $result = switch ($Component) {
        'modern_archive'   { Install-ModernArchive }
        'mkinstaller_core' { Install-MkInstallerCore }
        'db_init'          { Install-DbInit }
        'aliases'          { Install-AliasesComponent }
    }
    if ($result) { Save-ComponentState $Component 'installed' }
    return $result
}

function Install-Module {
    Write-LogInfo "Installing $($script:ModuleName) module..." $script:ModuleName
    foreach ($component in $script:Components) {
        if (-not (Install-Component $component)) {
            Write-LogError "Failed to install component: $component" $script:ModuleName
            return $false
        }
    }
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) configuration..." $script:ModuleName
    Remove-ModuleAliases $script:ModuleName "installer"
    if (Test-Path $script:StateFile) { Remove-Item $script:StateFile -Force }
    return $true
}

function Show-ModuleInfo {
    Write-Host "`nmkInstaller System" -ForegroundColor Cyan
    Write-Host "==================`n" -ForegroundColor Cyan
    Write-Host "Status: " -NoNewline
    if (Test-Component 'mkinstaller_core') { Write-Host "Installed" -ForegroundColor Green } else { Write-Host "Not installed" -ForegroundColor Red }
    Write-Host "Path:   $script:InstallPath"
    Write-Host "ModernArchive: " -NoNewline
    if (Test-Component 'modern_archive') { Write-Host "Built" -ForegroundColor Green } else { Write-Host "Not built" -ForegroundColor Red }
    Write-Host "`nAliases:"
    Write-Host "  mki      - Run installer build"
    Write-Host "  mki-web  - Start management web API`n"
}
#endregion

#region Main Execution
try {
    switch ($Action.ToLower()) {
        'grovel' { exit (if (Test-Component 'mkinstaller_core') { 0 } else { 1 }) }
        'install' { exit (if (Install-Module) { 0 } else { 1 }) }
        'remove' { exit (if (Remove-Module) { 0 } else { 1 }) }
        'verify' { exit (if (Test-Component 'mkinstaller_core') { 0 } else { 1 }) }
        'info' { Show-ModuleInfo; exit 0 }
    }
} catch {
    Write-LogError "Module execution failed: $_" $script:ModuleName
    exit 1
}
#endregion
