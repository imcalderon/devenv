#Requires -Version 5.1
<#
.SYNOPSIS
    DevEnv - Dual-Mode Hermetic Development Environment Manager
.DESCRIPTION
    Enhanced version with mode detection and dual-mode operation support
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

#region Core Mode Detection
function Get-ExecutionMode {
    <#
    .SYNOPSIS
        Detects whether DevEnv is running in Global or Project mode
    .DESCRIPTION
        Uses path analysis and file existence to determine execution context
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )
    
    $scriptDir = Split-Path $ScriptPath -Parent
    $scriptName = Split-Path $ScriptPath -Leaf
    
    Write-Verbose "Script path: $ScriptPath"
    Write-Verbose "Script directory: $scriptDir"
    
    # Case 1: Project Mode Detection
    # Check if we're in a project's bin directory with a symlink/copy
    if ($scriptDir -match '\\bin$' -or $scriptDir -match '/bin$') {
        $projectRoot = Split-Path $scriptDir -Parent
        $projectConfigFile = Join-Path $projectRoot "devenv.json"
        
        Write-Verbose "Checking for project mode..."
        Write-Verbose "Potential project root: $projectRoot"
        Write-Verbose "Looking for config: $projectConfigFile"
        
        if (Test-Path $projectConfigFile) {
            # Determine if this is a symlink or copy
            $isSymlink = $false
            $globalDevEnvPath = $null
            
            try {
                $item = Get-Item $ScriptPath -ErrorAction SilentlyContinue
                if ($item.LinkType -eq 'SymbolicLink') {
                    $isSymlink = $true
                    $globalDevEnvPath = $item.Target
                }
            } catch {
                $isSymlink = $false
            }
            
            return @{
                Mode = "Project"
                ProjectRoot = $projectRoot
                DataDir = Join-Path $projectRoot ".devenv"
                ConfigFile = $projectConfigFile
                ScriptPath = $ScriptPath
                IsSymlink = $isSymlink
                GlobalDevEnvPath = $globalDevEnvPath
            }
        }
    }
    
    # Case 2: Global Mode Detection
    # Check if we're in the DevEnv repository root
    $globalConfigFile = Join-Path $scriptDir "config.json"
    
    Write-Verbose "Checking for global mode..."
    Write-Verbose "Looking for global config: $globalConfigFile"
    
    if (Test-Path $globalConfigFile) {
        return @{
            Mode = "Global"
            ProjectRoot = $null
            DataDir = Join-Path $env:USERPROFILE ".devenv"
            ConfigFile = $globalConfigFile
            ScriptPath = $ScriptPath
            IsSymlink = $false
            GlobalDevEnvPath = $ScriptPath
        }
    }
    
    # Case 3: Error - Cannot determine mode
    throw @"
Cannot determine DevEnv execution mode.

Expected one of:
1. Global Mode: Running from DevEnv repository with config.json present
2. Project Mode: Running from project/bin/ directory with ../devenv.json present

Current location: $scriptDir
Script: $ScriptPath

Please ensure you're running DevEnv from the correct location.
"@
}

function Initialize-ExecutionEnvironment {
    <#
    .SYNOPSIS
        Sets up environment variables and directories for the detected mode
    #>
    param([hashtable]$DevEnvContext)
    
    # Set core environment variables
    $env:DEVENV_MODE = $DevEnvContext.Mode
    $env:DEVENV_DATA_DIR = $DevEnvContext.DataDir
    $env:DEVENV_CONFIG_FILE = $DevEnvContext.ConfigFile
    $env:DEVENV_ROOT = if ($DevEnvContext.Mode -eq "Global") { 
        Split-Path $DevEnvContext.ScriptPath -Parent 
    } else { 
        if ($DevEnvContext.GlobalDevEnvPath) {
            Split-Path $DevEnvContext.GlobalDevEnvPath -Parent 
        } else {
            # Fallback: assume DevEnv is in PATH or use current directory
            Split-Path $DevEnvContext.ScriptPath -Parent
        }
    }
    
    # Mode-specific setup
    if ($DevEnvContext.Mode -eq "Project") {
        $env:DEVENV_PROJECT_ROOT = $DevEnvContext.ProjectRoot
        $env:DEVENV_PROJECT_MODE = "true"
        
        Write-Host "[PROJ] " -NoNewline -ForegroundColor Blue
        Write-Host "DevEnv Project Mode" -ForegroundColor Cyan
        Write-Host "   Project: " -NoNewline -ForegroundColor Gray
        Write-Host (Split-Path $DevEnvContext.ProjectRoot -Leaf) -ForegroundColor White
        Write-Host "   Data Dir: " -NoNewline -ForegroundColor Gray
        Write-Host $DevEnvContext.DataDir -ForegroundColor Yellow
        
        if ($DevEnvContext.IsSymlink) {
            Write-Host "   Symlink: " -NoNewline -ForegroundColor Gray
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "   Type: " -NoNewline -ForegroundColor Gray
            Write-Host "Copy" -ForegroundColor Yellow
        }
    } else {
        $env:DEVENV_PROJECT_MODE = "false"
        
        Write-Host "[GLOBAL] " -NoNewline -ForegroundColor Blue
        Write-Host "DevEnv Global Mode" -ForegroundColor Green
        Write-Host "   Data Dir: " -NoNewline -ForegroundColor Gray
        Write-Host $DevEnvContext.DataDir -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    # Create required data directories
    $requiredDirs = @(
        $DevEnvContext.DataDir,
        (Join-Path $DevEnvContext.DataDir "state"),
        (Join-Path $DevEnvContext.DataDir "tools"),
        (Join-Path $DevEnvContext.DataDir "config"),
        (Join-Path $DevEnvContext.DataDir "logs"),
        (Join-Path $DevEnvContext.DataDir "backups")
    )
    
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $dir"
        }
    }
    
    # Load configuration
    if (Test-Path $DevEnvContext.ConfigFile) {
        try {
            $script:Config = Get-Content $DevEnvContext.ConfigFile | ConvertFrom-Json
            Write-Verbose "Loaded configuration from: $($DevEnvContext.ConfigFile)"
        } catch {
            Write-Warning "Failed to load configuration from $($DevEnvContext.ConfigFile): $_"
            $script:Config = @{}
        }
    } else {
        Write-Warning "Configuration file not found: $($DevEnvContext.ConfigFile)"
        $script:Config = @{}
    }
    
    return $DevEnvContext
}
#endregion

#region Project Creation
function New-DevEnvProject {
    <#
    .SYNOPSIS
        Creates a new project with DevEnv integration
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,
        
        [string]$ProjectPath = (Get-Location),
        
        [string]$Template = "basic",
        
        [string]$Description = ""
    )
    
    if ($script:DevEnvContext.Mode -eq "Project") {
        throw "Cannot create project from within project mode. Use global DevEnv instance."
    }
    
    $projectDir = Join-Path $ProjectPath $ProjectName
    
    if (Test-Path $projectDir) {
        if (-not $Force) {
            throw "Project directory already exists: $projectDir. Use -Force to overwrite."
        }
        Write-Warning "Project directory exists, removing: $projectDir"
        Remove-Item $projectDir -Recurse -Force
    }
    
    Write-Host "Creating project: " -NoNewline
    Write-Host $ProjectName -ForegroundColor Cyan
    Write-Host "Location: " -NoNewline
    Write-Host $projectDir -ForegroundColor Yellow
    Write-Host ""
    
    # Create project structure
    $projectStructure = @(
        "src",
        "bin",
        "docs",
        "tests",
        ".devenv"
    )
    
    foreach ($dir in $projectStructure) {
        $fullPath = Join-Path $projectDir $dir
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
    }
    
    # Create project configuration
    $projectConfig = @{
        name = $ProjectName
        version = "1.0.0"
        description = if ($Description) { $Description } else { "DevEnv project: $ProjectName" }
        template = $Template
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        devenv = @{
            version = "3.0.0"
            mode = "project"
            data_dir = ".devenv"
        }
        modules = @{
            order = @("git", "vscode")
        }
    }
    
    $configPath = Join-Path $projectDir "devenv.json"
    $projectConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
    
    # Create README
    $readmeContent = @"
# $ProjectName

$($projectConfig.description)

## DevEnv Setup

This project uses DevEnv for isolated development environment management.

### Quick Start

1. Install development environment:
   ``````powershell
   .\bin\devenv.ps1 install
   ``````

2. Check status:
   ``````powershell
   .\bin\devenv.ps1 status
   ``````

3. Verify everything works:
   ``````powershell
   .\bin\devenv.ps1 verify
   ``````

### Available Commands

- `.\bin\devenv.ps1 install [modules]` - Install development tools
- `.\bin\devenv.ps1 status` - Show environment status
- `.\bin\devenv.ps1 verify` - Verify installations
- `.\bin\devenv.ps1 info` - Show detailed information

### Data Directory

All development tools and configurations are stored in `.devenv/` directory.
This directory is gitignored and contains the complete isolated environment.

Created: $((Get-Date).ToString("yyyy-MM-dd"))
"@
    
    $readmePath = Join-Path $projectDir "README.md"
    Set-Content -Path $readmePath -Value $readmeContent -Encoding UTF8
    
    # Create .gitignore
    $gitignoreContent = @"
# DevEnv data directory - contains isolated development environment
.devenv/

# Common build outputs
bin/
obj/
build/
dist/

# IDE files
.vs/
.vscode/settings.json
*.user
*.suo

# OS files
Thumbs.db
.DS_Store
"@
    
    $gitignorePath = Join-Path $projectDir ".gitignore"
    Set-Content -Path $gitignorePath -Value $gitignoreContent -Encoding UTF8
    
    # Create DevEnv symlink or copy
    $globalDevEnvPath = $script:DevEnvContext.ScriptPath
    $projectDevEnvPath = Join-Path $projectDir "bin\devenv.ps1"
    
    try {
        # Try to create symbolic link (requires admin or developer mode)
        New-Item -ItemType SymbolicLink -Path $projectDevEnvPath -Target $globalDevEnvPath -Force | Out-Null
        Write-Host "+ Created symlink: " -NoNewline -ForegroundColor Green
        Write-Host "bin\devenv.ps1 -> $globalDevEnvPath" -ForegroundColor Gray
        $linkType = "symlink"
    } catch {
        # Fall back to copying the file
        Copy-Item -Path $globalDevEnvPath -Destination $projectDevEnvPath -Force
        Write-Host "! Created copy: " -NoNewline -ForegroundColor Yellow
        Write-Host "bin\devenv.ps1" -ForegroundColor Gray
        Write-Host "  (Symlink failed - requires admin or developer mode)" -ForegroundColor Gray
        $linkType = "copy"
    }
    
    Write-Host ""
    Write-Host "+ Project created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. cd $ProjectName" -ForegroundColor White
    Write-Host "2. .\bin\devenv.ps1 install    # Set up development environment" -ForegroundColor White
    Write-Host "3. .\bin\devenv.ps1 status     # Check environment status" -ForegroundColor White
    Write-Host ""
    
    return @{
        ProjectDir = $projectDir
        ConfigFile = $configPath
        LinkType = $linkType
        DevEnvPath = $projectDevEnvPath
    }
}
#endregion

#region Enhanced Status Display
function Show-ModeAwareStatus {
    <#
    .SYNOPSIS
        Shows status information appropriate for the current mode
    #>
    param([hashtable]$DevEnvContext)
    
    Write-Host ""
    Write-Host "DevEnv Status Report" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    Write-Host ""
    
    # Execution context
    Write-Host "Execution Context" -ForegroundColor Yellow
    Write-Host "-----------------" -ForegroundColor Yellow
    Write-Host "Mode: " -NoNewline
    
    if ($DevEnvContext.Mode -eq "Project") {
        Write-Host "Project-Specific" -ForegroundColor Magenta
        Write-Host "Project Name: " -NoNewline
        Write-Host (Split-Path $DevEnvContext.ProjectRoot -Leaf) -ForegroundColor White
        Write-Host "Project Root: " -NoNewline
        Write-Host $DevEnvContext.ProjectRoot -ForegroundColor Gray
        Write-Host "Project Config: " -NoNewline
        Write-Host $DevEnvContext.ConfigFile -ForegroundColor Gray
        
        if ($DevEnvContext.IsSymlink) {
            Write-Host "DevEnv Link: " -NoNewline
            Write-Host "Symlink OK" -ForegroundColor Green
            Write-Host "Global DevEnv: " -NoNewline
            Write-Host $DevEnvContext.GlobalDevEnvPath -ForegroundColor Gray
        } else {
            Write-Host "DevEnv Link: " -NoNewline
            Write-Host "Copy" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Global System-Wide" -ForegroundColor Green
        Write-Host "DevEnv Root: " -NoNewline
        Write-Host (Split-Path $DevEnvContext.ScriptPath -Parent) -ForegroundColor Gray
        Write-Host "Global Config: " -NoNewline
        Write-Host $DevEnvContext.ConfigFile -ForegroundColor Gray
    }
    
    Write-Host "Data Directory: " -NoNewline
    Write-Host $DevEnvContext.DataDir -ForegroundColor Yellow
    Write-Host ""
    
    # Configuration status
    Write-Host "Configuration" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow
    
    if (Test-Path $DevEnvContext.ConfigFile) {
        Write-Host "Config File: " -NoNewline
        Write-Host "Found OK" -ForegroundColor Green
        
        try {
            $config = Get-Content $DevEnvContext.ConfigFile | ConvertFrom-Json
            if ($config.modules -and $config.modules.order) {
                Write-Host "Configured Modules: " -NoNewline
                Write-Host ($config.modules.order -join ", ") -ForegroundColor Cyan
            }
        } catch {
            Write-Host "Config Parse: " -NoNewline
            Write-Host "Error" -ForegroundColor Red
        }
    } else {
        Write-Host "Config File: " -NoNewline
        Write-Host "Missing" -ForegroundColor Red
    }
    
    Write-Host ""
    
    # Data directory contents
    Write-Host "Environment Data" -ForegroundColor Yellow
    Write-Host "----------------" -ForegroundColor Yellow
    
    $dataDirs = @{
        "State" = Join-Path $DevEnvContext.DataDir "state"
        "Tools" = Join-Path $DevEnvContext.DataDir "tools" 
        "Config" = Join-Path $DevEnvContext.DataDir "config"
        "Logs" = Join-Path $DevEnvContext.DataDir "logs"
        "Backups" = Join-Path $DevEnvContext.DataDir "backups"
    }
    
    foreach ($dir in $dataDirs.GetEnumerator()) {
        Write-Host "$($dir.Key): " -NoNewline
        if (Test-Path $dir.Value) {
            $items = @(Get-ChildItem $dir.Value -ErrorAction SilentlyContinue)
            Write-Host "$($items.Count) items" -ForegroundColor Green
        } else {
            Write-Host "Not created" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    
    # Module status (simplified for now)
    Write-Host "Module Status" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow
    
    $stateDir = Join-Path $DevEnvContext.DataDir "state"
    if (Test-Path $stateDir) {
        $stateFiles = @(Get-ChildItem $stateDir -Filter "*.state" -ErrorAction SilentlyContinue)
        if ($stateFiles.Count -gt 0) {
            foreach ($stateFile in $stateFiles) {
                $moduleName = $stateFile.BaseName
                Write-Host "$moduleName`: " -NoNewline
                Write-Host "Installed" -ForegroundColor Green
            }
        } else {
            Write-Host "No modules installed" -ForegroundColor Gray
        }
    } else {
        Write-Host "No state directory" -ForegroundColor Gray
    }
    
    Write-Host ""
}

function Show-ModeAwareInfo {
    <#
    .SYNOPSIS
        Shows information and guidance appropriate for the current mode
    #>
    param([hashtable]$DevEnvContext)
    
    if ($DevEnvContext.Mode -eq "Project") {
        Write-Host ""
        Write-Host "[PROJ] Project Environment Information" -ForegroundColor Cyan
        Write-Host "=====================================" -ForegroundColor Cyan
        Write-Host ""
        
        $projectName = Split-Path $DevEnvContext.ProjectRoot -Leaf
        Write-Host "Project: " -NoNewline
        Write-Host $projectName -ForegroundColor White
        Write-Host ""
        
        # Load project config
        if (Test-Path $DevEnvContext.ConfigFile) {
            try {
                $projectConfig = Get-Content $DevEnvContext.ConfigFile | ConvertFrom-Json
                Write-Host "Description: " -NoNewline
                Write-Host $projectConfig.description -ForegroundColor Gray
                Write-Host "Template: " -NoNewline
                Write-Host $projectConfig.template -ForegroundColor Cyan
                Write-Host "Created: " -NoNewline
                Write-Host $projectConfig.created -ForegroundColor Gray
                Write-Host ""
            } catch {
                Write-Host "Could not read project configuration" -ForegroundColor Yellow
            }
        }
        
        Write-Host "Available Commands:" -ForegroundColor Yellow
        Write-Host "- .\bin\devenv.ps1 install        # Install development tools" -ForegroundColor White
        Write-Host "- .\bin\devenv.ps1 status         # Show environment status" -ForegroundColor White
        Write-Host "- .\bin\devenv.ps1 verify         # Verify installations" -ForegroundColor White
        Write-Host "- .\bin\devenv.ps1 list           # List available modules" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Project Structure:" -ForegroundColor Yellow
        $items = Get-ChildItem $DevEnvContext.ProjectRoot | Sort-Object Name
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                Write-Host "[DIR] $($item.Name)/" -ForegroundColor Blue
            } else {
                Write-Host "[FILE] $($item.Name)" -ForegroundColor Gray
            }
        }
        
    } else {
        # Global mode - show system analysis and project creation guidance
        Write-Host ""
        Write-Host "[GLOBAL] DevEnv Global Mode" -ForegroundColor Cyan
        Write-Host "===========================" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "Available Actions:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Project Management:" -ForegroundColor Cyan
        Write-Host "- .\devenv.ps1 create-project -Name MyProject    # Create new project" -ForegroundColor White
        Write-Host "- .\devenv.ps1 list                              # List available modules" -ForegroundColor White
        Write-Host ""
        Write-Host "Global Tools:" -ForegroundColor Cyan
        Write-Host "- .\devenv.ps1 install git vscode               # Install global tools" -ForegroundColor White
        Write-Host "- .\devenv.ps1 status                           # Show global status" -ForegroundColor White
        Write-Host ""
        
        Write-Host "Quick Start:" -ForegroundColor Yellow
        Write-Host "1. Create a new project:" -ForegroundColor White
        Write-Host "   .\devenv.ps1 create-project -Name MyProject" -ForegroundColor Gray
        Write-Host "2. Navigate to project:" -ForegroundColor White
        Write-Host "   cd MyProject" -ForegroundColor Gray
        Write-Host "3. Set up project environment:" -ForegroundColor White
        Write-Host "   .\bin\devenv.ps1 install" -ForegroundColor Gray
        Write-Host ""
    }
}
#endregion

#region Command Routing
function Invoke-ModeAwareCommand {
    <#
    .SYNOPSIS
        Routes commands based on execution mode
    #>
    param(
        [string]$Action,
        [string[]]$Modules,
        [hashtable]$DevEnvContext
    )
    
    Write-Host "Executing: " -NoNewline -ForegroundColor Gray
    Write-Host $Action -NoNewline -ForegroundColor White
    if ($Modules) {
        Write-Host " [$($Modules -join ', ')]" -NoNewline -ForegroundColor Cyan
    }
    Write-Host " in $($DevEnvContext.Mode) mode" -ForegroundColor Gray
    Write-Host ""
    
    switch ($Action) {
        'info' {
            Show-ModeAwareInfo $DevEnvContext
        }
        
        'status' {
            Show-ModeAwareStatus $DevEnvContext
        }
        
        'create-project' {
            if ($DevEnvContext.Mode -eq "Project") {
                throw "Cannot create project from project mode. Use global DevEnv."
            }
            
            if (-not $Name) {
                $Name = Read-Host "Enter project name"
            }
            
            New-DevEnvProject -ProjectName $Name -Template $Template
        }
        
        'install' {
            Write-Host "Module installation would happen here..." -ForegroundColor Yellow
            Write-Host "Mode: $($DevEnvContext.Mode)" -ForegroundColor Gray
            Write-Host "Data Dir: $($DevEnvContext.DataDir)" -ForegroundColor Gray
            Write-Host "Modules: $($Modules -join ', ')" -ForegroundColor Gray
            
            # This is where we'd call the existing module installation logic
            # with the appropriate data directory and configuration
        }
        
        'list' {
            Write-Host "Available Modules:" -ForegroundColor Yellow
            @("git", "vscode", "python", "nodejs", "docker", "powershell", "winget") | ForEach-Object {
                Write-Host "- $_" -ForegroundColor Cyan
            }
        }
        
        default {
            Write-Host "Command '$Action' not yet implemented in dual-mode system" -ForegroundColor Yellow
        }
    }
}
#endregion

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