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

    # Additional environment variables needed by module system
    $env:DEVENV_STATE_DIR = Join-Path $DevEnvContext.DataDir "state"
    $env:DEVENV_LOGS_DIR = Join-Path $DevEnvContext.DataDir "logs"
    $env:DEVENV_BACKUPS_DIR = Join-Path $DevEnvContext.DataDir "backups"
    $env:DEVENV_MODULES_DIR = Join-Path $env:DEVENV_ROOT "modules"

    # Module-specific data directories
    $env:DEVENV_PYTHON_DIR = Join-Path $DevEnvContext.DataDir "python"
    $env:DEVENV_NODEJS_DIR = Join-Path $DevEnvContext.DataDir "nodejs"
    $env:DEVENV_GO_DIR = Join-Path $DevEnvContext.DataDir "go"

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
