#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Terminal Module for DevEnv - Modern terminal application setup
.DESCRIPTION
    Native Windows module for Windows Terminal with themes, profiles, and configuration management.
    This module runs at runlevel 0 to set up the terminal environment before other modules.
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

$script:ModuleName = "terminal"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # Windows Terminal installation
    'settings',     # Terminal settings configuration
    'themes',       # Color schemes and themes
    'profiles',     # Shell profiles (PowerShell, WSL, etc.)
    'context',      # Context menu integration
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
            # Check if Windows Terminal is installed
            try {
                $null = Get-Command wt.exe -ErrorAction Stop
                return $true
            } catch {
                # Check via installed apps
                $wtApp = Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue
                return $null -ne $wtApp
            }
        }
        'settings' {
            # Check if settings are configured
            $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.settings_path"
            $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
            return (Test-Path $settingsPath)
        }
        'themes' {
            # Check if custom themes are installed
            $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.settings_path"
            $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
            
            if (Test-Path $settingsPath) {
                try {
                    $settings = Get-Content $settingsPath | ConvertFrom-Json
                    $schemes = $settings.schemes
                    return ($schemes | Where-Object { $_.name -eq "DevEnv Dark" }) -ne $null
                } catch {
                    return $false
                }
            }
            return $false
        }
        'profiles' {
            # Check if profiles are properly configured
            $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.settings_path"
            $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
            
            if (Test-Path $settingsPath) {
                try {
                    $settings = Get-Content $settingsPath | ConvertFrom-Json
                    $profiles = $settings.profiles.list
                    # Check for PowerShell and PowerShell 7 profiles
                    $hasPS = ($profiles | Where-Object { $_.name -eq "PowerShell" }) -ne $null
                    $hasPS7 = ($profiles | Where-Object { $_.name -eq "PowerShell 7" }) -ne $null
                    return $hasPS -and $hasPS7
                } catch {
                    return $false
                }
            }
            return $false
        }
        'context' {
            # Check if context menu integration is set up
            $regPath = "HKEY_CLASSES_ROOT\Directory\Background\shell\wt"
            try {
                $regValue = Get-ItemProperty -Path "Registry::$regPath" -Name "(default)" -ErrorAction Stop
                return $true
            } catch {
                return $false
            }
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
    Write-LogInfo "Installing Windows Terminal core component..." $script:ModuleName
    
    # Check if already installed
    if (Test-Component 'core') {
        Write-LogInfo "Windows Terminal is already installed" $script:ModuleName
        return $true
    }
    
    # Try installing via winget first
    try {
        Write-LogInfo "Installing Windows Terminal via winget..." $script:ModuleName
        winget.exe install --exact --id Microsoft.WindowsTerminal --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Windows Terminal installed successfully via winget" $script:ModuleName
            return $true
        } else {
            Write-LogWarning "winget installation failed, trying Microsoft Store..." $script:ModuleName
        }
    } catch {
        Write-LogWarning "winget not available: $_" $script:ModuleName
    }
    
    # Fallback to Microsoft Store
    try {
        Write-LogInfo "Installing from Microsoft Store..." $script:ModuleName
        # Use the Store app ID for Windows Terminal
        Start-Process "ms-windows-store://pdp/?productid=9N0DX20HK701" -Wait
        
        Write-LogInfo "Please complete the installation from Microsoft Store and press Enter to continue..."
        Read-Host
        
        # Verify installation
        if (Test-Component 'core') {
            Write-LogInfo "Windows Terminal installation verified" $script:ModuleName
            return $true
        } else {
            Write-LogError "Windows Terminal installation could not be verified" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Failed to install Windows Terminal: $_" $script:ModuleName
        return $false
    }
}

function Install-SettingsComponent {
    Write-LogInfo "Installing Windows Terminal settings..." $script:ModuleName
    
    try {
        $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.settings_path"
        $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
        $settingsDir = Split-Path $settingsPath -Parent
        
        # Create settings directory if needed
        if (-not (Test-Path $settingsDir)) {
            New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
        }
        
        # Backup existing settings
        if (Test-Path $settingsPath) {
            Backup-File $settingsPath $script:ModuleName
        }
        
        # Get settings from module config
        $settings = Get-ModuleConfig $script:ModuleName ".windows_terminal.settings"
        
        if ($settings) {
            # Convert to JSON and write to file
            $settingsJson = $settings | ConvertTo-Json -Depth 10
            Set-Content -Path $settingsPath -Value $settingsJson -Encoding UTF8
            Write-LogInfo "Windows Terminal settings configured: $settingsPath" $script:ModuleName
            return $true
        } else {
            Write-LogError "No settings configuration found in module config" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Failed to configure Windows Terminal settings: $_" $script:ModuleName
        return $false
    }
}

function Install-ThemesComponent {
    Write-LogInfo "Installing Windows Terminal themes..." $script:ModuleName
    
    try {
        $themesDir = Get-ModuleConfig $script:ModuleName ".shell.paths.themes_dir"
        $themesDir = [System.Environment]::ExpandEnvironmentVariables($themesDir)
        
        # Create themes directory
        if (-not (Test-Path $themesDir)) {
            New-Item -Path $themesDir -ItemType Directory -Force | Out-Null
        }
        
        # Themes are included in the main settings configuration
        # The install-settings component handles theme installation
        Write-LogInfo "Themes installed as part of settings configuration" $script:ModuleName
        return $true
        
    } catch {
        Write-LogError "Failed to install themes: $_" $script:ModuleName
        return $false
    }
}

function Install-ProfilesComponent {
    Write-LogInfo "Installing Windows Terminal profiles..." $script:ModuleName
    
    try {
        # Profiles are configured as part of the main settings
        # This component ensures they're properly set up
        
        $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.settings_path"
        $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
        
        if (-not (Test-Path $settingsPath)) {
            Write-LogError "Settings file not found. Install settings component first." $script:ModuleName
            return $false
        }
        
        # Verify profiles are in the settings
        $settings = Get-Content $settingsPath | ConvertFrom-Json
        $profiles = $settings.profiles.list
        
        $requiredProfiles = @("PowerShell", "PowerShell 7")
        foreach ($profileName in $requiredProfiles) {
            $profile = $profiles | Where-Object { $_.name -eq $profileName }
            if (-not $profile) {
                Write-LogWarning "Profile '$profileName' not found in settings" $script:ModuleName
            }
        }
        
        Write-LogInfo "Terminal profiles configured successfully" $script:ModuleName
        return $true
        
    } catch {
        Write-LogError "Failed to configure profiles: $_" $script:ModuleName
        return $false
    }
}

function Install-ContextComponent {
    Write-LogInfo "Installing Windows Terminal context menu integration..." $script:ModuleName
    
    try {
        # Get context menu configuration
        $contextConfig = Get-ModuleConfig $script:ModuleName ".integration.context_menu"
        
        if (-not $contextConfig -or -not $contextConfig.enabled) {
            Write-LogInfo "Context menu integration disabled in configuration" $script:ModuleName
            return $true
        }
        
        # Install registry keys for context menu
        $registryKeys = $contextConfig.registry_keys
        
        foreach ($regKey in $registryKeys) {
            $keyPath = $regKey.path
            $keyName = $regKey.name
            $command = $regKey.command
            
            # Create registry key
            if (-not (Test-Path "Registry::$keyPath")) {
                New-Item -Path "Registry::$keyPath" -Force | Out-Null
            }
            
            # Set default value (display name)
            Set-ItemProperty -Path "Registry::$keyPath" -Name "(Default)" -Value $keyName
            
            # Set command
            $commandPath = "$keyPath\command"
            if (-not (Test-Path "Registry::$commandPath")) {
                New-Item -Path "Registry::$commandPath" -Force | Out-Null
            }
            Set-ItemProperty -Path "Registry::$commandPath" -Name "(Default)" -Value $command
            
            Write-LogInfo "Added context menu entry: $keyName" $script:ModuleName
        }
        
        return $true
        
    } catch {
        Write-LogError "Failed to install context menu integration: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing Windows Terminal aliases..." $script:ModuleName
    
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
        'settings' { Install-SettingsComponent }
        'themes' { Install-ThemesComponent }
        'profiles' { Install-ProfilesComponent }
        'context' { Install-ContextComponent }
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
    Write-LogInfo "Checking Windows Terminal module installation status..." $script:ModuleName
    
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
    
    Write-LogInfo "Windows Terminal module installation completed successfully" $script:ModuleName
    Show-ModuleInfo
    
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName
    
    # Create backup before removal
    New-Backup $script:ModuleName
    
    # Remove context menu entries
    try {
        $contextConfig = Get-ModuleConfig $script:ModuleName ".integration.context_menu"
        if ($contextConfig -and $contextConfig.enabled) {
            $registryKeys = $contextConfig.registry_keys
            foreach ($regKey in $registryKeys) {
                $keyPath = $regKey.path
                if (Test-Path "Registry::$keyPath") {
                    Remove-Item -Path "Registry::$keyPath" -Recurse -Force
                    Write-LogInfo "Removed context menu entry: $keyPath" $script:ModuleName
                }
            }
        }
    } catch {
        Write-LogWarning "Error removing context menu entries: $_" $script:ModuleName
    }
    
    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }
    
    # Reset Windows Terminal settings to default
    $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.settings_path"
    $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
    
    if (Test-Path $settingsPath) {
        # Create minimal default settings
        $defaultSettings = @{
            '$help' = 'https://aka.ms/terminal-documentation'
            '$schema' = 'https://aka.ms/terminal-profiles-schema'
            'defaultProfile' = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
            'profiles' = @{
                'defaults' = @{}
                'list' = @(
                    @{
                        'guid' = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
                        'name' = 'Windows PowerShell'
                        'commandline' = 'powershell.exe'
                        'hidden' = $false
                    }
                )
            }
            'schemes' = @()
            'actions' = @()
        }
        
        $defaultSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8
        Write-LogInfo "Reset Windows Terminal settings to default" $script:ModuleName
    }
    
    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    
    Write-LogInfo "Windows Terminal module configuration removed" $script:ModuleName
    Write-LogWarning "Windows Terminal application itself was preserved" $script:ModuleName
    
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
        Write-LogInfo "Windows Terminal module verification completed successfully" $script:ModuleName
        
        # Show Windows Terminal version if available
        try {
            $wtApp = Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue
            if ($wtApp) {
                Write-LogInfo "Windows Terminal version: $($wtApp.Version)" $script:ModuleName
            }
        } catch {
            Write-LogWarning "Could not determine Windows Terminal version" $script:ModuleName
        }
    }
    
    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Windows Terminal - Modern Terminal Application
===========================================

Description:
-----------
Modern, feature-rich terminal application for Windows with GPU acceleration,
multiple tab support, and extensive customization options.

Benefits:
--------
+ GPU Acceleration - Smooth, fast terminal rendering
+ Multiple Profiles - Separate configurations for different shells
+ Rich Themes - Customizable color schemes and appearance
+ Tab Support - Multiple terminals in one window
+ Context Integration - Right-click to open terminal anywhere

Components:
----------
1. Core Application
   - Windows Terminal from Microsoft Store
   - Command-line integration (wt.exe)
   - System PATH configuration

2. Settings Configuration
   - Optimized default settings
   - Custom color schemes
   - Font and appearance settings
   - Keyboard shortcuts

3. Profile Management
   - PowerShell profiles
   - PowerShell 7 profiles  
   - WSL integration profiles
   - Custom shell support

4. Context Menu Integration
   - "Open in Terminal" context menu
   - Directory-specific terminal launch
   - Registry integration

Quick Commands:
--------------
wt                      # Launch Windows Terminal
wt -d .                # Open in current directory  
wt --elevate           # Launch as administrator
wt --settings          # Open settings

Profile Selection:
-----------------
wt -p "PowerShell"     # Open PowerShell profile
wt -p "PowerShell 7"   # Open PowerShell 7 profile
wt -p "Ubuntu"         # Open Ubuntu WSL profile

"@

    Write-Host $header -ForegroundColor Cyan
    
    # Show current installation status
    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow
    
    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component
        
        if ($isInstalled -and $isVerified) {
            Write-Host "[OK] $component`: Installed and verified" -ForegroundColor Green
        } elseif ($isInstalled) {
            Write-Host "[WARN] $component`: Installed but not verified" -ForegroundColor Yellow
        } else {
            Write-Host "[MISSING] $component`: Not installed" -ForegroundColor Red
        }
    }
    
    # Show Windows Terminal information
    try {
        $wtApp = Get-AppxPackage -Name "Microsoft.WindowsTerminal" -ErrorAction SilentlyContinue
        if ($wtApp) {
            Write-Host ""
            Write-Host "Windows Terminal Information:" -ForegroundColor Yellow
            Write-Host "  Version: $($wtApp.Version)" -ForegroundColor Gray
            Write-Host "  Install Location: $($wtApp.InstallLocation)" -ForegroundColor Gray
            
            # Check if wt.exe is in PATH
            try {
                $wtExe = Get-Command wt.exe -ErrorAction SilentlyContinue
                if ($wtExe) {
                    Write-Host "  Command Line: Available" -ForegroundColor Gray
                } else {
                    Write-Host "  Command Line: Not in PATH" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  Command Line: Not available" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host ""
        Write-Host "Windows Terminal: Not available" -ForegroundColor Red
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