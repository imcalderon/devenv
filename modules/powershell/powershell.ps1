#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell Module for DevEnv - Native Windows implementation
.DESCRIPTION
    Template for creating DevEnv modules that run natively on Windows using PowerShell.
    This template includes all the standard DevEnv module functions and Windows-specific implementations.
.PARAMETER Action
    The action to perform: install, remove, verify, info
.PARAMETER Force
    Force the operation even if already installed
#>

param (
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'grovel')]
    [string]$Action,
    
    [Parameter()]
    [switch]$Force
)

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Initialization
# Import required utilities
$libPath = Join-Path $env:DEVENV_ROOT "lib\windows"
$requiredModules = @(
    'logging.ps1',
    'json.ps1', 
    'module.ps1',
    'backup.ps1',
    'alias.ps1'
)

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $libPath $module
    if (Test-Path $modulePath) {
        . $modulePath
    } else {
        Write-Error "Required module not found: $modulePath"
        exit 1
    }
}

# Initialize module context
$script:ModuleName = "powershell"  # Change this for each module
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

# Initialize module logging
Initialize-Module $script:ModuleName
#endregion

#region Module Components
# Define module components for state management
$script:Components = @(
    'core',         # Base installation
    'profile',      # PowerShell profile setup
    'modules',      # PowerShell modules installation
    'aliases',      # Command aliases
    'config'        # Configuration files
)
#endregion

#region State Management Functions
function Save-ComponentState {
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        
        [Parameter(Mandatory)]
        [string]$Status
    )
    
    $stateDir = Split-Path $script:StateFile -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
    Add-Content -Path $script:StateFile -Value "$Component`:$Status`:$timestamp"
    
    Write-LogInfo "Saved state for component: $Component ($Status)" $script:ModuleName
}

function Test-ComponentState {
    param(
        [Parameter(Mandatory)]
        [string]$Component
    )
    
    if (Test-Path $script:StateFile) {
        $content = Get-Content $script:StateFile
        return ($content -match "^$Component`:installed:")
    }
    return $false
}

function Test-Component {
    param(
        [Parameter(Mandatory)]
        [string]$Component
    )
    
    switch ($Component) {
        'core' {
            # Verify PowerShell is installed and meets minimum version
            return $PSVersionTable.PSVersion.Major -ge 5
        }
        'profile' {
            # Verify PowerShell profile exists and is configured
            $profilePath = $PROFILE.CurrentUserAllHosts
            return (Test-Path $profilePath)
        }
        'modules' {
            # Verify essential PowerShell modules are installed
            $requiredModules = Get-ModuleConfig $script:ModuleName ".powershell.modules[]"
            foreach ($module in $requiredModules) {
                if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) {
                    return $false
                }
            }
            return $true
        }
        'aliases' {
            # Verify aliases are configured
            $aliasesFile = Join-Path (Get-AliasesDirectory) "aliases.ps1"
            return (Test-Path $aliasesFile) -and (Get-ModuleAliases $script:ModuleName)
        }
        'config' {
            # Verify configuration files exist
            $configDir = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
            $configDir = [System.Environment]::ExpandEnvironmentVariables($configDir)
            return (Test-Path $configDir)
        }
        default {
            return $false
        }
    }
}
#endregion

#region Component Installation Functions
function Install-CoreComponent {
    Write-LogInfo "Installing PowerShell core component..." $script:ModuleName
    
    # Check if we need to install a newer version of PowerShell
    $targetVersion = Get-ModuleConfig $script:ModuleName ".powershell.version"
    $currentVersion = $PSVersionTable.PSVersion
    
    if ($targetVersion -and ([version]$targetVersion -gt $currentVersion)) {
        Write-LogInfo "Current PowerShell version ($currentVersion) is older than target ($targetVersion)" $script:ModuleName
        
        # Install PowerShell via winget if available
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            try {
                winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
                Write-LogInfo "PowerShell updated via winget" $script:ModuleName
            }
            catch {
                Write-LogWarning "Failed to update PowerShell via winget: $_" $script:ModuleName
            }
        }
    }
    
    # Configure execution policy if needed
    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    $targetPolicy = Get-ModuleConfig $script:ModuleName ".security.execution_policy" "RemoteSigned"
    
    if ($currentPolicy -ne $targetPolicy) {
        Write-LogInfo "Setting execution policy to $targetPolicy" $script:ModuleName
        Set-ExecutionPolicy -ExecutionPolicy $targetPolicy -Scope CurrentUser -Force
    }
    
    return $true
}

function Install-ProfileComponent {
    Write-LogInfo "Installing PowerShell profile component..." $script:ModuleName
    
    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path $profilePath -Parent
    
    # Create profile directory if it doesn't exist
    if (-not (Test-Path $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }
    
    # Backup existing profile
    if (Test-Path $profilePath) {
        Backup-File $profilePath $script:ModuleName
    }
    
    # Create enhanced profile
    $profileContent = @"
# DevEnv PowerShell Profile
# Generated on $(Get-Date)

# Import DevEnv modules and aliases
`$devenvAliases = Join-Path `$env:DEVENV_DATA_DIR "aliases\aliases.ps1"
if (Test-Path `$devenvAliases) {
    . `$devenvAliases
}

# Enhanced prompt with Git integration
function prompt {
    `$path = `$PWD.Path.Replace(`$env:USERPROFILE, '~')
    
    # Git branch detection (if posh-git is available)
    `$gitBranch = ''
    if (Get-Command Write-VcsStatus -ErrorAction SilentlyContinue) {
        `$gitInfo = Write-VcsStatus
        if (`$gitInfo) {
            `$gitBranch = " `$gitInfo"
        }
    }
    
    Write-Host "[" -NoNewline -ForegroundColor Cyan
    Write-Host `$path -NoNewline -ForegroundColor Yellow
    Write-Host "]" -NoNewline -ForegroundColor Cyan
    Write-Host `$gitBranch -NoNewline -ForegroundColor Magenta
    Write-Host " > " -NoNewline -ForegroundColor Green
    
    return " "
}

# Enhanced tab completion
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows

# Key bindings
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Auto-import modules
`$autoImportModules = @('posh-git', 'Terminal-Icons', 'PSReadLine')
foreach (`$module in `$autoImportModules) {
    if (Get-Module -ListAvailable `$module -ErrorAction SilentlyContinue) {
        Import-Module `$module -ErrorAction SilentlyContinue
    }
}

# DevEnv welcome message
if (`$env:DEVENV_ROOT) {
    Write-Host "DevEnv loaded successfully" -ForegroundColor Green
}
"@
    
    Set-Content -Path $profilePath -Value $profileContent -Encoding UTF8
    Write-LogInfo "PowerShell profile created: $profilePath" $script:ModuleName
    
    return $true
}

function Install-ModulesComponent {
    Write-LogInfo "Installing PowerShell modules component..." $script:ModuleName
    
    # Get list of modules to install from config
    $modulesToInstall = Get-ModuleConfig $script:ModuleName ".powershell.modules[]"
    
    if (-not $modulesToInstall) {
        Write-LogInfo "No modules specified for installation" $script:ModuleName
        return $true
    }
    
    # Install PowerShellGet if not available
    if (-not (Get-Module -ListAvailable PowerShellGet -ErrorAction SilentlyContinue)) {
        Write-LogInfo "Installing PowerShellGet..." $script:ModuleName
        Install-Module PowerShellGet -Force -Scope CurrentUser
    }
    
    # Trust PSGallery if needed
    $psGallery = Get-PSRepository PSGallery
    if ($psGallery.InstallationPolicy -ne 'Trusted') {
        Write-LogInfo "Setting PSGallery as trusted repository" $script:ModuleName
        Set-PSRepository PSGallery -InstallationPolicy Trusted
    }
    
    foreach ($moduleName in $modulesToInstall) {
        Write-LogInfo "Installing module: $moduleName" $script:ModuleName
        
        try {
            if (-not (Get-Module -ListAvailable $moduleName -ErrorAction SilentlyContinue)) {
                Install-Module $moduleName -Scope CurrentUser -Force
                Write-LogInfo "Successfully installed module: $moduleName" $script:ModuleName
            } else {
                Write-LogInfo "Module already installed: $moduleName" $script:ModuleName
            }
        }
        catch {
            Write-LogError "Failed to install module ${moduleName}: $_" $script:ModuleName
            return $false
        }
    }
    
    return $true
}

function Install-AliasesComponent {
    Write-LogInfo "Installing aliases component..." $script:ModuleName
    
    # Add module aliases using the DevEnv alias system
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

function Install-ConfigComponent {
    Write-LogInfo "Installing configuration component..." $script:ModuleName
    
    # Create configuration directory
    $configDir = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
    $configDir = [System.Environment]::ExpandEnvironmentVariables($configDir)
    
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        Write-LogInfo "Created configuration directory: $configDir" $script:ModuleName
    }
    
    # Create module-specific configuration files
    $configFiles = @{
        'settings.json' = @{
            'theme' = 'dark'
            'auto_update' = $true
            'telemetry' = $false
        }
        'aliases.json' = Get-ModuleConfig $script:ModuleName ".shell.aliases"
    }
    
    foreach ($fileName in $configFiles.Keys) {
        $filePath = Join-Path $configDir $fileName
        $content = $configFiles[$fileName] | ConvertTo-Json -Depth 5
        Set-Content -Path $filePath -Value $content -Encoding UTF8
        Write-LogInfo "Created configuration file: $filePath" $script:ModuleName
    }
    
    return $true
}
#endregion

#region Main Module Functions
function Install-Component {
    param(
        [Parameter(Mandatory)]
        [string]$Component
    )
    
    if ((Test-ComponentState $Component) -and (Test-Component $Component) -and -not $Force) {
        Write-LogInfo "Component $Component already installed and verified" $script:ModuleName
        return $true
    }
    
    $result = switch ($Component) {
        'core' { Install-CoreComponent }
        'profile' { Install-ProfileComponent }
        'modules' { Install-ModulesComponent }
        'aliases' { Install-AliasesComponent }
        'config' { Install-ConfigComponent }
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
    Write-LogInfo "Checking module installation status..." $script:ModuleName
    
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
    
    Write-LogInfo "Module installation completed successfully" $script:ModuleName
    Show-ModuleInfo
    
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName
    
    # Create backup before removal
    New-Backup $script:ModuleName
    
    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }
    
    # Remove configuration files
    $configDir = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
    $configDir = [System.Environment]::ExpandEnvironmentVariables($configDir)
    if (Test-Path $configDir) {
        Remove-Item $configDir -Recurse -Force
    }
    
    # Reset PowerShell profile to basic state
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $basicProfile = "# Basic PowerShell Profile`n"
        Set-Content -Path $profilePath -Value $basicProfile
    }
    
    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    
    Write-LogInfo "Module removal completed" $script:ModuleName
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
        Write-LogInfo "Module verification completed successfully" $script:ModuleName
    }
    
    return $allVerified
}

function Show-ModuleInfo {
    Write-Host ""
    Write-Host "PowerShell Development Environment" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Description:" -ForegroundColor Yellow
    Write-Host "-----------" -ForegroundColor Yellow
    Write-Host "Enhanced PowerShell environment with modern modules, improved prompt,"
    Write-Host "and integrated development tools for Windows."
    Write-Host ""
    
    Write-Host "Benefits:" -ForegroundColor Yellow
    Write-Host "--------" -ForegroundColor Yellow
    Write-Host "+ Enhanced Command Line - PSReadLine with prediction and history" -ForegroundColor Green
    Write-Host "+ Git Integration - posh-git for repository status in prompt" -ForegroundColor Green
    Write-Host "+ Modern Modules - Latest PowerShell modules for development" -ForegroundColor Green
    Write-Host "+ Custom Aliases - Convenient shortcuts for common tasks" -ForegroundColor Green
    Write-Host "+ Profile Management - Automated profile setup and maintenance" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Components:" -ForegroundColor Yellow
    Write-Host "----------" -ForegroundColor Yellow
    Write-Host "1. Core PowerShell"
    Write-Host "   - PowerShell 7+ (if available)"
    Write-Host "   - Execution policy configuration"
    Write-Host "   - Module path management"
    Write-Host ""
    Write-Host "2. Essential Modules"
    Write-Host "   - PSReadLine for enhanced editing"
    Write-Host "   - posh-git for Git integration"
    Write-Host "   - Terminal-Icons for file type icons"
    Write-Host "   - PowerShellGet for module management"
    Write-Host ""
    Write-Host "3. Enhanced Profile"
    Write-Host "   - Custom prompt with Git status"
    Write-Host "   - Key bindings and shortcuts"
    Write-Host "   - Auto-import commonly used modules"
    Write-Host "   - History and prediction settings"
    Write-Host ""
    
    Write-Host "Quick Commands:" -ForegroundColor Yellow
    Write-Host "--------------" -ForegroundColor Yellow
    Write-Host "Get-Help about_*     # PowerShell help topics"
    Write-Host "Get-Module           # List loaded modules"
    Write-Host "Get-Command          # Find commands"
    Write-Host "Get-History          # Command history"
    Write-Host ""

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
    
    # Show PowerShell version info
    Write-Host ""
    Write-Host "PowerShell Information:" -ForegroundColor Yellow
    Write-Host "  Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host "  Edition: $($PSVersionTable.PSEdition)" -ForegroundColor Gray
    Write-Host "  Execution Policy: $(Get-ExecutionPolicy -Scope CurrentUser)" -ForegroundColor Gray
    
    # Show loaded modules
    $loadedModules = Get-Module | Where-Object { $_.Name -in @('PSReadLine', 'posh-git', 'Terminal-Icons') }
    if ($loadedModules) {
        Write-Host "  Loaded DevEnv Modules: $($loadedModules.Name -join ', ')" -ForegroundColor Gray
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