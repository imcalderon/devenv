#Requires -Version 5.1
<#
.SYNOPSIS
    Docker Module for DevEnv - Windows implementation
.DESCRIPTION
    Manages Docker Desktop for Windows with WSL2 backend integration,
    container management, and productivity aliases.
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

$script:ModuleName = "docker"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'core',              # Docker CLI verification
    'desktop',           # Docker Desktop running state
    'config',            # Docker Desktop settings
    'wsl_integration',   # WSL2 integration
    'aliases'            # Command aliases
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
                $null = docker --version 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'desktop' {
            try {
                $null = docker info 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'config' {
            # Check Docker Desktop settings file exists
            $settingsPath = Join-Path $env:APPDATA "Docker\settings-store.json"
            $legacySettingsPath = Join-Path $env:APPDATA "Docker\settings.json"
            return (Test-Path $settingsPath) -or (Test-Path $legacySettingsPath)
        }
        'wsl_integration' {
            # Check if WSL2 is available
            try {
                $null = wsl --status 2>$null
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
    Write-LogInfo "Verifying Docker CLI installation..." $script:ModuleName

    try {
        $dockerVersion = docker --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Docker CLI is installed: $dockerVersion" $script:ModuleName
            return $true
        }
    } catch {}

    # Attempt install via winget
    try {
        Write-LogInfo "Installing Docker Desktop via winget..." $script:ModuleName
        winget.exe install --exact --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Docker Desktop installed successfully via winget" $script:ModuleName

            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 5

            try {
                $dockerVersion = docker --version 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-LogInfo "Docker CLI verified: $dockerVersion" $script:ModuleName
                    return $true
                }
            } catch {}

            Write-LogWarning "Docker installed but CLI not yet in PATH. Restart your shell." $script:ModuleName
            return $true
        }
    } catch {
        Write-LogError "Failed to install Docker Desktop: $_" $script:ModuleName
    }

    Write-LogError "Docker installation failed" $script:ModuleName
    return $false
}

function Install-DesktopComponent {
    Write-LogInfo "Checking Docker Desktop status..." $script:ModuleName

    try {
        # Check if Docker daemon is responding
        $null = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Docker Desktop is running" $script:ModuleName
            return $true
        }
    } catch {}

    # Try to start Docker Desktop
    Write-LogInfo "Starting Docker Desktop..." $script:ModuleName

    $dockerDesktopPath = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dockerDesktopPath)) {
        # Try alternate location
        $dockerDesktopPath = Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\Docker Desktop.exe"
    }
    if (-not (Test-Path $dockerDesktopPath)) {
        # Try user install location
        $dockerDesktopPath = Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe"
    }

    if (Test-Path $dockerDesktopPath) {
        Start-Process -FilePath $dockerDesktopPath -WindowStyle Minimized
        Write-LogInfo "Docker Desktop starting, waiting for daemon..." $script:ModuleName

        # Wait for Docker daemon to become available
        $maxRetries = 30
        $retryCount = 0

        while ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 2
            try {
                $null = docker info 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-LogInfo "Docker Desktop is ready" $script:ModuleName
                    return $true
                }
            } catch {}
            $retryCount++
        }

        Write-LogWarning "Docker Desktop started but daemon is not yet responding" $script:ModuleName
        return $true
    }

    Write-LogError "Docker Desktop executable not found" $script:ModuleName
    return $false
}

function Install-ConfigComponent {
    Write-LogInfo "Configuring Docker Desktop..." $script:ModuleName

    try {
        # Docker Desktop settings are managed through its UI and settings file
        # We verify the settings file exists and log the daemon config from our config.json
        $settingsPath = Join-Path $env:APPDATA "Docker\settings-store.json"
        $legacySettingsPath = Join-Path $env:APPDATA "Docker\settings.json"

        if ((Test-Path $settingsPath) -or (Test-Path $legacySettingsPath)) {
            Write-LogInfo "Docker Desktop settings file found" $script:ModuleName
        } else {
            Write-LogWarning "Docker Desktop settings file not found. Launch Docker Desktop first." $script:ModuleName
        }

        # Log recommended daemon config from module config
        $daemonConfig = Get-ModuleConfig $script:ModuleName ".docker.daemon"
        if ($daemonConfig) {
            $logDriver = $daemonConfig.'log-driver'
            if ($logDriver) {
                Write-LogInfo "Recommended log driver: $logDriver" $script:ModuleName
            }

            $logOpts = $daemonConfig.'log-opts'
            if ($logOpts) {
                Write-LogInfo "Recommended log opts: max-size=$($logOpts.'max-size'), max-file=$($logOpts.'max-file')" $script:ModuleName
            }

            Write-LogInfo "Configure daemon settings via Docker Desktop > Settings > Docker Engine" $script:ModuleName
        }

        return $true
    } catch {
        Write-LogError "Error configuring Docker: $_" $script:ModuleName
        return $false
    }
}

function Install-WslIntegrationComponent {
    Write-LogInfo "Verifying WSL2 integration..." $script:ModuleName

    try {
        # Check if WSL is available
        $null = wsl --status 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-LogWarning "WSL2 is not available. Docker Desktop will use Hyper-V backend." $script:ModuleName
            return $true
        }

        Write-LogInfo "WSL2 is available" $script:ModuleName

        # List WSL distributions
        try {
            $distros = wsl --list --quiet 2>$null
            if ($distros) {
                Write-LogInfo "Available WSL distributions:" $script:ModuleName
                foreach ($distro in $distros) {
                    $distro = $distro.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($distro)) {
                        Write-LogInfo "  - $distro" $script:ModuleName
                    }
                }
            }
        } catch {
            Write-LogWarning "Could not list WSL distributions" $script:ModuleName
        }

        # Check WSL config for Docker integration
        $wslConfig = Get-ModuleConfig $script:ModuleName ".docker.wsl"
        if ($wslConfig -and $wslConfig.enabled) {
            Write-LogInfo "WSL Docker integration is configured as enabled" $script:ModuleName
            Write-LogInfo "Ensure Docker Desktop > Settings > Resources > WSL Integration is enabled" $script:ModuleName
        }

        return $true
    } catch {
        Write-LogError "Error checking WSL integration: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing Docker aliases..." $script:ModuleName

    # Add aliases for each category from config
    $aliasCategories = @('basic', 'container', 'cleanup')

    foreach ($category in $aliasCategories) {
        if (Add-ModuleAliases $script:ModuleName $category) {
            Write-LogInfo "Added aliases for category: $category" $script:ModuleName
        } else {
            Write-LogWarning "Failed to add aliases for category: $category" $script:ModuleName
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
        'desktop' { Install-DesktopComponent }
        'config' { Install-ConfigComponent }
        'wsl_integration' { Install-WslIntegrationComponent }
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
    Write-LogInfo "Checking Docker module installation status..." $script:ModuleName

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
            # WSL integration and desktop are non-fatal
            if ($component -in @('wsl_integration', 'desktop', 'config')) {
                Write-LogWarning "Optional component $component skipped" $script:ModuleName
            } else {
                Write-LogError "Failed to install component: $component" $script:ModuleName
                return $false
            }
        }
    }

    Write-LogInfo "Docker module installation completed successfully" $script:ModuleName
    Show-ModuleInfo

    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName

    # Create backup before removal
    New-Backup $script:ModuleName

    # Remove aliases
    $aliasCategories = @('basic', 'container', 'cleanup')
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }

    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }

    Write-LogInfo "Docker module configuration removed" $script:ModuleName
    Write-LogWarning "Docker Desktop installation was preserved. Uninstall via Settings if needed." $script:ModuleName

    return $true
}

function Test-ModuleVerification {
    Write-LogInfo "Verifying $($script:ModuleName) module installation..." $script:ModuleName

    $allVerified = $true

    foreach ($component in $script:Components) {
        if (-not (Test-Component $component)) {
            # Some components are optional
            if ($component -in @('wsl_integration', 'desktop')) {
                Write-LogWarning "Optional component not verified: $component" $script:ModuleName
            } else {
                Write-LogError "Verification failed for component: $component" $script:ModuleName
                $allVerified = $false
            }
        } else {
            Write-LogInfo "Component verified: $component" $script:ModuleName
        }
    }

    if ($allVerified) {
        Write-LogInfo "Docker module verification completed successfully" $script:ModuleName

        try {
            $version = docker --version 2>$null
            Write-LogInfo "Docker version: $version" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine Docker version" $script:ModuleName
        }

        try {
            $composeVersion = docker compose version 2>$null
            Write-LogInfo "Docker Compose: $composeVersion" $script:ModuleName
        } catch {}
    }

    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Docker Desktop Environment (Windows)
======================================

Description:
-----------
Docker Desktop for Windows with WSL2 backend, container management,
compose support, and productivity aliases.

Components:
----------
1. Docker CLI
   - Docker client and server
   - Docker Compose (integrated)

2. Docker Desktop
   - WSL2 backend (default)
   - Hyper-V fallback
   - Kubernetes (optional)

3. WSL2 Integration
   - Docker available in WSL distributions
   - Shared daemon between Windows and WSL

4. Aliases
   - Container management (d, dc, dps, dex)
   - Compose shortcuts (dcu, dcd, dcl)
   - Cleanup commands (dprune, dclean)

Quick Commands:
--------------
d ps                     # List running containers
dc up -d                 # Start compose stack
dex container bash       # Exec into container
dps                      # Docker ps
dprune                   # System prune

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
                        $version = docker --version 2>$null
                        Write-Host "  Version: $version" -ForegroundColor Gray
                    } catch {}
                }
                'desktop' {
                    try {
                        $info = docker info --format "{{.ServerVersion}}" 2>$null
                        Write-Host "  Server: $info" -ForegroundColor Gray
                    } catch {}
                }
                'wsl_integration' {
                    try {
                        $distros = wsl --list --quiet 2>$null
                        if ($distros) {
                            $count = ($distros | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
                            Write-Host "  WSL Distributions: $count" -ForegroundColor Gray
                        }
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
