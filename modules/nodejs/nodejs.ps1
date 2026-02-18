#Requires -Version 5.1
<#
.SYNOPSIS
    Node.js Module for DevEnv - Windows implementation
.DESCRIPTION
    Configures Node.js for Windows with global npm packages,
    npm configuration, and productivity aliases. Uses system Node.js
    installed via winget (no nvm on Windows).
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

$script:ModuleName = "nodejs"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # Node.js installation verification
    'packages',     # Global npm packages
    'config',       # npm configuration
    'aliases'       # Command aliases
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
                $null = node --version 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'packages' {
            try {
                # Check if at least some global packages are installed
                $globalPackages = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json
                if ($globalPackages -and $globalPackages.dependencies) {
                    return $true
                }
                # No global packages yet is ok if state says installed
                return Test-ComponentState 'packages'
            } catch {
                return $false
            }
        }
        'config' {
            try {
                $saveExact = npm config get save-exact 2>$null
                return $saveExact -eq "true"
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
    Write-LogInfo "Verifying Node.js installation..." $script:ModuleName

    try {
        $nodeVersion = node --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Node.js is installed: $nodeVersion" $script:ModuleName

            $npmVersion = npm --version 2>$null
            Write-LogInfo "npm version: $npmVersion" $script:ModuleName

            return $true
        }
    } catch {}

    # Attempt install via winget
    try {
        Write-LogInfo "Installing Node.js via winget..." $script:ModuleName
        winget.exe install --exact --id OpenJS.NodeJS --silent --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Node.js installed successfully via winget" $script:ModuleName

            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 3

            try {
                $nodeVersion = node --version 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-LogInfo "Node.js installation verified: $nodeVersion" $script:ModuleName
                    return $true
                }
            } catch {}

            Write-LogWarning "Node.js installed but could not be verified immediately. Restart your shell." $script:ModuleName
            return $true
        }
    } catch {
        Write-LogError "Failed to install Node.js: $_" $script:ModuleName
    }

    Write-LogError "Node.js installation failed" $script:ModuleName
    return $false
}

function Install-PackagesComponent {
    Write-LogInfo "Installing global npm packages..." $script:ModuleName

    try {
        # Get package lists from configuration
        $packageCategories = @('build', 'lint', 'tools')
        $allPackages = @()

        foreach ($category in $packageCategories) {
            $packages = Get-ModuleConfig $script:ModuleName ".nodejs.packages.$category[]"
            if ($packages) {
                $allPackages += $packages
            }
        }

        if ($allPackages.Count -eq 0) {
            Write-LogInfo "No global packages configured" $script:ModuleName
            return $true
        }

        # Install packages globally
        foreach ($package in $allPackages) {
            if ([string]::IsNullOrWhiteSpace($package)) { continue }

            Write-LogInfo "Installing package: $package" $script:ModuleName
            npm install -g $package 2>$null

            if ($LASTEXITCODE -ne 0) {
                Write-LogWarning "Failed to install package: $package" $script:ModuleName
            } else {
                Write-LogInfo "Successfully installed: $package" $script:ModuleName
            }
        }

        return $true
    } catch {
        Write-LogError "Error installing packages: $_" $script:ModuleName
        return $false
    }
}

function Install-ConfigComponent {
    Write-LogInfo "Configuring npm..." $script:ModuleName

    try {
        # Get npm config from module config
        $npmConfig = Get-ModuleConfig $script:ModuleName ".nodejs.npm.config"

        if ($npmConfig) {
            foreach ($prop in $npmConfig.PSObject.Properties) {
                $key = $prop.Name
                $value = $prop.Value

                # Convert boolean to string for npm config
                if ($value -is [bool]) {
                    $value = $value.ToString().ToLower()
                }

                Write-LogInfo "Setting npm config: $key = $value" $script:ModuleName
                npm config set $key $value 2>$null

                if ($LASTEXITCODE -ne 0) {
                    Write-LogWarning "Failed to set npm config: $key" $script:ModuleName
                }
            }
        }

        # Backup .npmrc if it exists
        $npmrc = Join-Path $env:USERPROFILE ".npmrc"
        if (Test-Path $npmrc) {
            Write-LogInfo "npm configuration file: $npmrc" $script:ModuleName
        }

        return $true
    } catch {
        Write-LogError "Error configuring npm: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing Node.js aliases..." $script:ModuleName

    # Add module aliases from config
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
        # Try adding aliases without category (flat structure)
        if (Add-ModuleAliases $script:ModuleName "npm") {
            Write-LogInfo "Added npm aliases" $script:ModuleName
        } else {
            Write-LogWarning "Failed to add npm aliases" $script:ModuleName
        }
    }

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
        'core' { Install-CoreComponent }
        'packages' { Install-PackagesComponent }
        'config' { Install-ConfigComponent }
        'aliases' { Install-AliasesComponent }
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
    Write-LogInfo "Checking Node.js module installation status..." $script:ModuleName

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

    Write-LogInfo "Node.js module installation completed successfully" $script:ModuleName
    Show-ModuleInfo

    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName

    # Create backup before removal
    New-Backup $script:ModuleName

    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    if ($aliasCategories) {
        foreach ($category in $aliasCategories) {
            Remove-ModuleAliases $script:ModuleName $category
        }
    } else {
        Remove-ModuleAliases $script:ModuleName "npm"
    }

    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }

    Write-LogInfo "Node.js module configuration removed" $script:ModuleName
    Write-LogWarning "Node.js installation and global packages were preserved" $script:ModuleName

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
        Write-LogInfo "Node.js module verification completed successfully" $script:ModuleName

        try {
            $nodeVersion = node --version 2>$null
            Write-LogInfo "Node.js version: $nodeVersion" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine Node.js version" $script:ModuleName
        }

        try {
            $npmVersion = npm --version 2>$null
            Write-LogInfo "npm version: $npmVersion" $script:ModuleName
        } catch {}
    }

    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Node.js Development Environment (Windows)
==========================================

Description:
-----------
Node.js development setup with npm package management,
global development tools, and productivity aliases.
Uses system Node.js installed via winget.

Components:
----------
1. Core Node.js
   - Node.js runtime (via winget)
   - npm package manager

2. Global Packages
   - Build: webpack, webpack-cli, @babel/core, @babel/cli
   - Lint: eslint, prettier
   - Tools: grunt-cli

3. npm Configuration
   - save-exact: true (deterministic versions)
   - package-lock: true

4. Aliases
   - n (node), ni (npm install)
   - nr (npm run), nrd (npm run dev), nrb (npm run build)

Quick Commands:
--------------
n                        # Node.js REPL
ni                       # npm install
nr dev                   # npm run dev
nrb                      # npm run build

"@

    Write-Host $header -ForegroundColor Cyan

    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow

    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component

        if ($isInstalled -and $isVerified) {
            Write-Host "+ $component`: Installed and verified" -ForegroundColor Green

            switch ($component) {
                'core' {
                    try {
                        $nodeVer = node --version 2>$null
                        $npmVer = npm --version 2>$null
                        Write-Host "  Node.js: $nodeVer" -ForegroundColor Gray
                        Write-Host "  npm: $npmVer" -ForegroundColor Gray
                    } catch {}
                }
                'packages' {
                    try {
                        $globalList = npm list -g --depth=0 2>$null
                        $packageCount = ($globalList | Select-String -Pattern "^\+--" | Measure-Object).Count
                        Write-Host "  Global packages: $packageCount installed" -ForegroundColor Gray
                    } catch {}
                }
            }
        } elseif ($isInstalled) {
            Write-Host "[WARN] $component`: Installed but not verified" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] $component`: Not installed" -ForegroundColor Red
        }
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
