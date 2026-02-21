#Requires -Version 5.1
<#
.SYNOPSIS
    Bazel Module for DevEnv - Windows implementation
.DESCRIPTION
    Installs and manages Bazel (via Bazelisk) using winget.
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
        Write-Error "Required library not found: $modulePath"
        exit 1
    }
}

$script:ModuleName = "bazel"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'core',     # Bazelisk installation
    'aliases'   # Shell integration
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
        'core' {
            try {
                $null = Get-Command bazel -ErrorAction SilentlyContinue
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'aliases' {
            $aliasesFile = Join-Path (Get-AliasesDirectory) "aliases.ps1"
            return (Test-Path $aliasesFile) -and (Get-ModuleAliases $script:ModuleName)
        }
        default {
            return $false
        }
    }
}
#endregion

#region Component Installation
function Install-CoreComponent {
    Write-LogInfo "Installing Bazelisk (Bazel manager)..." $script:ModuleName

    $packageId = Get-ModuleConfig $script:ModuleName ".package_id" "Bazel.Bazelisk"

    if (Test-Component 'core') {
        Write-LogInfo "Bazel already installed" $script:ModuleName
        return $true
    }

    try {
        Write-LogInfo "Installing $packageId via winget..." $script:ModuleName
        winget.exe install --exact --id $packageId --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Bazel (Bazelisk) installed successfully" $script:ModuleName
            return $true
        }
        return $false
    } catch {
        Write-LogError "Failed to install Bazel: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Configuring Bazel shell aliases..." $script:ModuleName
    return Add-ModuleAliases $script:ModuleName "bazel"
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
        'core' { Install-CoreComponent }
        'aliases' { Install-AliasesComponent }
        default {
            Write-LogError "Unknown component: $Component" $script:ModuleName
            $false
        }
    }

    if ($result) {
        Save-ComponentState $Component 'installed'
    }

    return $result
}

function Test-ModuleInstallation {
    foreach ($component in $script:Components) {
        if (-not (Test-ComponentState $component) -or -not (Test-Component $component)) {
            return $false
        }
    }
    return $true
}

function Install-Module {
    Write-LogInfo "Installing $($script:ModuleName) module..." $script:ModuleName

    if (-not $Force -and (Test-ModuleInstallation)) {
        Write-LogInfo "Module already installed and verified" $script:ModuleName
        return $true
    }

    foreach ($component in $script:Components) {
        if (-not (Install-Component $component)) {
            Write-LogError "Failed to install component: $component" $script:ModuleName
            return $false
        }
    }

    Write-LogInfo "Bazel installation completed successfully" $script:ModuleName
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module configuration..." $script:ModuleName
    Remove-ModuleAliases $script:ModuleName "bazel"
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    Write-LogWarning "Bazel application was preserved. Uninstall via winget if needed." $script:ModuleName
    return $true
}

function Show-ModuleInfo {
    Write-Host "`nBazel (via Bazelisk)" -ForegroundColor Cyan
    Write-Host "====================`n" -ForegroundColor Cyan
    Write-Host "Status:" -NoNewline
    if (Test-ModuleInstallation) {
        Write-Host " Installed" -ForegroundColor Green
    } else {
        Write-Host " Not installed" -ForegroundColor Red
    }
    Write-Host "Description: Hermetic build system with multi-language support`n"
}
#endregion

#region Main Execution
try {
    switch ($Action.ToLower()) {
        'grovel' {
            if (Test-ModuleInstallation) { exit 0 } else { exit 1 }
        }
        'install' {
            if (Install-Module) { exit 0 } else { exit 1 }
        }
        'remove' {
            if (Remove-Module) { exit 0 } else { exit 1 }
        }
        'verify' {
            if (Test-ModuleInstallation) { exit 0 } else { exit 1 }
        }
        'info' {
            Show-ModuleInfo
            exit 0
        }
    }
}
catch {
    Write-LogError "Module execution failed: $_" $script:ModuleName
    exit 1
}
#endregion
