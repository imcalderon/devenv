#Requires -Version 5.1
<#
.SYNOPSIS
    Registry Module for DevEnv - Safe Windows Registry Management
.DESCRIPTION
    Native Windows module for managing registry settings with backup and restore capabilities.
    Provides safe registry operations for development environment configuration.
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

$script:ModuleName = "registry"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

Initialize-Module $script:ModuleName

$script:Components = @(
    'backup',       # Registry backup system
    'tools',        # Registry management tools
    'developer',    # Developer-specific registry settings
    'context',      # Context menu integrations
    'aliases'       # Command aliases
)
#endregion

#region Registry Utility Functions
function Test-RegistryPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        $null = Get-Item -Path $Path -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Backup-RegistryKey {
    param(
        [Parameter(Mandatory)]
        [string]$KeyPath,
        
        [Parameter(Mandatory)]
        [string]$BackupPath
    )
    
    try {
        # Ensure backup directory exists
        $backupDir = Split-Path $BackupPath -Parent
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }
        
        # Export registry key
        $regArgs = @(
            'export',
            $KeyPath,
            $BackupPath,
            '/y'
        )
        
        $process = Start-Process -FilePath 'reg.exe' -ArgumentList $regArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-LogInfo "Registry key backed up: $KeyPath -> $BackupPath" $script:ModuleName
            return $true
        } else {
            Write-LogError "Failed to backup registry key: $KeyPath (Exit code: $($process.ExitCode))" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Error backing up registry key ${KeyPath}: $_" $script:ModuleName
        return $false
    }
}

function Restore-RegistryKey {
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )
    
    try {
        if (-not (Test-Path $BackupPath)) {
            Write-LogError "Backup file not found: $BackupPath" $script:ModuleName
            return $false
        }
        
        # Import registry key
        $regArgs = @(
            'import',
            $BackupPath
        )
        
        $process = Start-Process -FilePath 'reg.exe' -ArgumentList $regArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-LogInfo "Registry key restored from: $BackupPath" $script:ModuleName
            return $true
        } else {
            Write-LogError "Failed to restore registry key from: $BackupPath (Exit code: $($process.ExitCode))" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Error restoring registry key from ${BackupPath}: $_" $script:ModuleName
        return $false
    }
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        $Value,
        
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string]$Type = 'String',
        
        [switch]$CreatePath
    )
    
    try {
        # Create path if it doesn't exist and CreatePath is specified
        if ($CreatePath -and -not (Test-RegistryPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
            Write-LogInfo "Created registry path: $Path" $script:ModuleName
        }
        
        # Set the registry value
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-LogInfo "Set registry value: $Path\$Name = $Value ($Type)" $script:ModuleName
        
        return $true
    } catch {
        Write-LogError "Failed to set registry value ${Path}\${Name}: $_" $script:ModuleName
        return $false
    }
}

function Remove-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        if (Test-RegistryPath $Path) {
            $property = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($property) {
                Remove-ItemProperty -Path $Path -Name $Name -Force
                Write-LogInfo "Removed registry value: $Path\$Name" $script:ModuleName
                return $true
            }
        }
        
        Write-LogInfo "Registry value not found (already removed): $Path\$Name" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Failed to remove registry value ${Path}\${Name}: $_" $script:ModuleName
        return $false
    }
}
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
        'backup' {
            # Check if backup system is configured
            $backupDir = Get-ModuleConfig $script:ModuleName ".shell.paths.backup_dir"
            $backupDir = [System.Environment]::ExpandEnvironmentVariables($backupDir)
            return (Test-Path $backupDir)
        }
        'tools' {
            # Check if registry tools are available
            return (Get-Command reg.exe -ErrorAction SilentlyContinue) -and 
                   (Get-Command regedit.exe -ErrorAction SilentlyContinue)
        }
        'developer' {
            # Check if developer settings are applied
            $devSettings = Get-ModuleConfig $script:ModuleName ".registry.developer_settings"
            if (-not $devSettings) { return $true }
            
            foreach ($setting in $devSettings.PSObject.Properties) {
                $path = $setting.Value.path
                $name = $setting.Value.name
                $value = $setting.Value.value
                
                try {
                    $currentValue = Get-ItemPropertyValue -Path $path -Name $name -ErrorAction SilentlyContinue
                    if ($currentValue -ne $value) {
                        return $false
                    }
                } catch {
                    return $false
                }
            }
            return $true
        }
        'context' {
            # Check if context menu integrations are installed
            $contextMenus = Get-ModuleConfig $script:ModuleName ".registry.context_menus"
            if (-not $contextMenus) { return $true }
            
            foreach ($menu in $contextMenus.PSObject.Properties) {
                $path = $menu.Value.path
                if (-not (Test-RegistryPath $path)) {
                    return $false
                }
            }
            return $true
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
function Install-BackupComponent {
    Write-LogInfo "Installing registry backup system..." $script:ModuleName
    
    try {
        # Create backup directory
        $backupDir = Get-ModuleConfig $script:ModuleName ".shell.paths.backup_dir"
        $backupDir = [System.Environment]::ExpandEnvironmentVariables($backupDir)
        
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
            Write-LogInfo "Created registry backup directory: $backupDir" $script:ModuleName
        }
        
        # Create initial backup of important keys
        $importantKeys = Get-ModuleConfig $script:ModuleName ".registry.backup_keys[]"
        
        foreach ($keyPath in $importantKeys) {
            if (Test-RegistryPath $keyPath) {
                $keyName = ($keyPath -split '\\')[-1]
                $backupFile = Join-Path $backupDir "${keyName}_initial_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
                Backup-RegistryKey -KeyPath $keyPath -BackupPath $backupFile
            }
        }
        
        # Create backup script
        $backupScript = Join-Path $backupDir "backup_registry.ps1"
        $backupScriptContent = @"
# Registry Backup Script - Generated by DevEnv
param([string]`$BackupPath)

if (-not `$BackupPath) {
    `$BackupPath = Join-Path "$backupDir" "manual_backup_`$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}

if (-not (Test-Path `$BackupPath)) {
    New-Item -Path `$BackupPath -ItemType Directory -Force | Out-Null
}

`$keys = @(
$(($importantKeys | ForEach-Object { "    '$_'" }) -join ",`n")
)

foreach (`$key in `$keys) {
    `$keyName = (`$key -split '\\\\')[-1]
    `$backupFile = Join-Path `$BackupPath "`${keyName}.reg"
    reg.exe export `$key `$backupFile /y
    Write-Host "Backed up: `$key"
}

Write-Host "Registry backup completed: `$BackupPath"
"@
        
        Set-Content -Path $backupScript -Value $backupScriptContent -Encoding UTF8
        Write-LogInfo "Created registry backup script: $backupScript" $script:ModuleName
        
        return $true
    } catch {
        Write-LogError "Failed to install backup component: $_" $script:ModuleName
        return $false
    }
}

function Install-ToolsComponent {
    Write-LogInfo "Configuring registry tools..." $script:ModuleName
    
    try {
        # Verify that required tools are available
        $tools = @('reg.exe', 'regedit.exe')
        foreach ($tool in $tools) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                Write-LogError "Required tool not found: $tool" $script:ModuleName
                return $false
            }
        }
        
        # Create registry management functions script
        $toolsDir = Get-ModuleConfig $script:ModuleName ".shell.paths.tools_dir"
        $toolsDir = [System.Environment]::ExpandEnvironmentVariables($toolsDir)
        
        if (-not (Test-Path $toolsDir)) {
            New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
        }
        
        $functionsScript = Join-Path $toolsDir "registry_functions.ps1"
        $functionsContent = @"
# Registry Management Functions - Generated by DevEnv

function Get-RegistryKeyInfo {
    param([string]`$Path)
    
    if (-not (Test-Path `$Path)) {
        Write-Warning "Registry path not found: `$Path"
        return
    }
    
    `$key = Get-Item -Path `$Path
    `$properties = Get-ItemProperty -Path `$Path
    
    [PSCustomObject]@{
        Path = `$Path
        SubKeyCount = `$key.SubKeyCount
        ValueCount = `$key.ValueCount
        Properties = `$properties
        LastWriteTime = `$key.LastWriteTime
    }
}

function Find-RegistryValue {
    param(
        [string]`$SearchPath,
        [string]`$ValueName,
        [string]`$ValueData,
        [switch]`$Recurse
    )
    
    `$results = @()
    
    try {
        if (`$Recurse) {
            `$keys = Get-ChildItem -Path `$SearchPath -Recurse -ErrorAction SilentlyContinue
        } else {
            `$keys = Get-ChildItem -Path `$SearchPath -ErrorAction SilentlyContinue
        }
        
        foreach (`$key in `$keys) {
            try {
                `$properties = Get-ItemProperty -Path `$key.PSPath -ErrorAction SilentlyContinue
                
                if (`$ValueName) {
                    if (`$properties.PSObject.Properties.Name -contains `$ValueName) {
                        `$results += [PSCustomObject]@{
                            Path = `$key.PSPath
                            Name = `$ValueName
                            Value = `$properties.`$ValueName
                        }
                    }
                } elseif (`$ValueData) {
                    foreach (`$prop in `$properties.PSObject.Properties) {
                        if (`$prop.Value -like "*`$ValueData*") {
                            `$results += [PSCustomObject]@{
                                Path = `$key.PSPath
                                Name = `$prop.Name
                                Value = `$prop.Value
                            }
                        }
                    }
                }
            } catch {
                # Ignore access denied errors
            }
        }
    } catch {
        Write-Warning "Error searching registry: `$_"
    }
    
    return `$results
}

function Export-RegistryBranch {
    param(
        [string]`$KeyPath,
        [string]`$OutputFile
    )
    
    reg.exe export `$KeyPath `$OutputFile /y
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Host "Exported `$KeyPath to `$OutputFile"
    } else {
        Write-Error "Failed to export `$KeyPath"
    }
}

function Import-RegistryFile {
    param([string]`$RegistryFile)
    
    if (-not (Test-Path `$RegistryFile)) {
        Write-Error "Registry file not found: `$RegistryFile"
        return
    }
    
    reg.exe import `$RegistryFile
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Host "Imported `$RegistryFile"
    } else {
        Write-Error "Failed to import `$RegistryFile"
    }
}
"@
        
        Set-Content -Path $functionsScript -Value $functionsContent -Encoding UTF8
        Write-LogInfo "Created registry functions script: $functionsScript" $script:ModuleName
        
        return $true
    } catch {
        Write-LogError "Failed to install tools component: $_" $script:ModuleName
        return $false
    }
}

function Install-DeveloperComponent {
    Write-LogInfo "Applying developer registry settings..." $script:ModuleName
    
    try {
        $devSettings = Get-ModuleConfig $script:ModuleName ".registry.developer_settings"
        if (-not $devSettings) {
            Write-LogInfo "No developer settings configured" $script:ModuleName
            return $true
        }
        
        # Backup relevant keys first
        $backupDir = Get-ModuleConfig $script:ModuleName ".shell.paths.backup_dir"
        $backupDir = [System.Environment]::ExpandEnvironmentVariables($backupDir)
        $devBackupDir = Join-Path $backupDir "developer_settings_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -Path $devBackupDir -ItemType Directory -Force | Out-Null
        
        foreach ($setting in $devSettings.PSObject.Properties) {
            $path = $setting.Value.path
            $name = $setting.Value.name
            $value = $setting.Value.value
            $type = $setting.Value.type
            $description = $setting.Value.description
            
            Write-LogInfo "Applying developer setting: $description" $script:ModuleName
            
            # Backup the key if it exists
            if (Test-RegistryPath $path) {
                $keyName = ($path -split '\\')[-1]
                $backupFile = Join-Path $devBackupDir "${keyName}.reg"
                Backup-RegistryKey -KeyPath $path -BackupPath $backupFile
            }
            
            # Apply the setting
            if (-not (Set-RegistryValue -Path $path -Name $name -Value $value -Type $type -CreatePath)) {
                Write-LogError "Failed to apply developer setting: $description" $script:ModuleName
                return $false
            }
        }
        
        Write-LogInfo "Developer registry settings applied successfully" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Failed to install developer component: $_" $script:ModuleName
        return $false
    }
}

function Install-ContextComponent {
    Write-LogInfo "Installing context menu integrations..." $script:ModuleName
    
    try {
        $contextMenus = Get-ModuleConfig $script:ModuleName ".registry.context_menus"
        if (-not $contextMenus) {
            Write-LogInfo "No context menus configured" $script:ModuleName
            return $true
        }
        
        foreach ($menu in $contextMenus.PSObject.Properties) {
            $menuName = $menu.Name
            $config = $menu.Value
            
            Write-LogInfo "Installing context menu: $menuName" $script:ModuleName
            
            # Create the context menu registry entries
            $basePath = $config.path
            $displayName = $config.display_name
            $command = $config.command
            $icon = $config.icon
            
            # Set display name
            if (-not (Set-RegistryValue -Path $basePath -Name "(Default)" -Value $displayName -CreatePath)) {
                return $false
            }
            
            # Set icon if specified
            if ($icon) {
                if (-not (Set-RegistryValue -Path $basePath -Name "Icon" -Value $icon)) {
                    return $false
                }
            }
            
            # Set command
            $commandPath = "$basePath\command"
            if (-not (Set-RegistryValue -Path $commandPath -Name "(Default)" -Value $command -CreatePath)) {
                return $false
            }
        }
        
        Write-LogInfo "Context menu integrations installed successfully" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Failed to install context component: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing registry aliases..." $script:ModuleName
    
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
        'backup' { Install-BackupComponent }
        'tools' { Install-ToolsComponent }
        'developer' { Install-DeveloperComponent }
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
    Write-LogInfo "Checking registry module installation status..." $script:ModuleName
    
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
    
    # Check if running as administrator for registry modifications
    if (-not (Test-Administrator)) {
        Write-LogWarning "Some registry operations require administrator privileges" $script:ModuleName
        Write-LogWarning "Consider running as administrator for full functionality" $script:ModuleName
    }
    
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
    
    Write-LogInfo "Registry module installation completed successfully" $script:ModuleName
    Show-ModuleInfo
    
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName
    
    # Create backup before removal
    New-Backup $script:ModuleName
    
    # Remove context menu integrations
    $contextMenus = Get-ModuleConfig $script:ModuleName ".registry.context_menus"
    if ($contextMenus) {
        foreach ($menu in $contextMenus.PSObject.Properties) {
            $path = $menu.Value.path
            if (Test-RegistryPath $path) {
                try {
                    Remove-Item -Path $path -Recurse -Force
                    Write-LogInfo "Removed context menu: $($menu.Name)" $script:ModuleName
                } catch {
                    Write-LogWarning "Failed to remove context menu ${path}: $_" $script:ModuleName
                }
            }
        }
    }
    
    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }
    
    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    
    Write-LogInfo "Registry module removed" $script:ModuleName
    Write-LogWarning "Developer registry settings were preserved for safety" $script:ModuleName
    Write-LogInfo "Use backup files to restore original settings if needed" $script:ModuleName
    
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
        Write-LogInfo "Registry module verification completed successfully" $script:ModuleName
    }
    
    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

🗂️ Windows Registry Management
=============================

Description:
-----------
Safe Windows Registry management with backup and restore capabilities.
Provides developer-friendly registry settings and context menu integrations.

Benefits:
--------
✓ Safe Operations - Automatic backup before modifications
✓ Developer Settings - Optimized registry settings for development
✓ Context Menus - Custom right-click menu integrations
✓ Backup & Restore - Complete registry backup and restore system
✓ Search & Analysis - Registry search and analysis tools

Components:
----------
1. Backup System
   - Automatic registry backups
   - Point-in-time snapshots
   - Safe restore capabilities

2. Registry Tools
   - Enhanced registry functions
   - Search and analysis tools
   - Import/export utilities

3. Developer Settings
   - File association optimizations
   - Explorer enhancements
   - Development environment tweaks

4. Context Menu Integration
   - Custom right-click menus
   - Developer tool shortcuts
   - Quick access functions

Quick Commands:
--------------
reg-backup <key>         # Backup registry key
reg-restore <file>       # Restore from backup
reg-search <term>        # Search registry
reg-info <path>         # Show key information

Safety Features:
---------------
• Automatic backups before changes
• Administrator privilege detection
• Rollback capability
• Non-destructive operations

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
    
    # Show registry information
    Write-Host "`nRegistry Information:" -ForegroundColor Yellow
    Write-Host "  Administrator Rights: $(if(Test-Administrator){'Yes'}else{'No'})" -ForegroundColor Gray
    Write-Host "  Registry Tools: $(if(Get-Command reg.exe -ErrorAction SilentlyContinue){'Available'}else{'Not Found'})" -ForegroundColor Gray
    
    # Show backup information
    $backupDir = Get-ModuleConfig $script:ModuleName ".shell.paths.backup_dir"
    $backupDir = [System.Environment]::ExpandEnvironmentVariables($backupDir)
    if (Test-Path $backupDir) {
        $backupCount = (Get-ChildItem $backupDir -Filter "*.reg" | Measure-Object).Count
        Write-Host "  Backup Files: $backupCount available" -ForegroundColor Gray
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