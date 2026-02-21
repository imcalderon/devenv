#Requires -Version 5.1
<#
.SYNOPSIS
    Qt Creator Module for DevEnv - Windows implementation
.DESCRIPTION
    Installs and manages Qt Creator IDE using winget.
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

$script:ModuleName = "qtcreator"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'core',     # Qt Creator application
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
            # Check if qtcreator is in PATH or winget list
            try {
                $null = Get-Command qtcreator -ErrorAction SilentlyContinue
                if ($LASTEXITCODE -eq 0) { return $true }
                
                $installed = winget.exe list --exact --id Qt.QtCreator 2>&1
                return ($LASTEXITCODE -eq 0) -and ($installed -match "Qt.QtCreator")
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
    Write-LogInfo "Installing Qt Creator..." $script:ModuleName

    $packageId = Get-ModuleConfig $script:ModuleName ".package_id" "Qt.QtCreator"

    # Check if already installed
    if (Test-Component 'core') {
        Write-LogInfo "Qt Creator already installed" $script:ModuleName
        return $true
    }

    try {
        Write-LogInfo "Installing $packageId via winget..." $script:ModuleName
        winget.exe install --exact --id $packageId --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Qt Creator installed successfully" $script:ModuleName
            return $true
        } else {
            Write-LogError "winget install failed with code: $LASTEXITCODE" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Failed to install Qt Creator: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Configuring Qt Creator shell aliases..." $script:ModuleName
    if (Add-ModuleAliases $script:ModuleName "qt") {
        return $true
    }
    return $false
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
    $needsInstallation = $false
    foreach ($component in $script:Components) {
        if (-not (Test-ComponentState $component) -or -not (Test-Component $component)) {
            $needsInstallation = $true
            break
        }
    }
    return -not $needsInstallation
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

    Write-LogInfo "Qt Creator installation completed successfully" $script:ModuleName
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module configuration..." $script:ModuleName
    Remove-ModuleAliases $script:ModuleName "qt"
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    Write-LogWarning "Qt Creator application was preserved. Uninstall via Settings if needed." $script:ModuleName
    return $true
}

function Show-ModuleInfo {
    Write-Host "`nQt Creator IDE" -ForegroundColor Cyan
    Write-Host "==============`n" -ForegroundColor Cyan
    Write-Host "Status:" -NoNewline
    if (Test-ModuleInstallation) {
        Write-Host " Installed" -ForegroundColor Green
    } else {
        Write-Host " Not installed" -ForegroundColor Red
    }
    Write-Host "Description: Qt Creator IDE for cross-platform C++, QML and Python development`n"
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
