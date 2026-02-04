#Requires -Version 5.1
<#
.SYNOPSIS
    DevEnv - Dual-Mode Hermetic Development Environment Manager
.DESCRIPTION
    Enhanced version with mode detection, dual-mode operation support, and full module installation
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'status', 'create-project', 'list', 'backup', 'restore')]
    [string]$Action = 'info',

    [Parameter(Position = 1)]
    [string[]]$Modules,

    [Parameter()]
    [string]$Template,

    [Parameter()]
    [string]$Name,

    [Parameter()]
    [string]$DataDir,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateSet('Silent', 'Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [string]$LogLevel = 'Information'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get script path at script level (not inside functions)
$script:ScriptPath = if ($PSCommandPath) {
    $PSCommandPath
} elseif ($MyInvocation.MyCommand.Path) {
    $MyInvocation.MyCommand.Path
} else {
    $PSScriptRoot + '\' + $MyInvocation.MyCommand.Name
}
$script:ScriptDir = Split-Path $script:ScriptPath -Parent

# Dot-source library modules
$script:LibDir = Join-Path $script:ScriptDir "lib\windows"
. (Join-Path $script:LibDir "mode.ps1")
. (Join-Path $script:LibDir "modules.ps1")
. (Join-Path $script:LibDir "project.ps1")
. (Join-Path $script:LibDir "status.ps1")
. (Join-Path $script:LibDir "commands.ps1")

#region Main Execution
try {
    # Core mode detection and initialization
    Write-Verbose "Starting DevEnv dual-mode execution..."

    $script:DevEnvContext = Get-ExecutionMode -ScriptPath $script:ScriptPath
    $script:DevEnvContext = Initialize-ExecutionEnvironment $script:DevEnvContext

    Write-Verbose "Execution mode: $($script:DevEnvContext.Mode)"
    Write-Verbose "Data directory: $($script:DevEnvContext.DataDir)"
    Write-Verbose "Config file: $($script:DevEnvContext.ConfigFile)"

    # Route command based on mode and action
    Invoke-ModeAwareCommand -Action $Action -Modules $Modules -DevEnvContext $script:DevEnvContext

} catch {
    Write-Host ""
    Write-Host "ERROR: DevEnv Error" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""

    if ($_.Exception.Message -like "*Cannot determine*") {
        Write-Host "Troubleshooting:" -ForegroundColor Cyan
        Write-Host "- Ensure you're running from a DevEnv repository (global mode)" -ForegroundColor White
        Write-Host "- Or from a project with bin/devenv.ps1 and devenv.json (project mode)" -ForegroundColor White
        Write-Host ""
    }

    exit 1
}
#endregion
