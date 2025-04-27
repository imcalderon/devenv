# devenv.ps1 - Windows implementation of DevEnv

param (
    [string]$ConfigFile,
    [string]$RootDir,
    [Parameter(ValueFromRemainingArguments=$true)]
    $RemainingArgs
)

# Convert remaining args to array
$args = @()
if ($RemainingArgs) {
    $args = $RemainingArgs
}

# Get script directory if not provided
if (-not $RootDir) {
    function Get-ScriptDirectory {
        # Improved method that works in more contexts
        $scriptPath = $null
        try {
            $scriptPath = $MyInvocation.MyCommand.Path
            if (-not $scriptPath) {
                $scriptPath = $PSCommandPath
            }
        } catch {
            # Fallback to current directory
            $scriptPath = $PSScriptRoot
            if (-not $scriptPath) {
                $scriptPath = Get-Location
            }
        }
        
        if ($scriptPath -and (Test-Path $scriptPath)) {
            return Split-Path $scriptPath -Parent
        } else {
            # Last resort - use the current directory
            return (Get-Location).Path
        }
    }

    $RootDir = Get-ScriptDirectory
}

# If config file not specified, use default
if (-not $ConfigFile) {
    $ConfigFile = Join-Path -Path $RootDir -ChildPath "config.json"
    
    # If config.json doesn't exist, create it from template
    $TemplateFile = Join-Path -Path $RootDir -ChildPath "config.template.json"
    if ((-not (Test-Path $ConfigFile)) -and (Test-Path $TemplateFile)) {
        Write-Host "Creating config.json from template..."
        Copy-Item $TemplateFile $ConfigFile
    }
}

# Verify config file exists
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Error: Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Please create a config.json file based on config.template.json" -ForegroundColor Red
    exit 1
}

# Setup project environment variables
function Setup-Environment {
    param (
        [string]$RootDir
    )
    
    # Set up project-specific environment variables
    $env:DEVENV_ROOT = $RootDir
    $env:DEVENV_DATA_DIR = Join-Path -Path $RootDir -ChildPath "data"
    $env:DEVENV_CONFIG_DIR = Join-Path -Path $RootDir -ChildPath "config"
    $env:DEVENV_MODULES_DIR = Join-Path -Path $RootDir -ChildPath "modules"
    
    # Create data directories if they don't exist
    New-Item -Path $env:DEVENV_DATA_DIR -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path -Path $env:DEVENV_DATA_DIR -ChildPath "state") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path -Path $env:DEVENV_DATA_DIR -ChildPath "logs") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path -Path $env:DEVENV_DATA_DIR -ChildPath "backups") -ItemType Directory -Force | Out-Null
    
    # Platform-specific environment setup for Windows
    $env:DEVENV_HOME = $env:DEVENV_ROOT
    $env:DEVENV_STATE_DIR = Join-Path -Path $env:DEVENV_DATA_DIR -ChildPath "state"
    $env:DEVENV_LOGS_DIR = Join-Path -Path $env:DEVENV_DATA_DIR -ChildPath "logs"
    $env:DEVENV_BACKUPS_DIR = Join-Path -Path $env:DEVENV_DATA_DIR -ChildPath "backups"
}

# Load configuration
function Load-Config {
    param ([string]$ConfigFile)
    
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        Write-Host "Error loading config file: $_" -ForegroundColor Red
        exit 1
    }
}

# Setup environment variables
Setup-Environment $RootDir

# Load configuration
$Config = Load-Config $ConfigFile

# Check if WSL is available and should be used
function Use-WSL {
    param ($Config)
    
    # Check if WSL is enabled in config
    if ($Config.platforms.windows.wsl.enabled -ne $true) {
        return $false
    }
    
    # Check if WSL is installed
    try {
        $wslVersion = wsl.exe --status 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }
    catch {
        # WSL not available
        return $false
    }
    
    return $false
}

# Main execution
function Main {
    param (
        $Config,
        [string]$RootDir,
        [string]$ConfigFile,
        $Args
    )
    
    # Set environment variables
    $env:ROOT_DIR = $RootDir
    $env:CONFIG_FILE = $ConfigFile
    
    # Check if we should use WSL
    $useWsl = Use-WSL $Config
    
    if ($useWsl) {
        Write-Host "Using WSL for DevEnv execution..."
        
        # Check if WSL distribution is installed
        $distribution = $Config.platforms.windows.wsl.distribution
        try {
            $wslList = wsl.exe --list | Out-String
            if (-not ($wslList -like "*$distribution*")) {
                Write-Host "WSL distribution $distribution not found." -ForegroundColor Yellow
                Write-Host "Please install it with: wsl --install -d $distribution" -ForegroundColor Yellow
                Write-Host "Falling back to native Windows execution..." -ForegroundColor Yellow
                $useWsl = $false
            }
        }
        catch {
            Write-Host "Error checking WSL distributions: $_" -ForegroundColor Yellow
            Write-Host "Falling back to native Windows execution..." -ForegroundColor Yellow
            $useWsl = $false
        }
    }
    
    # Execute with WSL or native
    if ($useWsl) {
        # Convert Windows paths to WSL paths
        $wslRootDir = (wsl.exe wslpath "$RootDir") -replace "`r`n","" -replace "`n",""
        $wslConfigFile = (wsl.exe wslpath "$ConfigFile") -replace "`r`n","" -replace "`n",""
        
        # Prepare arguments
        $argString = ($Args | ForEach-Object { "`"$_`"" }) -join " "
        
        # Setup WSL environment variables
        $envSetup = "export DEVENV_ROOT='$wslRootDir' && "
        $envSetup += "export DEVENV_DATA_DIR='$wslRootDir/data' && "
        $envSetup += "export DEVENV_STATE_DIR='$wslRootDir/data/state' && "
        $envSetup += "export DEVENV_LOGS_DIR='$wslRootDir/data/logs' && "
        $envSetup += "export DEVENV_BACKUPS_DIR='$wslRootDir/data/backups' && "
        
        # Prepare the final WSL command
        $wslCommand = "$envSetup cd '$wslRootDir' && ./devenv.sh $argString"
        
        # Execute in WSL
        wsl.exe -d $distribution bash -c $wslCommand
    }
    else {
        # Use native Windows implementation
        $windowsExec = Join-Path -Path $RootDir -ChildPath "lib\windows\execute.ps1"
        if (Test-Path $windowsExec) {
            & $windowsExec -ConfigFile $ConfigFile -RootDir $RootDir -Args $Args
        } else {
            Write-Host "Error: Windows implementation not found: $windowsExec" -ForegroundColor Red
            Write-Host "Please make sure the 'lib\windows' directory exists and contains the required files." -ForegroundColor Red
            exit 1
        }
    }
}

# Run the main function
Main $Config $RootDir $ConfigFile $args