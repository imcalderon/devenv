#Requires -Version 5.1
<#
.SYNOPSIS
    Conda Module for DevEnv - Windows implementation
.DESCRIPTION
    Installs and configures Miniconda for Windows with channel management,
    PowerShell integration, and productivity aliases.
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

$script:ModuleName = "conda"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # Miniconda installation
    'config',       # Channel and conda configuration
    'shell',        # PowerShell shell integration
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
            $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
            $condaExe = Join-Path $condaRoot "Scripts\conda.exe"
            return (Test-Path $condaExe)
        }
        'config' {
            $condarcPath = Join-Path $env:USERPROFILE ".condarc"
            return (Test-Path $condarcPath)
        }
        'shell' {
            $profilePath = $PROFILE.CurrentUserAllHosts
            if (Test-Path $profilePath) {
                $content = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
                return ($content -and ($content -match "conda"))
            }
            return $false
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
    Write-LogInfo "Installing Miniconda..." $script:ModuleName

    $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
    $condaExe = Join-Path $condaRoot "Scripts\conda.exe"

    # Check if already installed
    if (Test-Path $condaExe) {
        try {
            $version = & $condaExe --version 2>$null
            Write-LogInfo "Miniconda already installed: $version" $script:ModuleName
            return $true
        } catch {}
    }

    # Download installer
    $installerUrl = Get-ModuleConfig $script:ModuleName ".package.installer_urls.`"win-64`""
    if ([string]::IsNullOrWhiteSpace($installerUrl)) {
        $installerUrl = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
    }

    $installerPath = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"

    Write-LogInfo "Downloading Miniconda from: $installerUrl" $script:ModuleName
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        $ProgressPreference = 'Continue'
        Write-LogInfo "Download complete" $script:ModuleName
    } catch {
        Write-LogError "Failed to download Miniconda: $_" $script:ModuleName
        return $false
    }

    # Install silently
    Write-LogInfo "Installing Miniconda to: $condaRoot" $script:ModuleName
    try {
        $installArgs = "/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=$condaRoot"
        $proc = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            Write-LogError "Miniconda installer exited with code: $($proc.ExitCode)" $script:ModuleName
            return $false
        }
        Write-LogInfo "Miniconda installed successfully" $script:ModuleName
    } catch {
        Write-LogError "Failed to install Miniconda: $_" $script:ModuleName
        return $false
    } finally {
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Verify installation
    if (Test-Path $condaExe) {
        $version = & $condaExe --version 2>$null
        Write-LogInfo "Miniconda installation verified: $version" $script:ModuleName
        return $true
    }

    Write-LogError "Miniconda installation could not be verified" $script:ModuleName
    return $false
}

function Install-ConfigComponent {
    Write-LogInfo "Configuring conda..." $script:ModuleName

    $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
    $condaExe = Join-Path $condaRoot "Scripts\conda.exe"

    if (-not (Test-Path $condaExe)) {
        Write-LogError "Conda not found at: $condaExe" $script:ModuleName
        return $false
    }

    try {
        # Temporarily allow stderr from native commands (conda writes warnings to stderr)
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'

        # Configure channels
        $channels = Get-ModuleConfig $script:ModuleName ".config.channels"
        if ($channels) {
            foreach ($channel in $channels) {
                & $condaExe config --add channels $channel 2>&1 | Out-Null
                Write-LogInfo "Added channel: $channel" $script:ModuleName
            }
        }

        # Configure channel priority
        $priority = Get-ModuleConfig $script:ModuleName ".config.channel_priority"
        if (-not [string]::IsNullOrWhiteSpace($priority)) {
            & $condaExe config --set channel_priority $priority 2>&1 | Out-Null
            Write-LogInfo "Set channel_priority: $priority" $script:ModuleName
        }

        # Configure auto_activate_base
        $autoActivate = Get-ModuleConfig $script:ModuleName ".config.auto_activate_base"
        if ($null -ne $autoActivate) {
            & $condaExe config --set auto_activate_base $autoActivate.ToString().ToLower() 2>&1 | Out-Null
            Write-LogInfo "Set auto_activate_base: $autoActivate" $script:ModuleName
        }

        # Configure pip_interop_enabled
        $pipInterop = Get-ModuleConfig $script:ModuleName ".config.pip_interop_enabled"
        if ($null -ne $pipInterop) {
            & $condaExe config --set pip_interop_enabled $pipInterop.ToString().ToLower() 2>&1 | Out-Null
            Write-LogInfo "Set pip_interop_enabled: $pipInterop" $script:ModuleName
        }

        # Configure env_prompt
        $envPrompt = Get-ModuleConfig $script:ModuleName ".config.env_prompt"
        if (-not [string]::IsNullOrWhiteSpace($envPrompt)) {
            & $condaExe config --set env_prompt "$envPrompt" 2>&1 | Out-Null
            Write-LogInfo "Set env_prompt: $envPrompt" $script:ModuleName
        }

        $ErrorActionPreference = $prevEAP
        return $true
    } catch {
        $ErrorActionPreference = $prevEAP
        Write-LogError "Error configuring conda: $_" $script:ModuleName
        return $false
    }
}

function Install-ShellComponent {
    Write-LogInfo "Configuring conda shell integration..." $script:ModuleName

    $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
    $condaExe = Join-Path $condaRoot "Scripts\conda.exe"

    if (-not (Test-Path $condaExe)) {
        Write-LogError "Conda not found at: $condaExe" $script:ModuleName
        return $false
    }

    try {
        # Initialize conda for PowerShell (conda writes to stderr)
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & $condaExe init powershell 2>&1 | Out-Null
        $ErrorActionPreference = $prevEAP
        if ($LASTEXITCODE -ne 0) {
            Write-LogWarning "conda init powershell returned non-zero exit code" $script:ModuleName
        }

        Write-LogInfo "Conda PowerShell integration configured" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Error configuring conda shell: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing conda aliases..." $script:ModuleName

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
        if (Add-ModuleAliases $script:ModuleName "conda") {
            Write-LogInfo "Added conda aliases" $script:ModuleName
        } else {
            Write-LogWarning "Failed to add conda aliases" $script:ModuleName
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
        'config' { Install-ConfigComponent }
        'shell' { Install-ShellComponent }
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
    Write-LogInfo "Checking Conda module installation status..." $script:ModuleName

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

    Write-LogInfo "Conda module installation completed successfully" $script:ModuleName
    Show-ModuleInfo

    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName

    # Create backup before removal
    New-Backup $script:ModuleName

    # Remove conda aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    if ($aliasCategories) {
        foreach ($category in $aliasCategories) {
            Remove-ModuleAliases $script:ModuleName $category
        }
    } else {
        Remove-ModuleAliases $script:ModuleName "conda"
    }

    # Remove conda from PowerShell profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $content = Get-Content -Path $profilePath -Raw
        $content = $content -replace "(?s)#region conda initialize.*?#endregion", ""
        Set-Content -Path $profilePath -Value $content -Force
    }

    # Remove .condarc
    $condarcPath = Join-Path $env:USERPROFILE ".condarc"
    if (Test-Path $condarcPath) {
        Backup-File $condarcPath $script:ModuleName
        Remove-Item $condarcPath -Force
    }

    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }

    Write-LogInfo "Conda module configuration removed" $script:ModuleName
    Write-LogWarning "Miniconda installation preserved. Remove manually: $env:USERPROFILE\miniconda3" $script:ModuleName

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
        Write-LogInfo "Conda module verification completed successfully" $script:ModuleName

        $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
        $condaExe = Join-Path $condaRoot "Scripts\conda.exe"
        try {
            $version = & $condaExe --version 2>$null
            Write-LogInfo "Conda version: $version" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine conda version" $script:ModuleName
        }
    }

    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Conda Development Environment (Windows)
========================================

Description:
-----------
Miniconda package and environment manager for Windows with
channel management, PowerShell integration, and productivity aliases.

Components:
----------
1. Core Miniconda
   - Miniconda3 installer (silent install)
   - conda package manager

2. Configuration
   - Channel setup (conda-forge, defaults)
   - Strict channel priority
   - pip interop enabled

3. Shell Integration
   - PowerShell conda init
   - Environment activation support

4. Aliases
   - ca (conda activate), ci (conda install)
   - ce (conda env list), cl (conda list)

Quick Commands:
--------------
ca myenv                 # Activate environment
ci numpy                 # Install package
ce                       # List environments
cl                       # List packages

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
                    $condaRoot = Join-Path $env:USERPROFILE "miniconda3"
                    $condaExe = Join-Path $condaRoot "Scripts\conda.exe"
                    try {
                        $version = & $condaExe --version 2>$null
                        Write-Host "  Version: $version" -ForegroundColor Gray
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
