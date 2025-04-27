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
    
    # Get log directory from module config if available
    $logDir = $DEFAULT_LOG_DIR
    
    if ($ModuleName -and (Test-Path "$env:ROOT_DIR\modules\$ModuleName\config.json")) {
        $logDir = Get-JsonValue "$env:ROOT_DIR\modules\$ModuleName\config.json" ".logging.dir" $DEFAULT_LOG_DIR
    }
    
    # Create log directory
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
    } catch {
        Write-Host "ERROR: Failed to create log directory: $logDir" -ForegroundColor Red
        return $false
    }
    
    # Set up log file with module prefix if applicable
    $prefix = if ($ModuleName) { "${ModuleName}_" } else { "" }
    $script:LOG_FILE = "${logDir}\devenv_${prefix}$(Get-Date -Format 'yyyyMMdd').log"
    
    # Create symlink to latest log
    try {
        $latestLog = "${logDir}\${prefix}latest.log"
        if (Test-Path $latestLog) {
            Remove-Item $latestLog -Force
        }
        New-Item -ItemType SymbolicLink -Path $latestLog -Target $script:LOG_FILE -Force | Out-Null
    } catch {
        # Symlinks might not be available, just create a copy
        try {
            Copy-Item $script:LOG_FILE $latestLog -Force
        } catch {
            # Ignore errors with the latest log
        }
    }
    
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
Initialize-Logging