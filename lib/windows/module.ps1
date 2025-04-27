# lib/windows/module.ps1 - PowerShell module utilities

# Get module configuration
function Get-ModuleConfig {
    param (
        [string]$Module,
        [string]$Key,
        $Default = $null,
        [string]$Platform = "windows"
    )
    
    $configFile = "$env:ROOT_DIR\modules\$Module\config.json"
    
    # Get platform-specific or global configuration
    $value = Get-ConfigValue $configFile $Key $Default $Platform $Module
    
    return $value
}

# Check if module is enabled
function Test-ModuleEnabled {
    param (
        [string]$Module,
        [string]$Platform = "windows"
    )
    
    # Check global enabled status
    $enabled = Get-ModuleConfig $Module ".enabled" $false
    
    if (-not $enabled) {
        return $false
    }
    
    # Check platform-specific enabled status if it exists
    $platformEnabled = Get-ModuleConfig $Module ".platforms.$Platform.enabled" $true $Platform
    
    return $platformEnabled
}

# Get module runlevel
function Get-ModuleRunlevel {
    param (
        [string]$Module,
        [string]$Platform = "windows"
    )
    
    # Try platform-specific runlevel first
    $runlevel = Get-ModuleConfig $Module ".platforms.$Platform.runlevel" $null $Platform
    
    # Fall back to global runlevel
    if ($null -eq $runlevel) {
        $runlevel = Get-ModuleConfig $Module ".runlevel" 999
    }
    
    return $runlevel
}

# Get module dependencies
function Get-ModuleDependencies {
    param (
        [string]$Module,
        [string]$Platform = "windows"
    )
    
    # Try platform-specific dependencies first
    $dependencies = @(Get-ModuleConfig $Module ".platforms.$Platform.dependencies[]" @() $Platform)
    
    # Get global dependencies and combine
    $globalDeps = @(Get-ModuleConfig $Module ".dependencies[]" @())
    
    return ($dependencies + $globalDeps | Select-Object -Unique)
}

# Verify module configuration
function Test-Module {
    param (
        [string]$Module
    )
    
    $configFile = "$env:ROOT_DIR\modules\$Module\config.json"
    
    # Check for required files
    if (-not (Test-Path $configFile)) {
        Write-LogError "Module configuration not found" $Module
        return $false
    }
    
    if (-not (Test-Path "$env:ROOT_DIR\modules\$Module\$Module.ps1")) {
        Write-LogError "Module script not found" $Module
        return $false
    }
    
    # Validate JSON configuration
    if (-not (Test-JsonFile $configFile -ModuleName $Module)) {
        return $false
    }
    
    return $true
}

# Initialize module
function Initialize-Module {
    param (
        [string]$Module
    )
    
    # Save current LOG_LEVEL
    $currentLogLevel = $script:LOG_LEVEL
    
    # Verify module first
    if (-not (Test-Module $Module)) {
        return $false
    }
    
    # Initialize module-specific logging with preserved log level
    $env:LOG_LEVEL = $currentLogLevel
    Initialize-Logging $Module
    
    # Export module context variables
    $env:MODULE_NAME = $Module
    $env:MODULE_DIR = "$env:ROOT_DIR\modules\$Module"
    $env:MODULE_CONFIG = "$env:MODULE_DIR\config.json"
    
    return $true
}

# Get array of paths from module configuration with substitution
function Get-ModulePaths {
    param (
        [string]$Module,
        [string]$KeyPath,
        [string]$Platform = "windows"
    )
    
    $paths = @(Get-ModuleConfig $Module $KeyPath @() $Platform)
    $expandedPaths = @()
    
    foreach ($path in $paths) {
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
        $expandedPaths += $expandedPath
    }
    
    return $expandedPaths
}

# Create a directory if it doesn't exist
function Ensure-Directory {
    param (
        [string]$Path,
        [string]$ModuleName = ""
    )
    
    if (-not (Test-Path $Path)) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-LogInfo "Created directory: $Path" $ModuleName
            return $true
        }
        catch {
            Write-LogError "Failed to create directory ${Path}: $_" $ModuleName
            return $false
        }
    }
    
    return $true
}