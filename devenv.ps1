#Requires -Version 5.1
<#
.SYNOPSIS
    DevEnv - Hermetic Development Environment Manager for Windows
.DESCRIPTION
    Cross-platform development environment setup with configurable data directories
    for complete environment isolation and portability.
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'backup', 'restore', 'update', 'status', 'list',
                 'list-environments', 'create-environment', 'switch-environment', 'remove-environment')]
    [string]$Action = 'info',
    
    [Parameter(Position = 1)]
    [string]$Module,
    
    [Parameter()]
    [string]$ConfigFile,
    
    [Parameter()]
    [string]$RootDir,
    
    [Parameter()]
    [string]$DataDir,
    
    [Parameter()]
    [string]$Environment,
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [switch]$UseWSL,
    
    [Parameter()]
    [switch]$NoWSL,
    
    [Parameter()]
    [switch]$UseContainers,
    
    [Parameter()]
    [ValidateSet('Silent', 'Error', 'Warning', 'Information', 'Verbose', 'Debug')]
    [string]$LogLevel = 'Information',
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$ShowHelp
)

# Set strict mode and error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

#region Global Variables
$script:Config = $null
$script:IsElevated = $false
$script:WindowsVersion = $null
$script:WSLAvailable = $false
$script:DockerAvailable = $false
$script:LogLevel = $LogLevel
$script:DryRun = $DryRun.IsPresent
$script:EnvironmentConfig = $null
$script:DataDirectory = $null
#endregion

#region Environment Management Functions
function Get-DefaultEnvironmentsRoot {
    return Join-Path $env:USERPROFILE ".devenv\environments"
}

function Get-EnvironmentConfigPath {
    param([string]$EnvironmentName)
    
    $envRoot = Get-DefaultEnvironmentsRoot
    return Join-Path $envRoot "$EnvironmentName.json"
}

function Get-CurrentEnvironment {
    $currentEnvFile = Join-Path (Get-DefaultEnvironmentsRoot) "current.txt"
    
    if (Test-Path $currentEnvFile) {
        $envName = Get-Content $currentEnvFile -ErrorAction SilentlyContinue
        if ($envName -and (Test-EnvironmentExists $envName)) {
            return $envName.Trim()
        }
    }
    
    return "default"
}

function Test-EnvironmentExists {
    param([string]$EnvironmentName)
    
    $configPath = Get-EnvironmentConfigPath $EnvironmentName
    return Test-Path $configPath
}

function Get-EnvironmentConfiguration {
    param([string]$EnvironmentName)
    
    $configPath = Get-EnvironmentConfigPath $EnvironmentName
    
    if (Test-Path $configPath) {
        try {
            return Get-Content $configPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-DevEnvLog "Failed to parse environment config for ${EnvironmentName}: $_" -Level Error
            return $null
        }
    }
    
    return $null
}

function New-Environment {
    param(
        [string]$EnvironmentName,
        [string]$DataDirectory,
        [string]$Description = ""
    )
    
    if (Test-EnvironmentExists $EnvironmentName) {
        throw "Environment '$EnvironmentName' already exists"
    }
    
    # Ensure environments root exists
    $envRoot = Get-DefaultEnvironmentsRoot
    if (-not (Test-Path $envRoot)) {
        New-Item -Path $envRoot -ItemType Directory -Force | Out-Null
    }
    
    # Resolve and validate data directory
    if (-not [System.IO.Path]::IsPathRooted($DataDirectory)) {
        $DataDirectory = Join-Path (Get-Location) $DataDirectory
    }
    $DataDirectory = [System.IO.Path]::GetFullPath($DataDirectory)
    
    # Create environment configuration
    $envConfig = @{
        name = $EnvironmentName
        description = $Description
        data_directory = $DataDirectory
        created = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        version = "1.0"
        platform = "windows"
    }
    
    # Save environment configuration
    $configPath = Get-EnvironmentConfigPath $EnvironmentName
    $envConfig | ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8
    
    # Create data directory structure
    $directories = @(
        $DataDirectory,
        (Join-Path $DataDirectory "state"),
        (Join-Path $DataDirectory "logs"),
        (Join-Path $DataDirectory "backups"),
        (Join-Path $DataDirectory "containers"),
        (Join-Path $DataDirectory "cache"),
        (Join-Path $DataDirectory "python"),
        (Join-Path $DataDirectory "nodejs"),
        (Join-Path $DataDirectory "conda"),
        (Join-Path $DataDirectory "docker"),
        (Join-Path $DataDirectory "vscode"),
        (Join-Path $DataDirectory "bin")
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    
    Write-DevEnvLog "Created environment '$EnvironmentName' at: $DataDirectory" -Level Information
    
    return $envConfig
}

function Set-CurrentEnvironment {
    param([string]$EnvironmentName)
    
    if (-not (Test-EnvironmentExists $EnvironmentName)) {
        throw "Environment '$EnvironmentName' does not exist"
    }
    
    $envRoot = Get-DefaultEnvironmentsRoot
    $currentEnvFile = Join-Path $envRoot "current.txt"
    
    Set-Content $currentEnvFile -Value $EnvironmentName -Encoding UTF8
    Write-DevEnvLog "Switched to environment: $EnvironmentName" -Level Information
}

function Remove-Environment {
    param(
        [string]$EnvironmentName,
        [switch]$RemoveData
    )
    
    if (-not (Test-EnvironmentExists $EnvironmentName)) {
        throw "Environment '$EnvironmentName' does not exist"
    }
    
    if ($EnvironmentName -eq "default") {
        throw "Cannot remove the default environment"
    }
    
    $envConfig = Get-EnvironmentConfiguration $EnvironmentName
    $configPath = Get-EnvironmentConfigPath $EnvironmentName
    
    # Remove data directory if requested
    if ($RemoveData -and $envConfig.data_directory -and (Test-Path $envConfig.data_directory)) {
        Write-DevEnvLog "Removing data directory: $($envConfig.data_directory)" -Level Warning
        Remove-Item $envConfig.data_directory -Recurse -Force
    }
    
    # Remove environment configuration
    Remove-Item $configPath -Force
    
    # If this was the current environment, switch to default
    $currentEnv = Get-CurrentEnvironment
    if ($currentEnv -eq $EnvironmentName) {
        Set-CurrentEnvironment "default"
    }
    
    Write-DevEnvLog "Removed environment: $EnvironmentName" -Level Information
}

function Show-Environments {
    $envRoot = Get-DefaultEnvironmentsRoot
    
    if (-not (Test-Path $envRoot)) {
        Write-Host "No environments found." -ForegroundColor Yellow
        return
    }
    
    $envFiles = Get-ChildItem $envRoot -Filter "*.json"
    $currentEnv = Get-CurrentEnvironment
    
    Write-Host "`nDevEnv Environments:" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    
    foreach ($envFile in $envFiles) {
        $envName = $envFile.BaseName
        $envConfig = Get-EnvironmentConfiguration $envName
        
        if ($envConfig) {
            $marker = if ($envName -eq $currentEnv) { " (current)" } else { "" }
            $status = if (Test-Path $envConfig.data_directory) { "OK" } else { "MISSING" }
            
            Write-Host "`n  $envName$marker" -ForegroundColor $(if($envName -eq $currentEnv){'Green'}else{'White'})
            Write-Host "    Description: $($envConfig.description)" -ForegroundColor Gray
            Write-Host "    Data Dir: $($envConfig.data_directory)" -ForegroundColor Gray
            Write-Host "    Status: $status" -ForegroundColor $(if($status -eq 'OK'){'Green'}else{'Red'})
            Write-Host "    Created: $($envConfig.created)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
}

function Resolve-DataDirectory {
    param(
        [string]$DataDir,
        [string]$Environment
    )
    
    # Priority: explicit DataDir > Environment config > current environment > default
    
    if ($DataDir) {
        # Explicit data directory provided
        if (-not [System.IO.Path]::IsPathRooted($DataDir)) {
            $DataDir = Join-Path (Get-Location) $DataDir
        }
        return [System.IO.Path]::GetFullPath($DataDir)
    }
    
    if ($Environment) {
        # Specific environment requested
        $envConfig = Get-EnvironmentConfiguration $Environment
        if ($envConfig -and $envConfig.data_directory) {
            return $envConfig.data_directory
        }
        throw "Environment '$Environment' not found or has no data directory configured"
    }
    
    # Use current environment
    $currentEnv = Get-CurrentEnvironment
    $envConfig = Get-EnvironmentConfiguration $currentEnv
    
    if ($envConfig -and $envConfig.data_directory) {
        return $envConfig.data_directory
    }
    
    # Fall back to default location
    $defaultDataDir = Join-Path $env:USERPROFILE ".devenv\default"
    
    # Create default environment if it doesn't exist
    if (-not (Test-EnvironmentExists "default")) {
        Write-DevEnvLog "Creating default environment at: $defaultDataDir" -Level Information
        New-Environment -EnvironmentName "default" -DataDirectory $defaultDataDir -Description "Default DevEnv environment"
        Set-CurrentEnvironment "default"
    }
    
    return $defaultDataDir
}
#endregion

#region Logging Functions
function Write-DevEnvLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Error', 'Warning', 'Information', 'Verbose', 'Debug')]
        [string]$Level = 'Information',
        
        [string]$Module = 'DevEnv',
        
        [switch]$NoNewline
    )
    
    $levelPriority = @{
        'Silent' = 0
        'Error' = 1
        'Warning' = 2
        'Information' = 3
        'Verbose' = 4
        'Debug' = 5
    }
    
    if ($levelPriority[$Level] -le $levelPriority[$script:LogLevel]) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $color = switch ($Level) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            'Information' { 'Green' }
            'Verbose' { 'Cyan' }
            'Debug' { 'Magenta' }
        }
        
        $prefix = "[$timestamp] [$Level]"
        if ($Module -ne 'DevEnv') {
            $prefix += " [$Module]"
        }
        
        $output = "$prefix $Message"
        
        if ($NoNewline) {
            Write-Host $output -ForegroundColor $color -NoNewline
        } else {
            Write-Host $output -ForegroundColor $color
        }
        
        # Also write to log file if available
        if ($script:DataDirectory) {
            try {
                $logFile = Join-Path $script:DataDirectory "logs\devenv_$(Get-Date -Format 'yyyyMMdd').log"
                if (Test-Path (Split-Path $logFile -Parent)) {
                    Add-Content -Path $logFile -Value $output -ErrorAction SilentlyContinue
                }
            } catch {
                # Silently ignore logging errors during initialization
            }
        }
    }
}

function Write-Progress-Step {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1
    )
    
    if ($script:LogLevel -ne 'Silent') {
        if ($PercentComplete -ge 0) {
            Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
        } else {
            Write-Progress -Activity $Activity -Status $Status
        }
    }
}
#endregion

#region System Detection Functions
function Test-Administrator {
    try {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$currentUser
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-WindowsVersion {
    try {
        $version = [System.Environment]::OSVersion.Version
        $build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
        
        return @{
            Major = $version.Major
            Minor = $version.Minor
            Build = [int]$build
            IsWindows10OrLater = ($version.Major -eq 10 -and [int]$build -ge 10240) -or $version.Major -gt 10
            IsWindows11OrLater = ($version.Major -eq 10 -and [int]$build -ge 22000) -or $version.Major -gt 10
        }
    }
    catch {
        Write-DevEnvLog "Failed to detect Windows version: $_" -Level Warning
        return @{ Major = 0; Minor = 0; Build = 0; IsWindows10OrLater = $false; IsWindows11OrLater = $false }
    }
}

function Test-WSLAvailable {
    try {
        $wslVersion = wsl.exe --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $distributions = wsl.exe --list --quiet 2>$null
            return ($distributions -and $distributions.Count -gt 0)
        }
        return $false
    }
    catch {
        return $false
    }
}

function Test-DockerAvailable {
    try {
        $null = docker.exe version 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}
#endregion

#region Environment Initialization
function Get-ScriptDirectory {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    elseif ($MyInvocation.MyCommand.Path) {
        return Split-Path $MyInvocation.MyCommand.Path -Parent
    }
    else {
        return Get-Location
    }
}

function Initialize-Environment {
    param(
        [string]$RootDirectory,
        [string]$DataDirectory
    )
    
    Write-DevEnvLog "Initializing DevEnv environment..." -Level Information
    
    # Ensure paths are properly formatted and absolute
    if (-not [System.IO.Path]::IsPathRooted($RootDirectory)) {
        $RootDirectory = Join-Path (Get-Location) $RootDirectory
    }
    $RootDirectory = [System.IO.Path]::GetFullPath($RootDirectory)
    
    if (-not [System.IO.Path]::IsPathRooted($DataDirectory)) {
        $DataDirectory = Join-Path (Get-Location) $DataDirectory
    }
    $DataDirectory = [System.IO.Path]::GetFullPath($DataDirectory)
    
    # Store for later use
    $script:DataDirectory = $DataDirectory
    
    Write-DevEnvLog "Root Directory: $RootDirectory" -Level Debug
    Write-DevEnvLog "Data Directory: $DataDirectory" -Level Debug
    
    # Detect system capabilities
    $script:IsElevated = Test-Administrator
    $script:WindowsVersion = Get-WindowsVersion
    $script:WSLAvailable = Test-WSLAvailable
    $script:DockerAvailable = Test-DockerAvailable
    
    Write-DevEnvLog "System Detection Results:" -Level Verbose
    Write-DevEnvLog "  Administrator: $($script:IsElevated)" -Level Verbose
    Write-DevEnvLog "  Windows Version: $($script:WindowsVersion.Major).$($script:WindowsVersion.Minor) (Build $($script:WindowsVersion.Build))" -Level Verbose
    Write-DevEnvLog "  WSL Available: $($script:WSLAvailable)" -Level Verbose
    Write-DevEnvLog "  Docker Available: $($script:DockerAvailable)" -Level Verbose
    
    # Set up environment variables - ALL paths now use the configurable data directory
    $envVars = @{
        'ROOT_DIR' = $RootDirectory
        'DEVENV_ROOT' = $RootDirectory
        'CONFIG_FILE' = Join-Path $RootDirectory "config.json"
        'DEVENV_DATA_DIR' = $DataDirectory
        'DEVENV_MODULES_DIR' = Join-Path $RootDirectory "modules"
        
        # All data-related paths use the configurable data directory
        'DEVENV_STATE_DIR' = Join-Path $DataDirectory "state"
        'DEVENV_LOGS_DIR' = Join-Path $DataDirectory "logs"
        'DEVENV_BACKUPS_DIR' = Join-Path $DataDirectory "backups"
        'DEVENV_CACHE_DIR' = Join-Path $DataDirectory "cache"
        'DEVENV_CONTAINERS_DIR' = Join-Path $DataDirectory "containers"
        'DEVENV_BIN_DIR' = Join-Path $DataDirectory "bin"
        
        # Module-specific data directories (hermetic!)
        'DEVENV_PYTHON_DIR' = Join-Path $DataDirectory "python"
        'DEVENV_NODEJS_DIR' = Join-Path $DataDirectory "nodejs"
        'DEVENV_CONDA_DIR' = Join-Path $DataDirectory "conda"
        'DEVENV_DOCKER_DIR' = Join-Path $DataDirectory "docker"
        'DEVENV_VSCODE_DIR' = Join-Path $DataDirectory "vscode"
        'DEVENV_GIT_DIR' = Join-Path $DataDirectory "git"
    }
    
    # Set all environment variables in the current process
    foreach ($var in $envVars.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($var.Key, $var.Value, [System.EnvironmentVariableTarget]::Process)
        Set-Item -Path "env:$($var.Key)" -Value $var.Value
        Write-DevEnvLog "Set environment variable: $($var.Key) = $($var.Value)" -Level Debug
    }
    
    # Platform and execution mode setup
    [System.Environment]::SetEnvironmentVariable('DEVENV_PLATFORM', 'windows', [System.EnvironmentVariableTarget]::Process)
    Set-Item -Path "env:DEVENV_PLATFORM" -Value 'windows'
    
    $executionMode = if ($UseWSL -and $script:WSLAvailable) {
        "wsl"
    } elseif ($NoWSL -or -not $script:WSLAvailable) {
        "native"
    } else {
        "hybrid"
    }
    
    [System.Environment]::SetEnvironmentVariable('DEVENV_EXECUTION_MODE', $executionMode, [System.EnvironmentVariableTarget]::Process)
    Set-Item -Path "env:DEVENV_EXECUTION_MODE" -Value $executionMode
    
    $containerPreference = if ($UseContainers -and $script:DockerAvailable) { "true" } else { "false" }
    [System.Environment]::SetEnvironmentVariable('DEVENV_PREFER_CONTAINERS', $containerPreference, [System.EnvironmentVariableTarget]::Process)
    Set-Item -Path "env:DEVENV_PREFER_CONTAINERS" -Value $containerPreference
    
    # Create required directories in the data directory
    $directories = @(
        $DataDirectory,
        (Join-Path $DataDirectory "state"),
        (Join-Path $DataDirectory "logs"),
        (Join-Path $DataDirectory "backups"),
        (Join-Path $DataDirectory "containers"),
        (Join-Path $DataDirectory "cache"),
        (Join-Path $DataDirectory "bin"),
        (Join-Path $DataDirectory "python"),
        (Join-Path $DataDirectory "nodejs"),
        (Join-Path $DataDirectory "conda"),
        (Join-Path $DataDirectory "docker"),
        (Join-Path $DataDirectory "vscode"),
        (Join-Path $DataDirectory "git")
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            try {
                if (-not $script:DryRun) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                }
                Write-DevEnvLog "Created directory: $dir" -Level Debug
            }
            catch {
                Write-DevEnvLog "Failed to create directory ${dir}: $_" -Level Error
                throw
            }
        }
    }
    
    Write-DevEnvLog "Environment initialized (Mode: $env:DEVENV_EXECUTION_MODE, Containers: $env:DEVENV_PREFER_CONTAINERS)" -Level Information
    Write-DevEnvLog "Data Directory: $DataDirectory" -Level Information
}
#endregion

#region Help and Status Functions
function Show-Help {
    @"
DevEnv - Hermetic Development Environment Manager for Windows

USAGE:
    devenv.ps1 [ACTION] [MODULE] [OPTIONS]

ACTIONS:
    install                 Install modules (default: all enabled modules)
    remove                  Remove/uninstall modules  
    verify                  Verify module installation and configuration
    info                    Show module information and status
    backup                  Create backup of current configuration
    restore                 Restore from backup
    update                  Update modules to latest versions
    status                  Show overall system status
    list                    List all available modules

ENVIRONMENT ACTIONS:
    list-environments       List all available environments
    create-environment      Create a new environment
    switch-environment      Switch to a different environment  
    remove-environment      Remove an environment

OPTIONS:
    -Module <name>          Target specific module
    -DataDir <path>         Specify data directory for this session
    -Environment <name>     Use specific named environment
    -Force                  Force operation even if already configured
    -UseWSL                 Prefer WSL execution when available
    -NoWSL                  Use only native Windows execution
    -UseContainers          Prefer containerized execution
    -LogLevel <level>       Set logging verbosity (Silent|Error|Warning|Information|Verbose|Debug)
    -DryRun                 Show what would be done without executing
    -ShowHelp               Show this help message

HERMETIC ENVIRONMENT EXAMPLES:
    # Create isolated environments for different projects
    devenv.ps1 create-environment "project-a" -DataDir "C:\Projects\ProjectA\.devenv"
    devenv.ps1 create-environment "project-b" -DataDir "C:\Projects\ProjectB\.devenv"
    
    # Switch between environments
    devenv.ps1 switch-environment "project-a"
    devenv.ps1 install python nodejs
    
    # Use temporary environment without switching
    devenv.ps1 install python -DataDir "C:\Temp\test-env"
    
    # List all environments
    devenv.ps1 list-environments

STANDARD USAGE EXAMPLES:
    devenv.ps1                          # Show info for current environment
    devenv.ps1 install                  # Install all enabled modules in current environment
    devenv.ps1 install python -Force    # Force reinstall Python module
    devenv.ps1 verify git              # Verify Git module installation
    devenv.ps1 status                  # Show system and environment status

EXECUTION MODES:
    Native:     Pure Windows PowerShell execution
    WSL:        Use Windows Subsystem for Linux
    Container:  Use Docker containers (recommended)

HERMETIC BENEFITS:
    - Complete environment isolation per project
    - Zero system pollution outside of system-wide tools
    - Portable environments (copy data directory = copy environment)
    - Multiple Python/Node versions without conflicts
    - Team collaboration via shared environment configs

For more information, visit: https://github.com/your-repo/devenv
"@
}

function Show-SystemStatus {
    $currentEnv = Get-CurrentEnvironment
    $envConfig = Get-EnvironmentConfiguration $currentEnv
    
    Write-Host "`nDevEnv System Status" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    
    Write-Host "`nSystem Information:" -ForegroundColor Yellow
    Write-Host "  Platform: Windows $($script:WindowsVersion.Major).$($script:WindowsVersion.Minor) (Build $($script:WindowsVersion.Build))"
    Write-Host "  Administrator: $(if($script:IsElevated){'Yes'}else{'No'})"
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)"
    
    Write-Host "`nExecution Capabilities:" -ForegroundColor Yellow
    Write-Host "  WSL Available: $(if($script:WSLAvailable){'Yes'}else{'No'})"
    Write-Host "  Docker Available: $(if($script:DockerAvailable){'Yes'}else{'No'})"
    
    Write-Host "`nCurrent Environment:" -ForegroundColor Yellow
    Write-Host "  Environment: $currentEnv"
    if ($envConfig) {
        Write-Host "  Description: $($envConfig.description)"
        Write-Host "  Data Directory: $($envConfig.data_directory)"
        Write-Host "  Created: $($envConfig.created)"
        $dataStatus = if (Test-Path $envConfig.data_directory) { "OK" } else { "MISSING" }
        Write-Host "  Status: $dataStatus" -ForegroundColor $(if($dataStatus -eq 'OK'){'Green'}else{'Red'})
    }
    
    Write-Host "`nExecution Configuration:" -ForegroundColor Yellow
    Write-Host "  Execution Mode: $env:DEVENV_EXECUTION_MODE"
    Write-Host "  Prefer Containers: $env:DEVENV_PREFER_CONTAINERS"
    Write-Host "  Root Directory: $env:DEVENV_ROOT"
    
    # Show enabled modules if config is loaded
    if ($script:Config) {
        $enabledModules = Get-EnabledModules -Config $script:Config
        Write-Host "`nEnabled Modules ($($enabledModules.Count)):" -ForegroundColor Yellow
        foreach ($module in $enabledModules) {
            $executionMode = Get-ModuleExecutionMode -ModuleName $module
            Write-Host "  $module ($executionMode)"
        }
    }
}
#endregion

#region Environment Action Handlers
function Invoke-EnvironmentAction {
    param([string]$Action, [string]$EnvironmentName)
    
    switch ($Action) {
        'list-environments' {
            Show-Environments
        }
        'create-environment' {
            if (-not $EnvironmentName) {
                Write-DevEnvLog "Environment name is required for create-environment" -Level Error
                return
            }
            
            $dataDir = if ($DataDir) { $DataDir } else { 
                $defaultLocation = Join-Path $env:USERPROFILE ".devenv\$EnvironmentName"
                Read-Host "Enter data directory for environment '$EnvironmentName' (default: $defaultLocation)"
            }
            
            if (-not $dataDir) {
                $dataDir = Join-Path $env:USERPROFILE ".devenv\$EnvironmentName"
            }
            
            $description = Read-Host "Enter description for environment '$EnvironmentName' (optional)"
            
            try {
                New-Environment -EnvironmentName $EnvironmentName -DataDirectory $dataDir -Description $description
                Write-DevEnvLog "Environment '$EnvironmentName' created successfully" -Level Information
                
                $switchNow = Read-Host "Switch to environment '$EnvironmentName' now? (y/N)"
                if ($switchNow -match '^[Yy]') {
                    Set-CurrentEnvironment $EnvironmentName
                }
            }
            catch {
                Write-DevEnvLog "Failed to create environment: $_" -Level Error
            }
        }
        'switch-environment' {
            if (-not $EnvironmentName) {
                Show-Environments
                $EnvironmentName = Read-Host "Enter environment name to switch to"
            }
            
            if ($EnvironmentName) {
                try {
                    Set-CurrentEnvironment $EnvironmentName
                    Write-DevEnvLog "Switched to environment: $EnvironmentName" -Level Information
                }
                catch {
                    Write-DevEnvLog "Failed to switch environment: $_" -Level Error
                }
            }
        }
        'remove-environment' {
            if (-not $EnvironmentName) {
                Show-Environments
                $EnvironmentName = Read-Host "Enter environment name to remove"
            }
            
            if ($EnvironmentName) {
                $confirmRemove = Read-Host "Remove environment '$EnvironmentName'? This will delete the configuration (y/N)"
                if ($confirmRemove -match '^[Yy]') {
                    $removeData = Read-Host "Also remove data directory? This cannot be undone! (y/N)"
                    try {
                        Remove-Environment -EnvironmentName $EnvironmentName -RemoveData:($removeData -match '^[Yy]')
                    }
                    catch {
                        Write-DevEnvLog "Failed to remove environment: $_" -Level Error
                    }
                }
            }
        }
    }
}
#endregion

# Placeholder for remaining functions (module management, etc.)
# These would be the same as before but using the new data directory structure

#region Main Execution
try {
    # Show help if requested
    if ($ShowHelp) {
        Show-Help
        exit 0
    }
    
    # Handle environment management actions first (before full initialization)
    if ($Action -in @('list-environments', 'create-environment', 'switch-environment', 'remove-environment')) {
        Invoke-EnvironmentAction -Action $Action -EnvironmentName $Module
        exit 0
    }
    
    # Determine root directory
    if (-not $RootDir) {
        $RootDir = Get-ScriptDirectory
    }
    
    # Resolve data directory based on parameters and current environment
    $resolvedDataDir = Resolve-DataDirectory -DataDir $DataDir -Environment $Environment
    
    # Initialize environment with resolved data directory
    Initialize-Environment -RootDirectory $RootDir -DataDirectory $resolvedDataDir
    
    # Load configuration
    if (-not $ConfigFile) {
        $ConfigFile = Join-Path $RootDir "config.json"
    }
    
    if (Test-Path $ConfigFile) {
        $script:Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } else {
        Write-DevEnvLog "Configuration file not found: $ConfigFile" -Level Warning
    }
    
    # Execute main actions
    switch ($Action.ToLower()) {
        'status' {
            Show-SystemStatus
        }
        'list' {
            if ($script:Config) {
                $enabledModules = Get-EnabledModules -Config $script:Config
                Write-Host "`nAvailable Modules:" -ForegroundColor Cyan
                foreach ($module in $enabledModules) {
                    $mode = Get-ModuleExecutionMode -ModuleName $module
                    Write-Host "  $module ($mode)" -ForegroundColor Green
                }
            } else {
                Write-DevEnvLog "No configuration loaded" -Level Warning
            }
        }
        'info' {
            if ($Module) {
                # Show specific module info (would invoke module)
                Write-DevEnvLog "Module info for: $Module" -Level Information
            } else {
                Show-SystemStatus
                Write-Host ""
                # Show all module info (would invoke all modules)
            }
        }
        default {
            # Handle install, remove, verify, etc. (would use existing logic but with new paths)
            Write-DevEnvLog "Action '$Action' would be executed for environment data directory: $resolvedDataDir" -Level Information
            if ($Module) {
                Write-DevEnvLog "Target module: $Module" -Level Information
            }
        }
    }
    
    Write-DevEnvLog "DevEnv operation completed successfully" -Level Information
}
catch {
    Write-DevEnvLog "DevEnv operation failed: $_" -Level Error
    Write-DevEnvLog "Stack trace: $($_.ScriptStackTrace)" -Level Debug
    exit 1
}
finally {
    # Cleanup
    if (Get-Command Write-Progress -ErrorAction SilentlyContinue) {
        Write-Progress -Activity "DevEnv" -Completed
    }
}
#endregion