# lib/windows/execute.ps1 - Windows implementation of DevEnv

param (
    [string]$ConfigFile,
    [string]$RootDir,
    [array]$Args
)

# Load utilities
function Load-Utils {
    param ([string]$RootDir)
    
    # Load logging utility
    $loggingPath = Join-Path -Path $RootDir -ChildPath "lib\windows\logging.ps1"
    if (Test-Path $loggingPath) {
        . $loggingPath
    } else {
        Write-Host "Error: Logging utility not found: $loggingPath" -ForegroundColor Red
        exit 1
    }
    
    # Load JSON utility
    $jsonPath = Join-Path -Path $RootDir -ChildPath "lib\windows\json.ps1"
    if (Test-Path $jsonPath) {
        . $jsonPath
    } else {
        Write-LogError "JSON utility not found: $jsonPath"
        exit 1
    }
    
    # Load module utility
    $modulePath = Join-Path -Path $RootDir -ChildPath "lib\windows\module.ps1"
    if (Test-Path $modulePath) {
        . $modulePath
    } else {
        Write-LogError "Module utility not found: $modulePath"
        exit 1
    }
    
    # Load backup utility
    $backupPath = Join-Path -Path $RootDir -ChildPath "lib\windows\backup.ps1"
    if (Test-Path $backupPath) {
        . $backupPath
    } else {
        Write-LogError "Backup utility not found: $backupPath"
        exit 1
    }
    
    # Load alias utility
    $aliasPath = Join-Path -Path $RootDir -ChildPath "lib\windows\alias.ps1"
    if (Test-Path $aliasPath) {
        . $aliasPath
    } else {
        Write-LogError "Alias utility not found: $aliasPath"
        exit 1
    }
}

# Verify environment
function Test-Environment {
    # Check for required directories
    $libDir = Join-Path -Path $env:ROOT_DIR -ChildPath "lib\windows"
    $modulesDir = Join-Path -Path $env:ROOT_DIR -ChildPath "modules"
    
    foreach ($dir in @($libDir, $modulesDir)) {
        if (-not (Test-Path $dir)) {
            Write-LogError "Required directory not found: $dir"
            return $false
        }
    }
    
    # Check for global config
    if (-not (Test-Path $env:CONFIG_FILE)) {
        Write-LogError "Global config not found: $env:CONFIG_FILE"
        return $false
    }
    
    # Validate global config
    if (-not (Test-JsonFile $env:CONFIG_FILE)) {
        Write-LogError "Config validation failed"
        return $false
    }
    
    return $true
}

# Get ordered list of enabled modules
function Get-OrderedModules {
    $modules = @(Get-JsonValue $env:CONFIG_FILE ".global.modules.order[]")
    $enabledModules = @()
    
    foreach ($module in $modules) {
        if (Test-ModuleEnabled $module) {
            $enabledModules += $module
        }
    }
    
    return $enabledModules
}

# Execute a stage for modules
function Invoke-Stage {
    param (
        [string]$Stage,
        [string]$SpecificModule = "",
        [bool]$Force = $false
    )
    
    $modules = @()
    
    if ($SpecificModule) {
        if (-not (Test-Module $SpecificModule)) {
            return $false
        }
        $modules = @($SpecificModule)
    }
    else {
        $modules = Get-OrderedModules
    }
    
    if ($modules.Count -eq 0) {
        Write-LogWarning "No enabled modules found"
        return $true
    }
    
    Write-LogInfo "Executing stage: $Stage"
    $exitCode = $true
    
    foreach ($module in $modules) {
        # Initialize module context
        if (-not (Initialize-Module $module)) {
            Write-LogError "Failed to initialize module: $module"
            continue
        }
        
        $moduleScript = Join-Path -Path $env:ROOT_DIR -ChildPath "modules\$module\$module.ps1"
        if (Test-Path $moduleScript) {
            Write-LogInfo "Running $Stage for module: $module" $module
            
            switch ($Stage) {
                "install" {
                    & $moduleScript $Stage -Force:$Force
                    if ($LASTEXITCODE -ne 0) { $exitCode = $false }
                }
                "info" {
                    & $moduleScript $Stage
                    # Don't fail on info
                }
                default {
                    & $moduleScript $Stage
                    if ($LASTEXITCODE -ne 0) { $exitCode = $false }
                }
            }
        }
        else {
            Write-LogError "Module script not found: $moduleScript" $module
            if ($Stage -ne "grovel") { $exitCode = $false }
        }
    }
    
    return $exitCode
}

# Show usage information
function Show-Usage {
    Write-Host "Usage: devenv.ps1 COMMAND [MODULE] [OPTIONS]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Cyan
    Write-Host "  install   Install one or all modules"
    Write-Host "  remove    Remove one or all modules"
    Write-Host "  verify    Verify one or all modules"
    Write-Host "  info      Show information about one or all modules"
    Write-Host "  backup    Create backup of current environment"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  -Force    Force installation even if already installed"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  devenv.ps1 install              # Install all modules"
    Write-Host "  devenv.ps1 install git -Force   # Force install git module"
    Write-Host "  devenv.ps1 info docker          # Show docker module information"
    Write-Host "  devenv.ps1 verify               # Verify all modules"
}

# Create backup
function New-ModuleBackup {
    param (
        [string]$SpecificModule = ""
    )
    
    $modules = @()
    
    if ($SpecificModule) {
        $modules = @($SpecificModule)
    }
    else {
        $modules = Get-OrderedModules
    }
    
    foreach ($module in $modules) {
        # Initialize module context
        if (-not (Initialize-Module $module)) {
            Write-LogError "Failed to initialize module: $module"
            continue
        }
        
        Write-LogInfo "Creating backup for module: $module" $module
        
        # Get module-specific backup paths
        $paths = @(Get-ModulePaths $module ".backup.paths[]")
        
        # Get platform-specific backup paths
        $platformPaths = @(Get-ModulePaths $module ".platforms.windows.backup.paths[]")
        
        # Combine paths
        $allPaths = $paths + $platformPaths
        
        foreach ($path in $allPaths) {
            if (Test-Path $path) {
                Backup-File $path $module
            }
        }
    }
}

# Main execution
function Invoke-Main {
    param ([array]$Args)
    
    if ($Args.Count -eq 0) {
        Show-Usage
        exit 1
    }
    
    # Parse arguments
    $action = $Args[0]
    $specificModule = ""
    $force = $false
    
    for ($i = 1; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "-Force" {
                $force = $true
            }
            default {
                if (-not $specificModule) {
                    $specificModule = $Args[$i]
                }
            }
        }
    }
    
    # Verify environment first
    if (-not (Test-Environment)) {
        Write-LogError "Environment verification failed"
        exit 1
    }
    
    switch ($action) {
        "install" {
            New-ModuleBackup $specificModule
            Invoke-Stage "install" $specificModule $force
        }
        "remove" {
            Invoke-Stage "remove" $specificModule
        }
        "verify" {
            Invoke-Stage "verify" $specificModule
        }
        "info" {
            Invoke-Stage "info" $specificModule
        }
        "backup" {
            New-ModuleBackup $specificModule
        }
        default {
            Show-Usage
            exit 1
        }
    }
}

# Setup environment vars
$env:ROOT_DIR = $RootDir
$env:CONFIG_FILE = $ConfigFile

# Load utilities
Load-Utils $RootDir

# Main execution
Invoke-Main $Args