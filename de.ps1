#Requires -Version 5.1
<#
.SYNOPSIS
    DevEnv Wrapper - Ensures proper initialization and execution context
.DESCRIPTION
    This wrapper script handles all environment setup, path resolution, and
    context management for DevEnv, preventing common initialization errors.
.EXAMPLE
    .\de.ps1 install
    .\de.ps1 install python -Force
    .\de.ps1 status
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = 'info',
    
    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$RemainingArgs
)

# Capture the original location to restore later
$originalLocation = Get-Location
$scriptStartTime = Get-Date

# Determine script location with multiple fallback methods
function Get-ScriptDirectory {
    $scriptPath = $null
    
    # Method 1: PSCommandPath (most reliable in PS 3.0+)
    if ($PSCommandPath) {
        $scriptPath = $PSCommandPath
    }
    # Method 2: MyInvocation
    elseif ($MyInvocation.MyCommand.Path) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }
    # Method 3: PSScriptRoot fallback
    elseif ($PSScriptRoot) {
        return $PSScriptRoot
    }
    # Method 4: Fallback to current directory
    else {
        Write-Warning "Could not determine script path, using current directory"
        return (Get-Location).Path
    }
    
    return Split-Path $scriptPath -Parent
}

try {
    # Clear any existing DevEnv environment variables to start fresh
    @(
        'DEVENV_ROOT',
        'DEVENV_MODE', 
        'DEVENV_DATA_DIR',
        'DEVENV_CONFIG_FILE',
        'DEVENV_STATE_DIR',
        'DEVENV_LOGS_DIR',
        'DEVENV_BACKUPS_DIR',
        'DEVENV_MODULES_DIR',
        'DEVENV_PYTHON_DIR',
        'ROOT_DIR'
    ) | ForEach-Object {
        Remove-Item "env:$_" -ErrorAction SilentlyContinue
    }

    # Get the directory where this wrapper script is located
    $devenvRoot = Get-ScriptDirectory
    
    # Ensure we have a valid DevEnv root
    if (-not $devenvRoot -or -not (Test-Path $devenvRoot)) {
        throw "Cannot determine DevEnv root directory"
    }
    
    # Change to DevEnv root directory
    Set-Location $devenvRoot
    
    Write-Host "DevEnv Wrapper Initialization" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "Root Directory: $devenvRoot" -ForegroundColor Gray
    
    # Verify critical files exist
    $requiredFiles = @(
        'devenv.ps1',
        'config.json',
        'lib\windows\logging.ps1',
        'lib\windows\json.ps1',
        'lib\windows\module.ps1'
    )
    
    $missingFiles = @()
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $devenvRoot $file
        if (-not (Test-Path $filePath)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-Host "`nERROR: Missing required files:" -ForegroundColor Red
        $missingFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "`nPlease ensure DevEnv is properly installed." -ForegroundColor Yellow
        exit 1
    }
    
    # Verify config.json is valid
    try {
        $configPath = Join-Path $devenvRoot "config.json"
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        Write-Host "Configuration: Valid (v$($config.version))" -ForegroundColor Gray
    }
    catch {
        Write-Host "`nERROR: Invalid config.json file" -ForegroundColor Red
        Write-Host "Details: $_" -ForegroundColor Yellow
        exit 1
    }
    
    # Check PowerShell execution policy
    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'AllSigned') {
        Write-Host "`nWARNING: Execution policy is $currentPolicy" -ForegroundColor Yellow
        Write-Host "Attempting to run with Bypass policy for this session..." -ForegroundColor Yellow
    }
    
    # Pre-set environment variables that DevEnv expects
    # This ensures they're available when devenv.ps1 runs
    $env:DEVENV_ROOT = $devenvRoot
    $env:ROOT_DIR = $devenvRoot
    $env:DEVENV_CONFIG_FILE = Join-Path $devenvRoot "config.json"
    $env:DEVENV_MODULES_DIR = Join-Path $devenvRoot "modules"
    
    # Determine if we're in project mode by looking for a parent devenv.json
    $projectRoot = $null
    $currentDir = Get-Location
    $parentDir = $currentDir
    
    # Search up the directory tree for devenv.json
    while ($parentDir -and (Split-Path $parentDir -Parent) -ne $parentDir) {
        $projectConfig = Join-Path $parentDir "devenv.json"
        if (Test-Path $projectConfig) {
            $projectRoot = $parentDir
            Write-Host "Project Mode: Detected at $projectRoot" -ForegroundColor Magenta
            break
        }
        $parentDir = Split-Path $parentDir -Parent
    }
    
    # Set data directory based on mode
    if ($projectRoot) {
        $env:DEVENV_MODE = "Project"
        $env:DEVENV_DATA_DIR = Join-Path $projectRoot ".devenv"
        $env:DEVENV_PROJECT_ROOT = $projectRoot
    }
    else {
        $env:DEVENV_MODE = "Global"
        $env:DEVENV_DATA_DIR = Join-Path $env:USERPROFILE ".devenv"
    }
    
    # Set derived paths
    $env:DEVENV_STATE_DIR = Join-Path $env:DEVENV_DATA_DIR "state"
    $env:DEVENV_LOGS_DIR = Join-Path $env:DEVENV_DATA_DIR "logs"
    $env:DEVENV_BACKUPS_DIR = Join-Path $env:DEVENV_DATA_DIR "backups"
    
    # Module-specific directories
    $env:DEVENV_PYTHON_DIR = Join-Path $env:DEVENV_DATA_DIR "python"
    $env:DEVENV_NODEJS_DIR = Join-Path $env:DEVENV_DATA_DIR "nodejs"
    $env:DEVENV_GO_DIR = Join-Path $env:DEVENV_DATA_DIR "go"
    
    # Ensure data directories exist
    @(
        $env:DEVENV_DATA_DIR,
        $env:DEVENV_STATE_DIR,
        $env:DEVENV_LOGS_DIR,
        $env:DEVENV_BACKUPS_DIR
    ) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null
        }
    }
    
    Write-Host "Mode: $($env:DEVENV_MODE)" -ForegroundColor $(if ($env:DEVENV_MODE -eq "Project") { "Magenta" } else { "Green" })
    Write-Host "Data Directory: $($env:DEVENV_DATA_DIR)" -ForegroundColor Gray
    Write-Host ""
    
    # Build the command line arguments
    $devenvScript = Join-Path $devenvRoot "devenv.ps1"
    $arguments = @($Action)
    if ($RemainingArgs) {
        $arguments += $RemainingArgs
    }
    
    # Execute DevEnv with proper context
    # Using & operator to ensure proper argument passing
    & $devenvScript @arguments
    
    # Capture exit code
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    
    # Report execution time
    $executionTime = (Get-Date) - $scriptStartTime
    Write-Host "`nExecution completed in $($executionTime.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Gray
    
    exit $exitCode
}
catch {
    Write-Host "`nFATAL ERROR in DevEnv Wrapper:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Error Details:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
finally {
    # Always restore original location
    Set-Location $originalLocation
}