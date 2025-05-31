#Requires -Version 5.1
<#
.SYNOPSIS
    WinGet Module for DevEnv - Windows Package Manager Integration
.DESCRIPTION
    Native Windows module for managing applications through Windows Package Manager (winget).
    Provides automated installation, updates, and management of development tools.
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

$script:ModuleName = "winget"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # WinGet installation and setup
    'sources',      # Package sources configuration
    'packages',     # Development packages installation
    'config',       # WinGet configuration
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
            # Check if winget is installed and functional
            try {
                $null = winget.exe --version 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'sources' {
            # Verify configured sources
            try {
                $sources = winget.exe source list 2>$null
                return ($sources -match "msstore") -and ($sources -match "winget")
            } catch {
                return $false
            }
        }
        'packages' {
            # Check if development packages are installed
            $requiredPackages = Get-ModuleConfig $script:ModuleName ".winget.packages.development[]"
            foreach ($package in $requiredPackages) {
                try {
                    $result = winget.exe list --exact --id $package 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        return $false
                    }
                } catch {
                    return $false
                }
            }
            return $true
        }
        'config' {
            # Verify WinGet configuration
            $configPath = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
            return (Test-Path $configPath)
        }
        'aliases' {
            # Check if aliases are configured
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
    Write-LogInfo "Installing WinGet core component..." $script:ModuleName
    
    # Check if WinGet is already available
    try {
        $null = winget.exe --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "WinGet is already installed" $script:ModuleName
            return $true
        }
    } catch {
        # WinGet not available, need to install
    }
    
    # WinGet comes with App Installer from Microsoft Store
    # For Windows 10/11, it should be pre-installed, but let's verify
    Write-LogInfo "Checking for App Installer..." $script:ModuleName
    
    # Try to install via Microsoft Store (requires user interaction)
    try {
        # Check if we can install via PowerShell
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        
        if (-not $appInstaller) {
            Write-LogWarning "App Installer not found. Please install from Microsoft Store:" $script:ModuleName
            Write-LogWarning "https://www.microsoft.com/p/app-installer/9nblggh4nns1" $script:ModuleName
            
            # Try alternative installation via GitHub releases
            Write-LogInfo "Attempting to install latest App Installer from GitHub..." $script:ModuleName
            
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $msixBundle = $latestRelease.assets | Where-Object { $_.name -like "*x64.msixbundle" } | Select-Object -First 1
            
            if ($msixBundle) {
                $downloadPath = Join-Path $env:TEMP $msixBundle.name
                Write-LogInfo "Downloading: $($msixBundle.name)" $script:ModuleName
                Invoke-WebRequest -Uri $msixBundle.browser_download_url -OutFile $downloadPath
                
                Write-LogInfo "Installing App Installer..." $script:ModuleName
                Add-AppxPackage -Path $downloadPath
                
                # Clean up
                Remove-Item $downloadPath -Force
            }
        }
        
        # Verify installation
        Start-Sleep -Seconds 5
        $null = winget.exe --version 2>$null
        return $LASTEXITCODE -eq 0
        
    } catch {
        Write-LogError "Failed to install WinGet: $_" $script:ModuleName
        return $false
    }
}

function Install-SourcesComponent {
    Write-LogInfo "Configuring WinGet sources..." $script:ModuleName
    
    try {
        # Reset sources to default if needed
        $sources = winget.exe source list 2>$null
        
        # Add Microsoft Store source if missing
        if (-not ($sources -match "msstore")) {
            Write-LogInfo "Adding Microsoft Store source..." $script:ModuleName
            winget.exe source add --name "msstore" --arg "https://storeedgefd.dsx.mp.microsoft.com/v9.0" --type "Microsoft.REST"
        }
        
        # Ensure winget community source is available
        if (-not ($sources -match "winget")) {
            Write-LogInfo "Adding WinGet community source..." $script:ModuleName
            winget.exe source add --name "winget" --arg "https://cdn.winget.microsoft.com/cache" --type "Microsoft.PreIndexed.Package"
        }
        
        # Update sources
        Write-LogInfo "Updating package sources..." $script:ModuleName
        winget.exe source update
        
        return $true
    } catch {
        Write-LogError "Failed to configure sources: $_" $script:ModuleName
        return $false
    }
}

function Install-PackagesComponent {
    Write-LogInfo "Installing development packages..." $script:ModuleName
    
    # Get package lists from configuration
    $developmentPackages = Get-ModuleConfig $script:ModuleName ".winget.packages.development[]"
    $optionalPackages = Get-ModuleConfig $script:ModuleName ".winget.packages.optional[]"
    
    $allPackages = $developmentPackages + $optionalPackages
    $failedPackages = @()
    
    foreach ($package in $allPackages) {
        if (-not $package) { continue }
        
        Write-LogInfo "Installing package: $package" $script:ModuleName
        
        try {
            # Check if already installed
            $listResult = winget.exe list --exact --id $package 2>$null
            if ($LASTEXITCODE -eq 0 -and $listResult -match $package) {
                Write-LogInfo "Package already installed: $package" $script:ModuleName
                continue
            }
            
            # Install the package
            $installArgs = @(
                "install",
                "--exact",
                "--id", $package,
                "--silent",
                "--accept-package-agreements",
                "--accept-source-agreements"
            )
            
            winget.exe @installArgs
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogInfo "Successfully installed: $package" $script:ModuleName
            } else {
                Write-LogWarning "Failed to install package: $package (exit code: $LASTEXITCODE)" $script:ModuleName
                $failedPackages += $package
            }
            
        } catch {
            Write-LogWarning "Error installing package ${package}: $_" $script:ModuleName
            $failedPackages += $package
        }
    }
    
    if ($failedPackages.Count -gt 0) {
        Write-LogWarning "Some packages failed to install: $($failedPackages -join ', ')" $script:ModuleName
        # Don't fail the entire component for optional packages
        return $developmentPackages.Count -eq 0 -or ($failedPackages | Where-Object { $_ -in $developmentPackages }).Count -eq 0
    }
    
    return $true
}

function Install-ConfigComponent {
    Write-LogInfo "Configuring WinGet settings..." $script:ModuleName
    
    try {
        # WinGet settings path
        $settingsDir = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState"
        $settingsFile = Join-Path $settingsDir "settings.json"
        
        # Create settings directory if needed
        if (-not (Test-Path $settingsDir)) {
            New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        }
        
        # Backup existing settings
        if (Test-Path $settingsFile) {
            Backup-File $settingsFile $script:ModuleName
        }
        
        # Create optimized WinGet settings
        $settings = @{
            "visual" = @{
                "progressBar" = "accent"
            }
            "installBehavior" = @{
                "preferences" = @{
                    "scope" = "user"
                    "locale" = "en-US"
                }
            }
            "source" = @{
                "autoUpdateIntervalInMinutes" = 1440  # Daily updates
            }
            "telemetry" = @{
                "disable" = $true
            }
            "network" = @{
                "downloader" = "wininet"
                "doProgressTimeoutInSeconds" = 60
            }
        }
        
        # Apply settings from module config if available
        $moduleSettings = Get-ModuleConfig $script:ModuleName ".winget.settings"
        if ($moduleSettings) {
            # Merge with default settings
            foreach ($key in $moduleSettings.PSObject.Properties.Name) {
                $settings[$key] = $moduleSettings.$key
            }
        }
        
        # Write settings file
        $settings | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsFile -Encoding UTF8
        Write-LogInfo "WinGet settings configured: $settingsFile" $script:ModuleName
        
        return $true
    } catch {
        Write-LogError "Failed to configure WinGet settings: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing WinGet aliases..." $script:ModuleName
    
    # Add module aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    
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
        'sources' { Install-SourcesComponent }
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
    Write-LogInfo "Checking WinGet module installation status..." $script:ModuleName
    
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
    
    Write-LogInfo "WinGet module installation completed successfully" $script:ModuleName
    Show-ModuleInfo
    
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName
    
    # Create backup before removal
    New-Backup $script:ModuleName
    
    # Remove installed packages (optional, dangerous)
    Write-LogWarning "Package removal not implemented for safety" $script:ModuleName
    Write-LogInfo "Use 'winget uninstall <package>' to remove specific packages" $script:ModuleName
    
    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }
    
    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    
    Write-LogInfo "WinGet module configuration removed" $script:ModuleName
    Write-LogWarning "WinGet itself and installed packages were preserved" $script:ModuleName
    
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
        Write-LogInfo "WinGet module verification completed successfully" $script:ModuleName
        
        # Show WinGet version
        try {
            $version = winget.exe --version 2>$null
            Write-LogInfo "WinGet version: $version" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine WinGet version" $script:ModuleName
        }
    }
    
    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

📦 Windows Package Manager (WinGet)
==================================

Description:
-----------
Windows Package Manager integration for automated installation and 
management of development tools and applications.

Benefits:
--------
✓ Automated Installation - Command-line package management
✓ Version Control - Specific versions and automatic updates  
✓ Dependency Management - Handle complex application dependencies
✓ Source Management - Multiple package sources (Store, Community)
✓ Silent Installation - Unattended setup for development environments

Components:
----------
1. Core WinGet
   - Windows Package Manager CLI
   - App Installer integration
   - Package database access

2. Package Sources
   - Microsoft Store packages
   - WinGet Community Repository
   - Custom sources support

3. Development Packages
   - Git, Node.js, Python, Docker
   - Development tools and utilities
   - Code editors and IDEs

Quick Commands:
--------------
wg search <term>         # Search for packages
wg install <package>     # Install package
wg list                  # List installed packages  
wg upgrade               # Upgrade all packages
wg uninstall <package>   # Remove package

"@

    Write-Host $header -ForegroundColor Cyan
    
    # Show current installation status
    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow
    
    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component
        
        if ($isInstalled -and $isVerified) {
            Write-Host "✓ $component`: Installed and verified" -ForegroundColor Green
        } elseif ($isInstalled) {
            Write-Host "⚠ $component`: Installed but not verified" -ForegroundColor Yellow
        } else {
            Write-Host "✗ $component`: Not installed" -ForegroundColor Red
        }
    }
    
    # Show WinGet information
    try {
        $version = winget.exe --version 2>$null
        if ($version) {
            Write-Host "`nWinGet Information:" -ForegroundColor Yellow
            Write-Host "  Version: $version" -ForegroundColor Gray
            
            # Show sources
            $sources = winget.exe source list 2>$null
            if ($sources) {
                Write-Host "  Sources: Available" -ForegroundColor Gray
            }
            
            # Show installed package count
            try {
                $installedCount = (winget.exe list 2>$null | Measure-Object -Line).Lines - 2  # Subtract header lines
                if ($installedCount -gt 0) {
                    Write-Host "  Installed Packages: $installedCount" -ForegroundColor Gray
                }
            } catch {
                # Ignore errors counting packages
            }
        }
    } catch {
        Write-Host "`nWinGet: Not available" -ForegroundColor Red
    }
    
    Write-Host ""
}
#endregion

#region Main Execution
try {
    switch ($Action.ToLower()) {
        'grovel' {
            exit (Test-ModuleInstallation ? 0 : 1)
        }
        'install' {
            $success = Install-Module
            exit ($success ? 0 : 1)
        }
        'remove' {
            $success = Remove-Module
            exit ($success ? 0 : 1)
        }
        'verify' {
            $success = Test-ModuleVerification
            exit ($success ? 0 : 1)
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