# lib/windows/logging.ps1 - PowerShell logging utilities

# Default configurations
$DEFAULT_LOG_LEVEL = "INFO"
$DEFAULT_LOG_DIR = "$env:USERPROFILE\.devenv\logs"

# Initialize logging
function Initialize-Logging {
    param (
        [string]$ModuleName = ""
    )
    
    # Preserve existing LOG_LEVEL if set
    if (-not $env:LOG_LEVEL) {
        $script:LOG_LEVEL = $DEFAULT_LOG_LEVEL
    } else {
        $script:LOG_LEVEL = $env:LOG_LEVEL
    }
    
    # Get log directory from environment or fallback
    $logDir = $env:DEVENV_LOGS_DIR
    if (-not $logDir) {
        $logDir = Join-Path $env:USERPROFILE ".devenv\logs"
    }
    
    # If module specified, try to find module-specific log dir
    if ($ModuleName -and $env:DEVENV_ROOT) {
        $moduleConfigPath = Join-Path $env:DEVENV_ROOT "modules\$ModuleName\config.json"
        if (Test-Path $moduleConfigPath) {
            $moduleLogDir = Get-JsonValue $moduleConfigPath ".logging.dir" $null
            if ($moduleLogDir) { $logDir = $moduleLogDir }
        }
    }
    
    # Create log directory
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        } catch {
            # Absolute fallback to USERPROFILE\.devenv\logs if specified failed
            $logDir = Join-Path $env:USERPROFILE ".devenv\logs"
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }
        }
    }
    
    # Set up log file with module prefix
    $prefix = if ($ModuleName) { "${ModuleName}_" } else { "" }
    $timestamp = Get-Date -Format 'yyyyMMdd'
    if ($null -eq $logDir) {
        $logDir = Join-Path $env:USERPROFILE ".devenv\logs"
    }
    $script:LOG_FILE = Join-Path $logDir "devenv_${prefix}${timestamp}.log"
    
    return $true
}

# Logging function with severity levels and colors
function Write-Log {
    param (
        [string]$Level,
        [string]$Message,
        [string]$Module = ""
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Only log if level is appropriate for current LOG_LEVEL
    switch ($script:LOG_LEVEL) {
        "DEBUG" {
            # Log everything
        }
        "INFO" {
            # Skip DEBUG
            if ($Level -eq "DEBUG") { return }
        }
        "WARN" {
            # Skip DEBUG and INFO
            if ($Level -eq "DEBUG" -or $Level -eq "INFO") { return }
        }
        "ERROR" {
            # Skip DEBUG, INFO, and WARN
            if ($Level -ne "ERROR") { return }
        }
    }
    
    # Ensure LOG_FILE is set
    if (-not $script:LOG_FILE) {
        Write-Host "ERROR: LOG_FILE is not set" -ForegroundColor Red
        return
    }
    
    # Format message with optional module prefix
    $logMessage = "[$timestamp] [$Level]$(if ($Module) { " [$Module]" }) $Message"
    
    # Write to log file
    try {
        Add-Content -Path $script:LOG_FILE -Value $logMessage
    } catch {
        Write-Host "ERROR: Failed to write to log file: $_" -ForegroundColor Red
    }
    
    # Console output with colors
    $foregroundColor = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "INFO" { "Green" }
        "DEBUG" { "Cyan" }
        default { "White" }
    }
    
    Write-Host "[$Level]$(if ($Module) { " [$Module]" }) $Message" -ForegroundColor $foregroundColor
}

# Helper functions for specific log levels
function Write-LogError {
    param (
        [string]$Message,
        [string]$Module = ""
    )
    Write-Log "ERROR" $Message $Module
}

function Write-LogWarning {
    param (
        [string]$Message,
        [string]$Module = ""
    )
    Write-Log "WARN" $Message $Module
}

function Write-LogInfo {
    param (
        [string]$Message,
        [string]$Module = ""
    )
    Write-Log "INFO" $Message $Module
}

function Write-LogDebug {
    param (
        [string]$Message,
        [string]$Module = ""
    )
    Write-Log "DEBUG" $Message $Module
}

# Initialize logging on import
$null = Initialize-Logging