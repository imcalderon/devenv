#Requires -Version 5.1
<#
.SYNOPSIS
    DevEnv - Development Environment Manager for Windows
.DESCRIPTION
    Cross-platform development environment setup with native Windows and WSL support,
    emphasizing containerization for reproducible development environments.
.PARAMETER Action
    The action to perform: install, remove, verify, info, backup, restore, update, status
.PARAMETER Module
    Specific module to target (optional, defaults to all modules)
.PARAMETER Force
    Force operation even if already installed/configured
.PARAMETER UseWSL
    Force use of WSL even when native Windows is available
.PARAMETER NoWSL
    Disable WSL usage, use only native Windows
.PARAMETER UseContainers
    Prefer containerized implementations where available
.PARAMETER LogLevel
    Logging verbosity level
.PARAMETER DryRun
    Show what would be done without actually doing it
.EXAMPLE
    .\devenv.ps1 install
    Install all enabled modules
.EXAMPLE
    .\devenv.ps1 install python -Force
    Force reinstall the Python module
.EXAMPLE
    .\devenv.ps1 install -UseContainers -NoWSL
    Install using containers on native Windows only
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'backup', 'restore', 'update', 'status', 'list')]
    [string]$Action = 'info',
    
    [Parameter(Position = 1)]
    [string]$Module,
    
    [Parameter()]
    [string]$ConfigFile,
    
    [Parameter()]
    [string]$RootDir,
    
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
        $logFile = Join-Path $env:DEVENV_LOGS_DIR "devenv_$(Get-Date -Format 'yyyyMMdd').log" -ErrorAction SilentlyContinue
        if ($logFile -and (Test-Path (Split-Path $logFile -Parent) -ErrorAction SilentlyContinue)) {
            Add-Content -Path $logFile -Value $output -ErrorAction SilentlyContinue
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
        # Check if WSL is installed
        $wslVersion = wsl.exe --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            # Check for installed distributions
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

function Test-ContainerSupport {
    # Check for Windows containers or Docker Desktop
    try {
        # Check Docker
        if (Test-DockerAvailable) {
            return $true
        }
        
        # Check Windows containers
        $containerFeature = Get-WindowsOptionalFeature -Online -FeatureName Containers -ErrorAction SilentlyContinue
        if ($containerFeature -and $containerFeature.State -eq 'Enabled') {
            return $true
        }
        
        return $false
    }
    catch {
        return $false
    }
}
#endregion

#region Configuration Functions
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
        [string]$RootDirectory
    )
    
    Write-DevEnvLog "Initializing DevEnv environment..." -Level Information
    
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
    
    # Set up environment variables
    $env:DEVENV_ROOT = $RootDirectory
    $env:DEVENV_DATA_DIR = Join-Path $RootDirectory "data"
    $env:DEVENV_CONFIG_DIR = Join-Path $RootDirectory "config"
    $env:DEVENV_MODULES_DIR = Join-Path $RootDirectory "modules"
    $env:DEVENV_STATE_DIR = Join-Path $env:DEVENV_DATA_DIR "state"
    $env:DEVENV_LOGS_DIR = Join-Path $env:DEVENV_DATA_DIR "logs"
    $env:DEVENV_BACKUPS_DIR = Join-Path $env:DEVENV_DATA_DIR "backups"
    
    # Platform-specific paths
    $env:DEVENV_PLATFORM = "windows"
    if ($UseWSL -and $script:WSLAvailable) {
        $env:DEVENV_EXECUTION_MODE = "wsl"
    } elseif ($NoWSL -or -not $script:WSLAvailable) {
        $env:DEVENV_EXECUTION_MODE = "native"
    } else {
        $env:DEVENV_EXECUTION_MODE = "hybrid"
    }
    
    # Container preference
    if ($UseContainers -and (Test-ContainerSupport)) {
        $env:DEVENV_PREFER_CONTAINERS = "true"
    } else {
        $env:DEVENV_PREFER_CONTAINERS = "false"
    }
    
    # Create required directories
    $directories = @(
        $env:DEVENV_DATA_DIR,
        $env:DEVENV_STATE_DIR,
        $env:DEVENV_LOGS_DIR,
        $env:DEVENV_BACKUPS_DIR,
        (Join-Path $env:DEVENV_DATA_DIR "containers"),
        (Join-Path $env:DEVENV_DATA_DIR "cache")
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
}

function Get-ConfigurationFile {
    param([string]$RootDirectory)
    
    $configFile = Join-Path $RootDirectory "config.json"
    $templateFile = Join-Path $RootDirectory "config.template.json"
    
    # Create config from template if it doesn't exist
    if (-not (Test-Path $configFile) -and (Test-Path $templateFile)) {
        Write-DevEnvLog "Creating config.json from template..." -Level Information
        if (-not $script:DryRun) {
            Copy-Item $templateFile $configFile
        }
    }
    
    if (-not (Test-Path $configFile)) {
        throw "Configuration file not found: $configFile. Please create one based on config.template.json"
    }
    
    return $configFile
}

function Import-Configuration {
    param([string]$ConfigPath)
    
    Write-DevEnvLog "Loading configuration from: $ConfigPath" -Level Verbose
    
    try {
        $configContent = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        # Validate required sections
        $requiredSections = @('global', 'platforms')
        foreach ($section in $requiredSections) {
            if (-not $configContent.PSObject.Properties[$section]) {
                throw "Missing required configuration section: $section"
            }
        }
        
        return $configContent
    }
    catch {
        Write-DevEnvLog "Failed to load configuration: $_" -Level Error
        throw
    }
}
#endregion

#region Module Management Functions
function Get-EnabledModules {
    param([object]$Config)
    
    $moduleOrder = $Config.global.modules.order
    $enabledModules = @()
    
    foreach ($moduleName in $moduleOrder) {
        $moduleConfigPath = Join-Path $env:DEVENV_MODULES_DIR "$moduleName\config.json"
        
        if (Test-Path $moduleConfigPath) {
            try {
                $moduleConfig = Get-Content $moduleConfigPath -Raw | ConvertFrom-Json
                
                # Check global enabled status
                $globalEnabled = $moduleConfig.enabled -eq $true
                
                # Check platform-specific enabled status
                $platformEnabled = $true
                if ($moduleConfig.platforms.windows) {
                    $platformEnabled = $moduleConfig.platforms.windows.enabled -ne $false
                }
                
                if ($globalEnabled -and $platformEnabled) {
                    $enabledModules += $moduleName
                }
            }
            catch {
                Write-DevEnvLog "Failed to parse module config for ${moduleName}: $_" -Level Warning
            }
        } else {
            Write-DevEnvLog "Module config not found: $moduleConfigPath" -Level Warning
        }
    }
    
    return $enabledModules
}

function Invoke-ModuleAction {
    param(
        [string]$ModuleName,
        [string]$Action,
        [switch]$Force
    )
    
    Write-DevEnvLog "Executing $Action for module: $ModuleName" -Level Information -Module $ModuleName
    
    # Determine execution strategy
    $executionMode = Get-ModuleExecutionMode -ModuleName $ModuleName
    
    switch ($executionMode) {
        'native' {
            Invoke-NativeModule -ModuleName $ModuleName -Action $Action -Force:$Force
        }
        'wsl' {
            Invoke-WSLModule -ModuleName $ModuleName -Action $Action -Force:$Force
        }
        'container' {
            Invoke-ContainerModule -ModuleName $ModuleName -Action $Action -Force:$Force
        }
        default {
            throw "Unknown execution mode: $executionMode"
        }
    }
}

function Get-ModuleExecutionMode {
    param([string]$ModuleName)
    
    # Priority: Container > WSL > Native Windows
    if ($env:DEVENV_PREFER_CONTAINERS -eq "true" -and (Test-ModuleContainerSupport -ModuleName $ModuleName)) {
        return 'container'
    }
    
    if ($env:DEVENV_EXECUTION_MODE -in @('wsl', 'hybrid') -and (Test-ModuleWSLSupport -ModuleName $ModuleName)) {
        return 'wsl'
    }
    
    return 'native'
}

function Test-ModuleContainerSupport {
    param([string]$ModuleName)
    
    # Check if module supports containerization
    if (-not $script:Config.global.container.enabled) {
        return $false
    }
    
    $moduleContainer = $script:Config.global.container.modules.$ModuleName
    return $moduleContainer -and $moduleContainer.containerize -eq $true
}

function Test-ModuleWSLSupport {
    param([string]$ModuleName)
    
    # Some modules work better in WSL (like shell environments)
    $wslPreferred = @('zsh', 'git', 'python', 'nodejs')
    return $ModuleName -in $wslPreferred
}

function Invoke-NativeModule {
    param(
        [string]$ModuleName,
        [string]$Action,
        [switch]$Force
    )
    
    $moduleScript = Join-Path $env:DEVENV_MODULES_DIR "$ModuleName\$ModuleName.ps1"
    
    if (Test-Path $moduleScript) {
        Write-DevEnvLog "Running native PowerShell module: $moduleScript" -Level Verbose -Module $ModuleName
        
        if (-not $script:DryRun) {
            $params = @{
                Action = $Action
                Force = $Force.IsPresent
            }
            
            & $moduleScript @params
        } else {
            Write-DevEnvLog "DRY RUN: Would execute $moduleScript $Action" -Level Information -Module $ModuleName
        }
    } else {
        Write-DevEnvLog "Native module script not found: $moduleScript" -Level Error -Module $ModuleName
        throw "Module script not found"
    }
}

function Invoke-WSLModule {
    param(
        [string]$ModuleName,
        [string]$Action,
        [switch]$Force
    )
    
    if (-not $script:WSLAvailable) {
        Write-DevEnvLog "WSL not available, falling back to native execution" -Level Warning -Module $ModuleName
        Invoke-NativeModule -ModuleName $ModuleName -Action $Action -Force:$Force
        return
    }
    
    # Get WSL distribution from config
    $distribution = $script:Config.platforms.windows.wsl.distribution
    if (-not $distribution) {
        $distribution = "Ubuntu"
    }
    
    # Convert Windows paths to WSL paths
    $wslRootDir = wsl.exe wslpath "$env:DEVENV_ROOT"
    $moduleScript = "$wslRootDir/modules/$ModuleName/$ModuleName.sh"
    
    Write-DevEnvLog "Running WSL module: $moduleScript" -Level Verbose -Module $ModuleName
    
    if (-not $script:DryRun) {
        $forceFlag = if ($Force) { "--force" } else { "" }
        $wslCommand = "cd '$wslRootDir' && bash '$moduleScript' '$Action' $forceFlag"
        
        wsl.exe -d $distribution bash -c $wslCommand
        
        if ($LASTEXITCODE -ne 0) {
            throw "WSL module execution failed with exit code: $LASTEXITCODE"
        }
    } else {
        Write-DevEnvLog "DRY RUN: Would execute WSL command for $ModuleName $Action" -Level Information -Module $ModuleName
    }
}

function Invoke-ContainerModule {
    param(
        [string]$ModuleName,
        [string]$Action,
        [switch]$Force
    )
    
    if (-not (Test-ContainerSupport)) {
        Write-DevEnvLog "Container support not available, falling back to native execution" -Level Warning -Module $ModuleName
        Invoke-NativeModule -ModuleName $ModuleName -Action $Action -Force:$Force
        return
    }
    
    Write-DevEnvLog "Running containerized module: $ModuleName" -Level Verbose -Module $ModuleName
    
    # This would integrate with your existing container management
    if (-not $script:DryRun) {
        # Implementation would call your devenv-container equivalent
        # For now, fall back to native
        Invoke-NativeModule -ModuleName $ModuleName -Action $Action -Force:$Force
    } else {
        Write-DevEnvLog "DRY RUN: Would execute containerized $ModuleName $Action" -Level Information -Module $ModuleName
    }
}
#endregion

#region Main Functions
function Show-Help {
    @"
DevEnv - Development Environment Manager for Windows

USAGE:
    devenv.ps1 [ACTION] [MODULE] [OPTIONS]

ACTIONS:
    install     Install modules (default: all enabled modules)
    remove      Remove/uninstall modules
    verify      Verify module installation and configuration
    info        Show module information and status
    backup      Create backup of current configuration
    restore     Restore from backup
    update      Update modules to latest versions
    status      Show overall system status
    list        List all available modules

OPTIONS:
    -Module <name>      Target specific module
    -Force              Force operation even if already configured
    -UseWSL             Prefer WSL execution when available
    -NoWSL              Use only native Windows execution
    -UseContainers      Prefer containerized execution
    -LogLevel <level>   Set logging verbosity (Silent|Error|Warning|Information|Verbose|Debug)
    -DryRun             Show what would be done without executing
    -ShowHelp           Show this help message

EXAMPLES:
    devenv.ps1                          # Show info for all modules
    devenv.ps1 install                  # Install all enabled modules
    devenv.ps1 install python -Force    # Force reinstall Python module
    devenv.ps1 verify git              # Verify Git module installation
    devenv.ps1 status                  # Show system status
    devenv.ps1 install -UseContainers  # Install with container preference

EXECUTION MODES:
    Native:     Pure Windows PowerShell execution
    WSL:        Use Windows Subsystem for Linux
    Container:  Use Docker containers (recommended)
    
The system automatically chooses the best execution mode based on:
1. User preferences (-UseWSL, -NoWSL, -UseContainers)
2. Module capabilities and requirements
3. System availability (WSL installed, Docker available, etc.)

For more information, visit: https://github.com/your-repo/devenv
"@
}

function Show-SystemStatus {
    Write-Host "`nDevEnv System Status" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    
    Write-Host "`nSystem Information:" -ForegroundColor Yellow
    Write-Host "  Platform: Windows $($script:WindowsVersion.Major).$($script:WindowsVersion.Minor) (Build $($script:WindowsVersion.Build))"
    Write-Host "  Administrator: $(if($script:IsElevated){'Yes'}else{'No'})"
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)"
    
    Write-Host "`nExecution Capabilities:" -ForegroundColor Yellow
    Write-Host "  WSL Available: $(if($script:WSLAvailable){'Yes'}else{'No'})"
    Write-Host "  Docker Available: $(if($script:DockerAvailable){'Yes'}else{'No'})"
    Write-Host "  Container Support: $(if(Test-ContainerSupport){'Yes'}else{'No'})"
    
    Write-Host "`nCurrent Configuration:" -ForegroundColor Yellow
    Write-Host "  Execution Mode: $env:DEVENV_EXECUTION_MODE"
    Write-Host "  Prefer Containers: $env:DEVENV_PREFER_CONTAINERS"
    Write-Host "  Root Directory: $env:DEVENV_ROOT"
    Write-Host "  Data Directory: $env:DEVENV_DATA_DIR"
    
    # Show enabled modules
    $enabledModules = Get-EnabledModules -Config $script:Config
    Write-Host "`nEnabled Modules ($($enabledModules.Count)):" -ForegroundColor Yellow
    foreach ($module in $enabledModules) {
        $executionMode = Get-ModuleExecutionMode -ModuleName $module
        Write-Host "  $module ($executionMode)"
    }
}

function Invoke-DevEnvAction {
    param(
        [string]$Action,
        [string]$TargetModule
    )
    
    $enabledModules = Get-EnabledModules -Config $script:Config
    
    if ($TargetModule) {
        if ($TargetModule -notin $enabledModules) {
            Write-DevEnvLog "Module '$TargetModule' is not enabled or does not exist" -Level Warning
            return
        }
        $modulesToProcess = @($TargetModule)
    } else {
        $modulesToProcess = $enabledModules
    }
    
    if ($modulesToProcess.Count -eq 0) {
        Write-DevEnvLog "No modules to process" -Level Warning
        return
    }
    
    Write-DevEnvLog "Processing $($modulesToProcess.Count) module(s) for action: $Action" -Level Information
    
    $totalModules = $modulesToProcess.Count
    $currentModule = 0
    
    foreach ($moduleName in $modulesToProcess) {
        $currentModule++
        $percentComplete = [int](($currentModule / $totalModules) * 100)
        
        Write-Progress-Step -Activity "DevEnv $Action" -Status "Processing $moduleName ($currentModule of $totalModules)" -PercentComplete $percentComplete
        
        try {
            Invoke-ModuleAction -ModuleName $moduleName -Action $Action -Force:$Force
            Write-DevEnvLog "Successfully completed $Action for $moduleName" -Level Information -Module $moduleName
        }
        catch {
            Write-DevEnvLog "Failed to $Action module ${moduleName}: $_" -Level Error -Module $moduleName
            
            # Continue with other modules unless this is a critical failure
            if ($Action -eq 'install' -and $moduleName -in @('powershell', 'git')) {
                Write-DevEnvLog "Critical module failed, stopping execution" -Level Error
                throw
            }
        }
    }
    
    Write-Progress -Activity "DevEnv $Action" -Completed
    Write-DevEnvLog "Completed $Action for all modules" -Level Information
}
#endregion

#region Main Execution
try {
    # Show help if requested
    if ($ShowHelp) {
        Show-Help
        exit 0
    }
    
    # Determine root directory
    if (-not $RootDir) {
        $RootDir = Get-ScriptDirectory
    }
    
    # Initialize environment
    Initialize-Environment -RootDirectory $RootDir
    
    # Load configuration
    if (-not $ConfigFile) {
        $ConfigFile = Get-ConfigurationFile -RootDirectory $RootDir
    }
    
    $script:Config = Import-Configuration -ConfigPath $ConfigFile
    
    # Execute action
    switch ($Action.ToLower()) {
        'status' {
            Show-SystemStatus
        }
        'list' {
            $enabledModules = Get-EnabledModules -Config $script:Config
            Write-Host "`nAvailable Modules:" -ForegroundColor Cyan
            foreach ($module in $enabledModules) {
                $mode = Get-ModuleExecutionMode -ModuleName $module
                Write-Host "  $module ($mode)" -ForegroundColor Green
            }
        }
        'info' {
            if ($Module) {
                Invoke-DevEnvAction -Action 'info' -TargetModule $Module
            } else {
                Show-SystemStatus
                Write-Host ""
                Invoke-DevEnvAction -Action 'info'
            }
        }
        default {
            Invoke-DevEnvAction -Action $Action -TargetModule $Module
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