# lib/windows/module.ps1 - PowerShell module utilities with robust path handling

# Get module configuration with robust path resolution
function Get-ModuleConfig {
    param (
        [string]$Module,
        [string]$Key,
        $Default = $null,
        [string]$Platform = "windows"
    )
    
    if ([string]::IsNullOrWhiteSpace($Module)) {
        Write-LogError "Module name cannot be empty" $Module
        return $Default
    }
    
    # Try multiple environment variable names for compatibility
    $rootDir = $env:DEVENV_ROOT
    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        $rootDir = $env:ROOT_DIR
    }
    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        # Fallback to script location
        if ($PSScriptRoot) {
            # Navigate up to find the root directory (assuming we're in lib/windows)
            $rootDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        Write-LogError "Cannot determine DevEnv root directory. Please ensure DEVENV_ROOT environment variable is set." $Module
        return $Default
    }
    
    $configFile = Join-Path $rootDir "modules\$Module\config.json"
    
    if (-not (Test-Path $configFile)) {
        Write-LogError "Module configuration not found: $configFile" $Module
        return $Default
    }
    
    try {
        # Get platform-specific or global configuration
        $value = Get-ConfigValue $configFile $Key $Default $Platform $Module
        return $value
    } catch {
        Write-LogError "Failed to get module config ${Module}.${Key}: $_" $Module
        return $Default
    }
}

# Check if module is enabled
function Test-ModuleEnabled {
    param (
        [string]$Module,
        [string]$Platform = "windows"
    )
    
    if ([string]::IsNullOrWhiteSpace($Module)) {
        return $false
    }
    
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
    
    if ([string]::IsNullOrWhiteSpace($Module)) {
        return 999
    }
    
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
    
    if ([string]::IsNullOrWhiteSpace($Module)) {
        return @()
    }
    
    # Try platform-specific dependencies first
    $dependencies = @(Get-ModuleConfig $Module ".platforms.$Platform.dependencies[]" @() $Platform)
    
    # Get global dependencies and combine
    $globalDeps = @(Get-ModuleConfig $Module ".dependencies[]" @())
    
    return ($dependencies + $globalDeps | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

# Verify module configuration
function Test-Module {
    param (
        [string]$Module
    )
    
    if ([string]::IsNullOrWhiteSpace($Module)) {
        Write-LogError "Module name cannot be empty" $Module
        return $false
    }
    
    # Try multiple environment variable names for compatibility
    $rootDir = $env:DEVENV_ROOT
    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        $rootDir = $env:ROOT_DIR
    }
    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        Write-LogError "Cannot determine DevEnv root directory" $Module
        return $false
    }
    
    $configFile = Join-Path $rootDir "modules\$Module\config.json"
    
    # Check for required files
    if (-not (Test-Path $configFile)) {
        Write-LogError "Module configuration not found: $configFile" $Module
        return $false
    }
    
    $moduleScript = Join-Path $rootDir "modules\$Module\$Module.ps1"
    if (-not (Test-Path $moduleScript)) {
        Write-LogError "Module script not found: $moduleScript" $Module
        return $false
    }
    
    # Validate JSON configuration
    if (-not (Test-JsonFile $configFile -ModuleName $Module)) {
        return $false
    }
    
    return $true
}

# Initialize module with validation
function Initialize-Module {
    param (
        [string]$Module
    )
    
    if ([string]::IsNullOrWhiteSpace($Module)) {
        Write-Error "Module name cannot be empty"
        return $false
    }
    
    # Save current LOG_LEVEL
    $currentLogLevel = if ($script:LOG_LEVEL) { $script:LOG_LEVEL } else { "INFO" }
    
    # Verify module first
    if (-not (Test-Module $Module)) {
        return $false
    }
    
    # Initialize module-specific logging with preserved log level
    $env:LOG_LEVEL = $currentLogLevel
    try {
        Initialize-Logging $Module
    } catch {
        Write-Warning "Failed to initialize logging for module $Module`: $_"
    }
    
    # Export module context variables with robust path resolution
    $rootDir = $env:DEVENV_ROOT
    if ([string]::IsNullOrWhiteSpace($rootDir)) {
        $rootDir = $env:ROOT_DIR
    }
    
    if (-not [string]::IsNullOrWhiteSpace($rootDir)) {
        $env:MODULE_NAME = $Module
        $env:MODULE_DIR = Join-Path $rootDir "modules\$Module"
        $env:MODULE_CONFIG = Join-Path $env:MODULE_DIR "config.json"
    }
    
    return $true
}

# Get array of paths from module configuration with substitution
function Get-ModulePaths {
    param (
        [string]$Module,
        [string]$KeyPath,
        [string]$Platform = "windows"
    )
    
    if ([string]::IsNullOrWhiteSpace($Module) -or [string]::IsNullOrWhiteSpace($KeyPath)) {
        return @()
    }
    
    $paths = @(Get-ModuleConfig $Module $KeyPath @() $Platform)
    $expandedPaths = @()
    
    foreach ($path in $paths) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
            if (-not [string]::IsNullOrWhiteSpace($expandedPath)) {
                $expandedPaths += $expandedPath
            }
        }
    }
    
    return $expandedPaths
}

# Create a directory if it doesn't exist with validation
function Ensure-Directory {
    param (
        [string]$Path,
        [string]$ModuleName = ""
    )
    
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-LogError "Path cannot be empty" $ModuleName
        return $false
    }
    
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-LogInfo "Created directory: $Path" $ModuleName
        }
        return $true
    } catch {
        Write-LogError "Failed to create directory ${Path}: $_" $ModuleName
        return $false
    }
}