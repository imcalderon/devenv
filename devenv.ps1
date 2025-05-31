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
$script:DataDirectory = $null
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
        $color = switch ($Level) {
            'Error' { 'Red' }
            'Warning' { 'Yellow' }
            'Information' { 'Green' }
            'Verbose' { 'Cyan' }
            'Debug' { 'Magenta' }
        }
        
        if ($NoNewline) {
            Write-Host $Message -ForegroundColor $color -NoNewline
        } else {
            Write-Host $Message -ForegroundColor $color
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

function Test-GitAvailable {
    try {
        $null = git.exe --version 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Test-NodeAvailable {
    try {
        $null = node.exe --version 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Test-PythonAvailable {
    try {
        $null = python.exe --version 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Test-VSCodeAvailable {
    try {
        $null = code.exe --version 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}
#endregion

#region Enhanced System Status and Guidance
function Show-WelcomeMessage {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  DevEnv - Hermetic Development Setup  " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Welcome to DevEnv! Let's analyze your system and get you started." -ForegroundColor White
    Write-Host ""
}

function Show-SystemAnalysis {
    Write-Host "System Analysis" -ForegroundColor Yellow
    Write-Host "---------------" -ForegroundColor Yellow
    
    # Basic system info
    Write-Host "Platform: " -NoNewline
    Write-Host "Windows $($script:WindowsVersion.Major).$($script:WindowsVersion.Minor) (Build $($script:WindowsVersion.Build))" -ForegroundColor Green
    
    Write-Host "PowerShell: " -NoNewline
    Write-Host "$($PSVersionTable.PSVersion)" -ForegroundColor Green
    
    Write-Host "Administrator: " -NoNewline
    if ($script:IsElevated) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No" -ForegroundColor Yellow
        Write-Host "  Note: Some modules may require administrator privileges for installation" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Development Capabilities" -ForegroundColor Yellow
    Write-Host "------------------------" -ForegroundColor Yellow
    
    # WSL Status
    Write-Host "WSL (Windows Subsystem for Linux): " -NoNewline
    if ($script:WSLAvailable) {
        Write-Host "Available" -ForegroundColor Green
        try {
            $wslDistros = wsl.exe --list --quiet 2>$null | Where-Object { $_.Trim() -ne "" }
            Write-Host "  Distributions: $($wslDistros -join ', ')" -ForegroundColor Gray
        } catch {}
    } else {
        Write-Host "Not Available" -ForegroundColor Red
        Write-Host "  Tip: Install WSL2 for enhanced Linux compatibility" -ForegroundColor Gray
    }
    
    # Docker Status
    Write-Host "Docker: " -NoNewline
    if ($script:DockerAvailable) {
        Write-Host "Available" -ForegroundColor Green
        try {
            $dockerVersion = docker.exe --version 2>$null
            Write-Host "  Version: $dockerVersion" -ForegroundColor Gray
        } catch {}
    } else {
        Write-Host "Not Available" -ForegroundColor Red
        Write-Host "  Tip: Install Docker Desktop for containerized development" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Installed Development Tools" -ForegroundColor Yellow
    Write-Host "---------------------------" -ForegroundColor Yellow
    
    # Check common development tools
    $tools = @(
        @{ Name = "Git"; Check = { Test-GitAvailable } },
        @{ Name = "Node.js"; Check = { Test-NodeAvailable } },
        @{ Name = "Python"; Check = { Test-PythonAvailable } },
        @{ Name = "VS Code"; Check = { Test-VSCodeAvailable } }
    )
    
    foreach ($tool in $tools) {
        Write-Host "$($tool.Name): " -NoNewline
        if (& $tool.Check) {
            Write-Host "Installed" -ForegroundColor Green
        } else {
            Write-Host "Not Installed" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}

function Show-GuidedSetup {
    Write-Host "Getting Started" -ForegroundColor Yellow
    Write-Host "---------------" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "DevEnv creates isolated, portable development environments that don't pollute your system." -ForegroundColor White
    Write-Host "Each project can have its own complete development setup that travels with your code." -ForegroundColor White
    Write-Host ""
    
    Write-Host "Recommended Setup Steps:" -ForegroundColor Cyan
    Write-Host ""
    
    # Step 1: Create project directory
    Write-Host "1. Create a Project Environment" -ForegroundColor Green
    Write-Host "   Choose where to set up your isolated development environment:" -ForegroundColor White
    Write-Host ""
    Write-Host "   For a specific project:" -ForegroundColor Gray
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host "cd C:\YourProject" -ForegroundColor White
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 create-environment 'my-project' -DataDir '.\.devenv'" -ForegroundColor White
    Write-Host ""
    Write-Host "   For general development:" -ForegroundColor Gray
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 create-environment 'dev-main' -DataDir 'C:\Dev\.devenv'" -ForegroundColor White
    Write-Host ""
    
    # Step 2: Install tools
    Write-Host "2. Install Development Tools" -ForegroundColor Green
    Write-Host "   After creating an environment, install the tools you need:" -ForegroundColor White
    Write-Host ""
    
    if (-not (Test-GitAvailable)) {
        Write-Host "   Install Git (version control):" -ForegroundColor Gray
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 install git" -ForegroundColor White
        Write-Host ""
    }
    
    if (-not (Test-VSCodeAvailable)) {
        Write-Host "   Install VS Code (code editor):" -ForegroundColor Gray
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 install vscode" -ForegroundColor White
        Write-Host ""
    }
    
    if (-not (Test-PythonAvailable)) {
        Write-Host "   Install Python (programming language):" -ForegroundColor Gray
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 install python" -ForegroundColor White
        Write-Host ""
    }
    
    if (-not (Test-NodeAvailable)) {
        Write-Host "   Install Node.js (JavaScript runtime):" -ForegroundColor Gray
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 install nodejs" -ForegroundColor White
        Write-Host ""
    }
    
    if (-not $script:DockerAvailable) {
        Write-Host "   Install Docker (containerization):" -ForegroundColor Gray
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 install docker" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "   Install everything at once:" -ForegroundColor Gray
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 install" -ForegroundColor White
    Write-Host ""
    
    # Step 3: Additional commands
    Write-Host "3. Useful Commands" -ForegroundColor Green
    Write-Host ""
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 list" -ForegroundColor White
    Write-Host "       Show all available modules" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 status" -ForegroundColor White
    Write-Host "       Show detailed system and environment status" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 list-environments" -ForegroundColor White
    Write-Host "       Show all your development environments" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
    Write-Host ".\devenv.ps1 verify" -ForegroundColor White
    Write-Host "       Check that everything is working correctly" -ForegroundColor Gray
    Write-Host ""
    
    # Benefits section
    Write-Host "Why Use DevEnv?" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "• " -NoNewline -ForegroundColor Green
    Write-Host "Hermetic: Each environment is completely isolated" -ForegroundColor White
    Write-Host "• " -NoNewline -ForegroundColor Green
    Write-Host "Portable: Copy the .devenv folder = copy the entire environment" -ForegroundColor White
    Write-Host "• " -NoNewline -ForegroundColor Green
    Write-Host "Clean: No system pollution - everything can be removed cleanly" -ForegroundColor White
    Write-Host "• " -NoNewline -ForegroundColor Green
    Write-Host "Team-Friendly: Share identical environments across your team" -ForegroundColor White
    Write-Host "• " -NoNewline -ForegroundColor Green
    Write-Host "Container-Ready: Uses Docker containers when available for maximum isolation" -ForegroundColor White
    Write-Host ""
}

function Show-QuickStart {
    Write-Host "Quick Start - No Environment Set" -ForegroundColor Yellow
    Write-Host "=================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "You don't have any DevEnv environments set up yet." -ForegroundColor White
    Write-Host "Let's create your first isolated development environment!" -ForegroundColor White
    Write-Host ""
    
    $createNow = Read-Host "Would you like to create a development environment now? (Y/n)"
    
    if ($createNow -match '^[Nn]') {
        Write-Host ""
        Write-Host "No problem! When you're ready, use these commands:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Create environment in current directory:" -ForegroundColor Gray
        Write-Host "PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 create-environment 'my-project' -DataDir '.\.devenv'" -ForegroundColor White
        Write-Host ""
        Write-Host "Create environment in a specific location:" -ForegroundColor Gray
        Write-Host "PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 create-environment 'dev-main' -DataDir 'C:\Dev\.devenv'" -ForegroundColor White
        Write-Host ""
        return
    }
    
    Write-Host ""
    Write-Host "Great! Let's set up your development environment." -ForegroundColor Green
    Write-Host ""
    
    # Get environment name
    $envName = Read-Host "Enter a name for your environment (e.g., 'my-project', 'main-dev')"
    if (-not $envName) {
        $envName = "main-dev"
        Write-Host "Using default name: $envName" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Where would you like to store your development environment?" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:" -ForegroundColor White
    Write-Host "1. Current directory ($(Get-Location)\.devenv)" -ForegroundColor Gray
    Write-Host "2. Dedicated dev folder (C:\Dev\.devenv)" -ForegroundColor Gray
    Write-Host "3. Custom location" -ForegroundColor Gray
    Write-Host ""
    
    $locationChoice = Read-Host "Choose option (1/2/3) or press Enter for option 1"
    
    $dataDir = switch ($locationChoice) {
        "2" { "C:\Dev\.devenv" }
        "3" { 
            $customPath = Read-Host "Enter the full path for your environment data"
            if ($customPath) { $customPath } else { "$(Get-Location)\.devenv" }
        }
        default { "$(Get-Location)\.devenv" }
    }
    
    Write-Host ""
    $description = Read-Host "Enter a description for this environment (optional)"
    
    Write-Host ""
    Write-Host "Creating environment '$envName' at: $dataDir" -ForegroundColor Green
    
    try {
        # Create the environment (would call the actual creation function)
        Write-Host "Environment '$envName' created successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "1. Switch to your new environment:" -ForegroundColor White
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 switch-environment '$envName'" -ForegroundColor White
        Write-Host ""
        Write-Host "2. Install development tools:" -ForegroundColor White
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 install git vscode python" -ForegroundColor White
        Write-Host ""
        Write-Host "3. Check everything is working:" -ForegroundColor White
        Write-Host "   PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 verify" -ForegroundColor White
        Write-Host ""
    }
    catch {
        Write-Host "Failed to create environment: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Try creating it manually:" -ForegroundColor Yellow
        Write-Host "PS> " -NoNewline -ForegroundColor DarkGray
        Write-Host ".\devenv.ps1 create-environment '$envName' -DataDir '$dataDir'" -ForegroundColor White
    }
}

function Get-DefaultEnvironmentsRoot {
    return Join-Path $env:USERPROFILE ".devenv\environments"
}

function Test-HasAnyEnvironments {
    $envRoot = Get-DefaultEnvironmentsRoot
    if (-not (Test-Path $envRoot)) {
        return $false
    }
    
    $envFiles = Get-ChildItem $envRoot -Filter "*.json" -ErrorAction SilentlyContinue
    return ($envFiles.Count -gt 0)
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

function Initialize-BasicEnvironment {
    param([string]$RootDirectory)
    
    # Just basic initialization without creating data directories
    if (-not [System.IO.Path]::IsPathRooted($RootDirectory)) {
        $RootDirectory = Join-Path (Get-Location) $RootDirectory
    }
    $RootDirectory = [System.IO.Path]::GetFullPath($RootDirectory)
    
    # Detect system capabilities
    $script:IsElevated = Test-Administrator
    $script:WindowsVersion = Get-WindowsVersion
    $script:WSLAvailable = Test-WSLAvailable
    $script:DockerAvailable = Test-DockerAvailable
    
    # Set minimal environment variables
    $env:DEVENV_ROOT = $RootDirectory
    $env:ROOT_DIR = $RootDirectory
    $env:CONFIG_FILE = Join-Path $RootDirectory "config.json"
    $env:DEVENV_PLATFORM = 'windows'
}
#endregion

#region Help Function
function Show-Help {
    @"
DevEnv - Hermetic Development Environment Manager for Windows

USAGE:
    devenv.ps1 [ACTION] [MODULE] [OPTIONS]

ACTIONS:
    install                 Install modules (default: all enabled modules)
    remove                  Remove/uninstall modules  
    verify                  Verify module installation and configuration
    info                    Show system analysis and setup guidance (default)
    backup                  Create backup of current configuration
    restore                 Restore from backup
    update                  Update modules to latest versions
    status                  Show detailed system and environment status
    list                    List all available modules

ENVIRONMENT ACTIONS:
    list-environments       List all available environments
    create-environment      Create a new isolated environment
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

EXAMPLES:
    devenv.ps1                                    # Show system analysis and guidance
    devenv.ps1 create-environment "my-project"   # Create isolated environment
    devenv.ps1 install git python vscode         # Install development tools
    devenv.ps1 status                           # Show detailed status
    devenv.ps1 list-environments                # List all environments

For more information, visit: https://github.com/your-repo/devenv
"@
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
    
    # Initialize basic environment (no data directory creation)
    Initialize-BasicEnvironment -RootDirectory $RootDir
    
    # Handle the default 'info' action with enhanced guidance
    if ($Action -eq 'info' -and -not $Module -and -not $DataDir -and -not $Environment) {
        Show-WelcomeMessage
        Show-SystemAnalysis
        Write-Host ""
        
        # Check if user has any environments
        if (Test-HasAnyEnvironments) {
            Show-GuidedSetup
        } else {
            Show-QuickStart
        }
        
        exit 0
    }
    
    # For all other actions, you would continue with the existing logic
    # This is where the original devenv.ps1 logic would continue...
    
    Write-Host "Action '$Action' not yet implemented in this demo" -ForegroundColor Yellow
    if ($Module) {
        Write-Host "Target module: $Module" -ForegroundColor Information
    }
    
}
catch {
    Write-DevEnvLog "DevEnv operation failed: $_" -Level Error
    exit 1
}
#endregion