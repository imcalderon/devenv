#Requires -Version 5.1
<#
.SYNOPSIS
    VFX Module for DevEnv - Windows implementation
.DESCRIPTION
    Sets up a complete VFX Platform build environment on Windows with
    Visual Studio Build Tools, conda, vfx-bootstrap, and build dependencies.
    Provides tooling for building USD and dependencies against specific
    VFX Reference Platform versions using native MSVC.
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

$script:ModuleName = "vfx"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'build_deps',       # VS Build Tools, CMake, Ninja, NASM
    'conda_env',        # Conda environment for VFX build tools
    'vfx_bootstrap',    # Install vfx-bootstrap package into conda env
    'channels',         # Configure conda channels and local channel
    'shell',            # Shell aliases for VFX commands
    'platform_version'  # Write VFX Platform version specs
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

function Get-CondaExe {
    $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
    $condaExe = Join-Path $condaRoot "Scripts\conda.exe"
    if (Test-Path $condaExe) {
        return $condaExe
    }
    # Try PATH
    $condaPath = Get-Command conda -ErrorAction SilentlyContinue
    if ($condaPath) {
        return $condaPath.Source
    }
    return $null
}

function Test-Component {
    param([string]$Component)

    switch ($Component) {
        'build_deps' {
            try {
                $cmake = Get-Command cmake -ErrorAction SilentlyContinue
                $ninja = Get-Command ninja -ErrorAction SilentlyContinue
                return ($null -ne $cmake) -and ($null -ne $ninja)
            } catch {
                return $false
            }
        }
        'conda_env' {
            $condaExe = Get-CondaExe
            if (-not $condaExe) { return $false }
            try {
                $envList = & $condaExe env list 2>$null
                return ($envList -match "vfx-build")
            } catch {
                return $false
            }
        }
        'vfx_bootstrap' {
            $condaExe = Get-CondaExe
            if (-not $condaExe) { return $false }
            try {
                & $condaExe run -n vfx-build python -c "import builder" 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'channels' {
            $channelDir = Join-Path $env:USERPROFILE "Development\vfx\channel"
            return (Test-Path $channelDir) -and (Test-Path (Join-Path $channelDir "channeldata.json"))
        }
        'shell' {
            $aliasesFile = Join-Path (Get-AliasesDirectory) "aliases.ps1"
            return (Test-Path $aliasesFile) -and (Get-ModuleAliases $script:ModuleName)
        }
        'platform_version' {
            $platformFile = Join-Path $env:USERPROFILE ".vfx-devenv\platform.json"
            return (Test-Path $platformFile)
        }
        default {
            return $false
        }
    }
}
#endregion

#region Component Installation
function Install-BuildDepsComponent {
    Write-LogInfo "Installing build dependencies..." $script:ModuleName

    # Install via winget
    $wingetPackages = Get-ModuleConfig $script:ModuleName ".build_deps.windows.winget[]"
    if ($wingetPackages) {
        foreach ($pkg in $wingetPackages) {
            Write-LogInfo "Installing $pkg via winget..." $script:ModuleName
            try {
                # Check if already installed
                $installed = winget.exe list --exact --id $pkg 2>$null
                if ($LASTEXITCODE -eq 0 -and ($installed -match $pkg)) {
                    Write-LogInfo "$pkg already installed" $script:ModuleName
                    continue
                }
            } catch {}

            try {
                winget.exe install --exact --id $pkg --silent --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -ne 0) {
                    Write-LogWarning "winget install returned non-zero for $pkg (may already be installed)" $script:ModuleName
                }
            } catch {
                Write-LogWarning "Failed to install $pkg via winget: $_" $script:ModuleName
            }
        }
    }

    # Install VS workloads
    $vsWorkloads = Get-ModuleConfig $script:ModuleName ".build_deps.windows.vs_workloads[]"
    if ($vsWorkloads) {
        # Find VS installer
        $vsInstallerPaths = @(
            "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe",
            "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vs_installer.exe"
        )
        $vsInstaller = $null
        foreach ($path in $vsInstallerPaths) {
            if (Test-Path $path) {
                $vsInstaller = $path
                break
            }
        }

        if ($vsInstaller) {
            $addArgs = @("modify", "--installPath", "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools", "--quiet", "--norestart")
            foreach ($workload in $vsWorkloads) {
                $addArgs += "--add"
                $addArgs += $workload
            }

            Write-LogInfo "Installing VS workloads..." $script:ModuleName
            try {
                $proc = Start-Process -FilePath $vsInstaller -ArgumentList $addArgs -Wait -PassThru -NoNewWindow
                Write-LogInfo "VS installer exited with code: $($proc.ExitCode)" $script:ModuleName
            } catch {
                Write-LogWarning "Failed to install VS workloads: $_" $script:ModuleName
            }
        } else {
            Write-LogWarning "Visual Studio Installer not found. Install VS Build Tools first." $script:ModuleName
        }
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

    # Verify cmake and ninja
    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    $ninja = Get-Command ninja -ErrorAction SilentlyContinue
    if ($cmake -and $ninja) {
        Write-LogInfo "Build deps verified: cmake=$($cmake.Source), ninja=$($ninja.Source)" $script:ModuleName
        return $true
    }

    Write-LogWarning "Some build deps may need a shell restart to be found" $script:ModuleName
    return $true
}

function Install-CondaEnvComponent {
    Write-LogInfo "Setting up conda environment..." $script:ModuleName

    $condaExe = Get-CondaExe
    if (-not $condaExe) {
        Write-LogError "Conda not found. Install conda module first." $script:ModuleName
        return $false
    }

    $envName = Get-ModuleConfig $script:ModuleName ".conda.env_name"
    if ([string]::IsNullOrWhiteSpace($envName)) { $envName = "vfx-build" }

    # Accept conda channel TOS non-interactively
    try {
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>$null
        & $condaExe tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>$null
    } catch {}

    # Check if env already exists
    $envList = & $condaExe env list 2>$null
    if ($envList -match $envName) {
        Write-LogInfo "Conda environment '$envName' already exists, updating" $script:ModuleName
        $packages = Get-ModuleConfig $script:ModuleName ".conda.packages[]"
        if ($packages) {
            & $condaExe install -n $envName -y $packages
        }
        return $true
    }

    Write-LogInfo "Creating conda environment: $envName" $script:ModuleName
    $packages = Get-ModuleConfig $script:ModuleName ".conda.packages[]"
    if ($packages) {
        & $condaExe create -n $envName -y $packages
    } else {
        & $condaExe create -n $envName -y conda-build boa conda-verify
    }

    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Failed to create conda environment '$envName'" $script:ModuleName
        return $false
    }

    return $true
}

function Install-VfxBootstrapComponent {
    Write-LogInfo "Installing vfx-bootstrap..." $script:ModuleName

    $condaExe = Get-CondaExe
    if (-not $condaExe) {
        Write-LogError "Conda not found" $script:ModuleName
        return $false
    }

    $envName = Get-ModuleConfig $script:ModuleName ".conda.env_name"
    if ([string]::IsNullOrWhiteSpace($envName)) { $envName = "vfx-build" }

    $bootstrapDir = Join-Path $env:DEVENV_ROOT "toolkits\vfx-bootstrap"

    if (-not (Test-Path (Join-Path $bootstrapDir "setup.py"))) {
        Write-LogError "vfx-bootstrap not found at $bootstrapDir" $script:ModuleName
        return $false
    }

    Write-LogInfo "Installing vfx-bootstrap into $envName from $bootstrapDir" $script:ModuleName
    & $condaExe run -n $envName pip install -e $bootstrapDir
    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Failed to install vfx-bootstrap into '$envName'" $script:ModuleName
        return $false
    }

    return $true
}

function Install-ChannelsComponent {
    Write-LogInfo "Configuring VFX local channel..." $script:ModuleName

    $channelDir = Join-Path $env:USERPROFILE "Development\vfx\channel"

    # Create channel subdirectories
    foreach ($subdir in @("win-64", "noarch")) {
        $subdirPath = Join-Path $channelDir $subdir
        if (-not (Test-Path $subdirPath)) {
            New-Item -Path $subdirPath -ItemType Directory -Force | Out-Null
        }

        # Initialize repodata.json
        $repodataPath = Join-Path $subdirPath "repodata.json"
        $repodataContent = @"
{
    "info": {
        "subdir": "$subdir"
    },
    "packages": {},
    "packages.conda": {},
    "removed": [],
    "repodata_version": 1
}
"@
        Set-Content -Path $repodataPath -Value $repodataContent -Encoding UTF8
    }

    # Create channeldata.json
    $channeldataPath = Join-Path $channelDir "channeldata.json"
    $channeldataContent = @"
{
    "channeldata_version": 1,
    "packages": {},
    "subdirs": ["win-64", "noarch"]
}
"@
    Set-Content -Path $channeldataPath -Value $channeldataContent -Encoding UTF8

    # Add local channel to conda config
    $condaExe = Get-CondaExe
    if ($condaExe) {
        $channelUrl = "file:///$($channelDir -replace '\\', '/')"
        try {
            $channels = & $condaExe config --show channels 2>$null
            if (-not ($channels -match [regex]::Escape($channelDir))) {
                & $condaExe config --append channels $channelUrl
                Write-LogInfo "Added local VFX channel to conda config" $script:ModuleName
            }
        } catch {
            Write-LogWarning "Could not add local channel to conda config: $_" $script:ModuleName
        }
    }

    # Create output directories
    $buildOutput = Join-Path $env:USERPROFILE "Development\vfx\builds"
    $packageOutput = Join-Path $env:USERPROFILE "Development\vfx\packages"
    foreach ($dir in @($buildOutput, $packageOutput)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    Write-LogInfo "VFX channel configured at: $channelDir" $script:ModuleName
    return $true
}

function Install-ShellComponent {
    Write-LogInfo "Configuring VFX shell aliases..." $script:ModuleName

    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"

    if ($aliasCategories) {
        foreach ($category in $aliasCategories) {
            if (Add-ModuleAliases $script:ModuleName $category) {
                Write-LogInfo "Added aliases for category: $category" $script:ModuleName
            } else {
                Write-LogWarning "Failed to add aliases for category: $category" $script:ModuleName
            }
        }
    } else {
        if (Add-ModuleAliases $script:ModuleName "vfx") {
            Write-LogInfo "Added vfx aliases" $script:ModuleName
        }
    }

    return $true
}

function Install-PlatformVersionComponent {
    Write-LogInfo "Writing VFX Platform version specs..." $script:ModuleName

    $vfxHome = Join-Path $env:USERPROFILE ".vfx-devenv"
    if (-not (Test-Path $vfxHome)) {
        New-Item -Path $vfxHome -ItemType Directory -Force | Out-Null
    }

    $platformFile = Join-Path $vfxHome "platform.json"

    # Read version specs from module config
    $vfx2024 = Get-ModuleConfig $script:ModuleName ".vfx_platform.`"2024`""
    $vfx2025 = Get-ModuleConfig $script:ModuleName ".vfx_platform.`"2025`""

    $platformData = @{
        active_version = "2025"
        versions = @{
            "2024" = $vfx2024
            "2025" = $vfx2025
        }
        installed_at = (Get-Date -Format "o")
        devenv_root = $env:DEVENV_ROOT
    }

    $platformData | ConvertTo-Json -Depth 4 | Set-Content -Path $platformFile -Encoding UTF8
    Write-LogInfo "Platform version specs written to: $platformFile" $script:ModuleName

    return $true
}
#endregion

#region Main Module Functions
function Install-Component {
    param([string]$Component)

    if ((Test-ComponentState $Component) -and (Test-Component $Component) -and -not $Force) {
        Write-LogInfo "Component $Component already installed and verified" $script:ModuleName
        return $true
    }

    $result = switch ($Component) {
        'build_deps' { Install-BuildDepsComponent }
        'conda_env' { Install-CondaEnvComponent }
        'vfx_bootstrap' { Install-VfxBootstrapComponent }
        'channels' { Install-ChannelsComponent }
        'shell' { Install-ShellComponent }
        'platform_version' { Install-PlatformVersionComponent }
        default {
            Write-LogError "Unknown component: $Component" $script:ModuleName
            $false
        }
    }

    if ($result) {
        Save-ComponentState $Component 'installed'
        Write-LogInfo "Successfully installed component: $Component" $script:ModuleName
    } else {
        Write-LogError "Failed to install component: $Component" $script:ModuleName
    }

    return $result
}

function Test-ModuleInstallation {
    Write-LogInfo "Checking VFX module installation status..." $script:ModuleName

    $needsInstallation = $false

    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component

        if (-not $isInstalled -or -not $isVerified) {
            Write-LogInfo "Component $component needs installation" $script:ModuleName
            $needsInstallation = $true
        }
    }

    return -not $needsInstallation
}

function Install-Module {
    Write-LogInfo "Installing $($script:ModuleName) module..." $script:ModuleName

    if (-not $Force -and (Test-ModuleInstallation)) {
        Write-LogInfo "Module already installed and verified" $script:ModuleName
        Show-ModuleInfo
        return $true
    }

    # Create backup before installation
    New-Backup $script:ModuleName

    # Install each component
    foreach ($component in $script:Components) {
        Write-LogInfo "Installing component: $component" $script:ModuleName

        if (-not (Install-Component $component)) {
            Write-LogError "Failed to install component: $component" $script:ModuleName
            return $false
        }
    }

    Write-LogInfo "VFX module installation completed successfully" $script:ModuleName
    Show-ModuleInfo

    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName

    # Create backup before removal
    New-Backup $script:ModuleName

    # Remove shell aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    if ($aliasCategories) {
        foreach ($category in $aliasCategories) {
            Remove-ModuleAliases $script:ModuleName $category
        }
    } else {
        Remove-ModuleAliases $script:ModuleName "vfx"
    }

    # Remove local channel from conda config
    $condaExe = Get-CondaExe
    if ($condaExe) {
        $channelDir = Join-Path $env:USERPROFILE "Development\vfx\channel"
        $channelUrl = "file:///$($channelDir -replace '\\', '/')"
        try {
            & $condaExe config --remove channels $channelUrl 2>$null
        } catch {}
    }

    # Remove channel directory
    $channelDir = Join-Path $env:USERPROFILE "Development\vfx\channel"
    if (Test-Path $channelDir) {
        Remove-Item $channelDir -Recurse -Force
    }

    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }

    Write-LogInfo "VFX module configuration removed" $script:ModuleName
    Write-LogWarning "Conda environment 'vfx-build' preserved. Run: conda env remove -n vfx-build" $script:ModuleName
    Write-LogWarning "VFX home preserved at ~\.vfx-devenv. Remove manually if desired." $script:ModuleName

    return $true
}

function Test-ModuleVerification {
    Write-LogInfo "Verifying $($script:ModuleName) module installation..." $script:ModuleName

    $allVerified = $true

    foreach ($component in $script:Components) {
        if (-not (Test-Component $component)) {
            Write-LogError "Verification failed for component: $component" $script:ModuleName
            $allVerified = $false
        } else {
            Write-LogInfo "Component verified: $component" $script:ModuleName
        }
    }

    if ($allVerified) {
        Write-LogInfo "VFX module verification completed successfully" $script:ModuleName
    }

    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

VFX Platform Development Environment (Windows)
================================================

Description:
-----------
Complete VFX Platform build and development environment powered by
vfx-bootstrap. Provides tooling for building USD and dependencies
against specific VFX Reference Platform versions using native MSVC.

Components:
----------
1. Build Dependencies
   - Visual Studio 2022 Build Tools (MSVC)
   - CMake, Ninja, NASM

2. Conda Environment (vfx-build)
   - conda-build, boa, conda-verify
   - Isolated build environment

3. VFX Bootstrap
   - builder: Python build orchestration for VFX packages
   - packager: Format-agnostic package creation
   - recipes: Conda build recipes for VFX dependencies

4. Local Channel
   - Conda channel for built VFX packages (win-64)
   - Automatic channel configuration

5. Shell Aliases
   - vfx-build, vfx-list, vfx-clean, vfx-info

6. Platform Version
   - VFX Platform 2024/2025 version specs

Quick Start:
-----------
1. List available recipes:
   vfx-list

2. Build a package:
   vfx-build openexr

3. Build the full stack:
   vfx-build usd

"@

    Write-Host $header -ForegroundColor Cyan

    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow

    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component

        if ($isInstalled -and $isVerified) {
            Write-Host "+ $component`: Installed and verified" -ForegroundColor Green
        } elseif ($isInstalled) {
            Write-Host "[WARN] $component`: Installed but not verified" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] $component`: Not installed" -ForegroundColor Red
        }
    }

    # Show platform version if available
    $platformFile = Join-Path $env:USERPROFILE ".vfx-devenv\platform.json"
    if (Test-Path $platformFile) {
        Write-Host ""
        Write-Host "VFX Platform Version:" -ForegroundColor Yellow
        Write-Host "--------------------" -ForegroundColor Yellow
        try {
            $platformData = Get-Content $platformFile -Raw | ConvertFrom-Json
            Write-Host "  Active: VFX Platform $($platformData.active_version)" -ForegroundColor Gray
        } catch {}
    }

    Write-Host ""
}
#endregion

#region Main Execution
try {
    switch ($Action.ToLower()) {
        'grovel' {
            if (Test-ModuleInstallation) { exit 0 } else { exit 1 }
        }
        'install' {
            $success = Install-Module
            if ($success) { exit 0 } else { exit 1 }
        }
        'remove' {
            $success = Remove-Module
            if ($success) { exit 0 } else { exit 1 }
        }
        'verify' {
            $success = Test-ModuleVerification
            if ($success) { exit 0 } else { exit 1 }
        }
        'info' {
            Show-ModuleInfo
            exit 0
        }
        default {
            Write-LogError "Unknown action: $Action" $script:ModuleName
            Write-LogError "Usage: $($MyInvocation.MyCommand.Name) {install|remove|verify|info|grovel} [-Force]" $script:ModuleName
            exit 1
        }
    }
}
catch {
    Write-LogError "Module execution failed: $_" $script:ModuleName
    Write-LogError "Stack trace: $($_.ScriptStackTrace)" $script:ModuleName
    exit 1
}
#endregion
