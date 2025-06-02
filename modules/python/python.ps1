#Requires -Version 5.1
<#
.SYNOPSIS
    Python Module for DevEnv - Native Windows implementation with container support
.DESCRIPTION
    Native Windows module for Python development with virtual environments,
    package management, and containerized Python support.
#>

param (
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'grovel')]
    [string]$Action,
    
    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Initialization
$libPath = Join-Path $env:DEVENV_ROOT "lib\windows"
$requiredModules = @('logging.ps1', 'json.ps1', 'module.ps1', 'backup.ps1', 'alias.ps1')

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $libPath $module
    if (Test-Path $modulePath) {
        . $modulePath
    } else {
        Write-Error "Required module not found: $modulePath"
        exit 1
    }
}

$script:ModuleName = "python"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # Python installation
    'pip',          # Package management
    'venv',         # Virtual environments
    'packages',     # Development packages
    'jupyter',      # Jupyter notebooks
    'container',    # Container support
    'config',       # Python configuration
    'aliases'       # Command aliases
)
#endregion

#region State Management
function Save-ComponentState {
    param([string]$Component, [string]$Status)
    
    $stateDir = Split-Path $script:StateFile -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
    Add-Content -Path $script:StateFile -Value "$Component`:$Status`:$timestamp"
    Write-LogInfo "Saved state for component: $Component ($Status)" $script:ModuleName
}

function Test-ComponentState {
    param([string]$Component)
    
    if (Test-Path $script:StateFile) {
        $content = Get-Content $script:StateFile
        return ($content -match "^$Component`:installed:")
    }
    return $false
}

function Test-Component {
    param([string]$Component)
    
    switch ($Component) {
        'core' {
            # Check if Python is installed
            try {
                $pythonVersion = python --version 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'pip' {
            # Check if pip is available
            try {
                $null = pip --version 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'venv' {
            # Check if virtual environment exists
            $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
            $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
            $venvPython = Join-Path $venvPath "Scripts\python.exe"
            return (Test-Path $venvPython)
        }
        'packages' {
            # Check if essential packages are installed
            $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
            $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
            $venvPip = Join-Path $venvPath "Scripts\pip.exe"
            
            if (Test-Path $venvPip) {
                try {
                    $packages = & $venvPip list --format=freeze 2>$null
                    $requiredPackages = @('ipython', 'jupyter', 'black', 'pylint')
                    
                    foreach ($package in $requiredPackages) {
                        if (-not ($packages -match "^$package==")) {
                            return $false
                        }
                    }
                    return $true
                } catch {
                    return $false
                }
            }
            return $false
        }
        'jupyter' {
            # Check if Jupyter is available
            $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
            $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
            $jupyterPath = Join-Path $venvPath "Scripts\jupyter.exe"
            return (Test-Path $jupyterPath)
        }
        'container' {
            # Check if container configuration exists
            $containerEnabled = Get-ModuleConfig $script:ModuleName ".global.container.modules.python.containerize"
            if ($containerEnabled -eq $true) {
                try {
                    $null = docker.exe version 2>$null
                    return $LASTEXITCODE -eq 0
                } catch {
                    return $false
                }
            }
            return $true
        }
        'config' {
            # Check if configuration files exist
            $configPath = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
            $configPath = [System.Environment]::ExpandEnvironmentVariables($configPath)
            $configFiles = @("pyproject.toml", "pylintrc")
            
            foreach ($file in $configFiles) {
                if (-not (Test-Path (Join-Path $configPath $file))) {
                    return $false
                }
            }
            return $true
        }
        'aliases' {
            # Check if aliases are configured
            $aliasesFile = Join-Path (Get-AliasesDirectory) "aliases.ps1"
            return (Test-Path $aliasesFile) -and (Get-ModuleAliases $script:ModuleName)
        }
        default {
            return $false
        }
    }
}
#endregion

#region Component Installation
function Install-CoreComponent {
    Write-LogInfo "Installing Python core component..." $script:ModuleName
    
    # Check if Python is already installed
    try {
        $pythonVersion = python --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Python is already installed: $pythonVersion" $script:ModuleName
            return $true
        }
    } catch {}
    
    # Install Python via winget
    try {
        Write-LogInfo "Installing Python via winget..." $script:ModuleName
        $pythonId = "Python.Python.3.11"  # Use Python 3.11 for better compatibility
        
        winget.exe install --exact --id $pythonId --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Python installed successfully via winget" $script:ModuleName
            
            # Refresh PATH environment variable
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            
            # Wait a moment for installation to complete
            Start-Sleep -Seconds 5
            
            # Verify installation
            try {
                $pythonVersion = python --version 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-LogInfo "Python installation verified: $pythonVersion" $script:ModuleName
                    return $true
                }
            } catch {}
            
            Write-LogWarning "Python installation could not be verified immediately" $script:ModuleName
            return $true
        } else {
            Write-LogWarning "winget installation failed, trying Microsoft Store..." $script:ModuleName
        }
    } catch {
        Write-LogWarning "winget not available: $_" $script:ModuleName
    }
    
    # Fallback to Microsoft Store
    try {
        Write-LogInfo "Attempting to install Python from Microsoft Store..." $script:ModuleName
        winget.exe install --exact --id "9NRWMJP3717K" --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Python installed from Microsoft Store" $script:ModuleName
            return $true
        }
    } catch {
        Write-LogError "Failed to install Python from Microsoft Store: $_" $script:ModuleName
    }
    
    # Final fallback - direct download
    try {
        Write-LogInfo "Downloading Python installer directly..." $script:ModuleName
        $downloadUrl = "https://www.python.org/ftp/python/3.11.7/python-3.11.7-amd64.exe"
        $installerPath = Join-Path $env:TEMP "python-installer.exe"
        
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        
        Write-LogInfo "Installing Python..." $script:ModuleName
        Start-Process -FilePath $installerPath -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_test=0" -Wait
        
        # Clean up
        Remove-Item $installerPath -Force
        
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        
        Start-Sleep -Seconds 3
        
        # Verify installation
        try {
            $pythonVersion = python --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-LogInfo "Python installation verified: $pythonVersion" $script:ModuleName
                return $true
            }
        } catch {}
        
        Write-LogError "Python installation verification failed" $script:ModuleName
        return $false
    } catch {
        Write-LogError "Failed to install Python: $_" $script:ModuleName
        return $false
    }
}

function Install-PipComponent {
    Write-LogInfo "Configuring pip..." $script:ModuleName
    
    try {
        # Upgrade pip to latest version
        python -m pip install --upgrade pip
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "pip upgraded successfully" $script:ModuleName
            return $true
        } else {
            Write-LogError "Failed to upgrade pip" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Error configuring pip: $_" $script:ModuleName
        return $false
    }
}

function Install-VenvComponent {
    Write-LogInfo "Creating Python virtual environment..." $script:ModuleName
    
    try {
        $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
        $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
        
        # Create virtual environment directory
        $venvParent = Split-Path $venvPath -Parent
        if (-not (Test-Path $venvParent)) {
            New-Item -Path $venvParent -ItemType Directory -Force | Out-Null
        }
        
        # Create virtual environment
        if (-not (Test-Path $venvPath)) {
            Write-LogInfo "Creating virtual environment at: $venvPath" $script:ModuleName
            python -m venv $venvPath
            
            if ($LASTEXITCODE -ne 0) {
                Write-LogError "Failed to create virtual environment" $script:ModuleName
                return $false
            }
        }
        
        # Activate virtual environment and upgrade pip
        $activateScript = Join-Path $venvPath "Scripts\Activate.ps1"
        if (Test-Path $activateScript) {
            & $activateScript
            
            # Upgrade pip in virtual environment
            $venvPip = Join-Path $venvPath "Scripts\pip.exe"
            & $venvPip install --upgrade pip setuptools wheel
            
            Write-LogInfo "Virtual environment created and configured" $script:ModuleName
            return $true
        } else {
            Write-LogError "Virtual environment activation script not found" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Error creating virtual environment: $_" $script:ModuleName
        return $false
    }
}

function Install-PackagesComponent {
    Write-LogInfo "Installing Python packages..." $script:ModuleName
    
    try {
        $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
        $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
        $venvPip = Join-Path $venvPath "Scripts\pip.exe"
        
        if (-not (Test-Path $venvPip)) {
            Write-LogError "Virtual environment pip not found" $script:ModuleName
            return $false
        }
        
        # Get package lists from configuration
        $packageCategories = @('development', 'linting', 'testing', 'build')
        $allPackages = @()
        
        foreach ($category in $packageCategories) {
            $packages = Get-ModuleConfig $script:ModuleName ".python.packages.$category[]"
            if ($packages) {
                $allPackages += $packages
            }
        }
        
        # Also add data science packages
        $dataPackages = Get-ModuleConfig $script:ModuleName ".python.packages.utils.data_processing.packages[]"
        if ($dataPackages) {
            $allPackages += $dataPackages
        }
        
        # Install packages
        foreach ($package in $allPackages) {
            if (-not $package) { continue }
            
            Write-LogInfo "Installing package: $package" $script:ModuleName
            & $venvPip install $package
            
            if ($LASTEXITCODE -ne 0) {
                Write-LogWarning "Failed to install package: $package" $script:ModuleName
            } else {
                Write-LogInfo "Successfully installed: $package" $script:ModuleName
            }
        }
        
        return $true
    } catch {
        Write-LogError "Error installing packages: $_" $script:ModuleName
        return $false
    }
}

function Install-JupyterComponent {
    Write-LogInfo "Configuring Jupyter..." $script:ModuleName
    
    try {
        $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
        $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
        $venvPip = Join-Path $venvPath "Scripts\pip.exe"
        
        # Install Jupyter packages
        $jupyterPackages = @('jupyter', 'jupyterlab', 'notebook', 'ipykernel')
        
        foreach ($package in $jupyterPackages) {
            Write-LogInfo "Installing $package..." $script:ModuleName
            & $venvPip install $package
        }
        
        # Configure Jupyter kernel
        $venvPython = Join-Path $venvPath "Scripts\python.exe"
        & $venvPython -m ipykernel install --user --name devenv-python --display-name "DevEnv Python"
        
        Write-LogInfo "Jupyter configured successfully" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Error configuring Jupyter: $_" $script:ModuleName
        return $false
    }
}

function Install-ContainerComponent {
    Write-LogInfo "Installing Python container component..." $script:ModuleName
    
    # Check if containerization is enabled
    $containerEnabled = Get-ModuleConfig $script:ModuleName ".global.container.modules.python.containerize"
    if ($containerEnabled -ne $true) {
        Write-LogInfo "Python containerization not enabled" $script:ModuleName
        return $true
    }
    
    # Check if Docker is available
    try {
        $null = docker.exe version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-LogWarning "Docker not available, skipping container setup" $script:ModuleName
            return $true
        }
    } catch {
        Write-LogWarning "Docker not available, skipping container setup" $script:ModuleName
        return $true
    }
    
    try {
        $containerDir = Join-Path $env:DEVENV_DATA_DIR "containers\python"
        if (-not (Test-Path $containerDir)) {
            New-Item -Path $containerDir -ItemType Directory -Force | Out-Null
        }
        
        # Create Dockerfile
        $dockerfile = Join-Path $containerDir "Dockerfile"
        $dockerfileContent = @"
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \\
    build-essential \\
    curl \\
    git \\
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /home/user

# Create user
RUN useradd -m -s /bin/bash user
USER user

# Set up Python environment
ENV PATH="/home/user/.local/bin:`$PATH"
ENV PYTHONPATH="/home/user/projects"

# Install common Python packages
COPY requirements.txt /tmp/
RUN pip install --user --no-cache-dir -r /tmp/requirements.txt

# Expose Jupyter port
EXPOSE 8888

# Default command
CMD ["python"]
"@
        
        Set-Content -Path $dockerfile -Value $dockerfileContent -Encoding UTF8
        
        # Create requirements.txt
        $requirements = Join-Path $containerDir "requirements.txt"
        $requirementsContent = @"
# Development tools
ipython
jupyter
jupyterlab
notebook
ipykernel

# Code quality
black
pylint
flake8
mypy
isort

# Testing
pytest
pytest-cov

# Data science
numpy
pandas
matplotlib
seaborn
scipy
scikit-learn

# Utilities
requests
click
python-dotenv
"@
        
        Set-Content -Path $requirements -Value $requirementsContent -Encoding UTF8
        
        # Create docker-compose.yml
        $composeFile = Join-Path $containerDir "docker-compose.yml"
        $composeContent = @"
version: '3.8'

services:
  python:
    build: .
    container_name: devenv-python
    ports:
      - "8888:8888"
    volumes:
      - $($env:USERPROFILE.Replace('\', '/')):/home/user/host-home
      - $($env:DEVENV_ROOT.Replace('\', '/')):/home/user/devenv
      - python-packages:/home/user/.local
    working_dir: /home/user/projects
    environment:
      - JUPYTER_ENABLE_LAB=yes
    command: tail -f /dev/null
    restart: unless-stopped

volumes:
  python-packages:
"@
        
        Set-Content -Path $composeFile -Value $composeContent -Encoding UTF8
        
        # Create start script
        $startScript = Join-Path $containerDir "start-python.ps1"
        $startScriptContent = @"
# Start Python container
param(
    [switch]`$Rebuild,
    [switch]`$Jupyter
)

`$containerDir = "$containerDir"
Push-Location `$containerDir

try {
    if (`$Rebuild) {
        Write-Host "Rebuilding Python container..." -ForegroundColor Yellow
        docker-compose down
        docker-compose build --no-cache
    }
    
    Write-Host "Starting Python container..." -ForegroundColor Green
    docker-compose up -d
    
    if (`$LASTEXITCODE -eq 0) {
        if (`$Jupyter) {
            Write-Host ""
            Write-Host "Starting Jupyter Lab in container..." -ForegroundColor Green
            docker-compose exec python jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root
        } else {
            Write-Host ""
            Write-Host "Python container is running!" -ForegroundColor Green
            Write-Host "Container name: devenv-python" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Quick commands:" -ForegroundColor White
            Write-Host "  docker exec -it devenv-python python" -ForegroundColor Gray
            Write-Host "  docker exec -it devenv-python jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root" -ForegroundColor Gray
        }
    } else {
        Write-Host "Failed to start Python container" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}
"@
        
        Set-Content -Path $startScript -Value $startScriptContent -Encoding UTF8
        
        Write-LogInfo "Python container configuration created at: $containerDir" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Failed to configure Python container: $_" $script:ModuleName
        return $false
    }
}

function Install-ConfigComponent {
    Write-LogInfo "Installing Python configuration..." $script:ModuleName
    
    try {
        $configPath = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
        $configPath = [System.Environment]::ExpandEnvironmentVariables($configPath)
        
        if (-not (Test-Path $configPath)) {
            New-Item -Path $configPath -ItemType Directory -Force | Out-Null
        }
        
        # Create pyproject.toml for Black and other tools
        $pyprojectPath = Join-Path $configPath "pyproject.toml"
        $pyprojectContent = @"
[tool.black]
line-length = 100
target-version = ['py311']
skip-string-normalization = true

[tool.isort]
profile = "black"
line_length = 100

[tool.mypy]
python_version = "3.11"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = "-v --tb=short"
"@
        
        Set-Content -Path $pyprojectPath -Value $pyprojectContent -Encoding UTF8
        
        # Create pylintrc
        $pylintrcPath = Join-Path $configPath "pylintrc"
        $pylintrcContent = @"
[MASTER]
persistent=yes

[MESSAGES CONTROL]
disable=C0111,C0103,R0903,R0913,W0613

[REPORTS]
output-format=text
reports=no

[FORMAT]
max-line-length=100

[BASIC]
good-names=i,j,k,ex,Run,_,df,ax,fig

[DESIGN]
max-args=7
max-locals=15
max-returns=6
max-branches=12
max-statements=50
"@
        
        Set-Content -Path $pylintrcPath -Value $pylintrcContent -Encoding UTF8
        
        Write-LogInfo "Python configuration files created" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Failed to create configuration: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing Python aliases..." $script:ModuleName
    
    # Add module aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    
    foreach ($category in $aliasCategories) {
        if (Add-ModuleAliases $script:ModuleName $category) {
            Write-LogInfo "Added aliases for category: $category" $script:ModuleName
        } else {
            Write-LogWarning "Failed to add aliases for category: $category" $script:ModuleName
        }
    }
    
    # Create Python wrapper scripts
    $scriptsPath = Join-Path $env:DEVENV_DATA_DIR "python\scripts"
    if (-not (Test-Path $scriptsPath)) {
        New-Item -Path $scriptsPath -ItemType Directory -Force | Out-Null
    }
    
    # Create Python wrapper
    $pythonWrapper = Join-Path $scriptsPath "py.ps1"
    $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
    $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
    $venvPython = Join-Path $venvPath "Scripts\python.exe"
    
    $wrapperContent = @"
# Python wrapper script
param([Parameter(ValueFromRemainingArguments)]`$Args)

`$venvPython = "$venvPython"

if (Test-Path `$venvPython) {
    & `$venvPython @Args
} else {
    python @Args
}
"@
    
    Set-Content -Path $pythonWrapper -Value $wrapperContent -Encoding UTF8
    
    return $true
}
#endregion

#region Main Module Functions
function Install-Component {
    param([string]$Component)
    
    if ((Test-ComponentState $Component) -and (Test-Component $Component) -and -not $Force) {
        Write-LogInfo "Component $Component already installed and verified" $script:ModuleName
        return $true
    }
    
    $result = switch ($Component) {
        'core' { Install-CoreComponent }
        'pip' { Install-PipComponent }
        'venv' { Install-VenvComponent }
        'packages' { Install-PackagesComponent }
        'jupyter' { Install-JupyterComponent }
        'container' { Install-ContainerComponent }
        'config' { Install-ConfigComponent }
        'aliases' { Install-AliasesComponent }
        default { 
            Write-LogError "Unknown component: $Component" $script:ModuleName
            $false
        }
    }
    
    if ($result) {
        Save-ComponentState $Component 'installed'
        Write-LogInfo "Successfully installed component: $Component" $script:ModuleName
    } else {
        Write-LogError "Failed to install component: $Component" $script:ModuleName
    }
    
    return $result
}

function Test-ModuleInstallation {
    Write-LogInfo "Checking Python module installation status..." $script:ModuleName
    
    $needsInstallation = $false
    
    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component
        
        if (-not $isInstalled -or -not $isVerified) {
            Write-LogInfo "Component $component needs installation" $script:ModuleName
            $needsInstallation = $true
        }
    }
    
    return -not $needsInstallation
}

function Install-Module {
    Write-LogInfo "Installing $($script:ModuleName) module..." $script:ModuleName
    
    if (-not $Force -and (Test-ModuleInstallation)) {
        Write-LogInfo "Module already installed and verified" $script:ModuleName
        Show-ModuleInfo
        return $true
    }
    
    # Create backup before installation
    New-Backup $script:ModuleName
    
    # Install each component
    foreach ($component in $script:Components) {
        Write-LogInfo "Installing component: $component" $script:ModuleName
        
        if (-not (Install-Component $component)) {
            Write-LogError "Failed to install component: $component" $script:ModuleName
            return $false
        }
    }
    
    Write-LogInfo "Python module installation completed successfully" $script:ModuleName
    Show-ModuleInfo
    
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName
    
    # Create backup before removal
    New-Backup $script:ModuleName
    
    # Stop container if running
    $containerDir = Join-Path $env:DEVENV_DATA_DIR "containers\python"
    if (Test-Path $containerDir) {
        try {
            Push-Location $containerDir
            docker-compose down 2>$null
            Pop-Location
        } catch {
            # Ignore errors
        }
    }
    
    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }
    
    # Remove virtual environment
    $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
    $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
    if (Test-Path $venvPath) {
        Remove-Item $venvPath -Recurse -Force
    }
    
    # Remove configuration
    $configPath = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
    $configPath = [System.Environment]::ExpandEnvironmentVariables($configPath)
    if (Test-Path $configPath) {
        Remove-Item $configPath -Recurse -Force
    }
    
    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    
    Write-LogInfo "Python module configuration removed" $script:ModuleName
    Write-LogWarning "Python installation and system packages were preserved" $script:ModuleName
    
    return $true
}

function Test-ModuleVerification {
    Write-LogInfo "Verifying $($script:ModuleName) module installation..." $script:ModuleName
    
    $allVerified = $true
    
    foreach ($component in $script:Components) {
        if (-not (Test-Component $component)) {
            Write-LogError "Verification failed for component: $component" $script:ModuleName
            $allVerified = $false
        } else {
            Write-LogInfo "Component verified: $component" $script:ModuleName
        }
    }
    
    if ($allVerified) {
        Write-LogInfo "Python module verification completed successfully" $script:ModuleName
        
        # Show Python version
        try {
            $version = python --version 2>$null
            Write-LogInfo "Python version: $version" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine Python version" $script:ModuleName
        }
    }
    
    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Python Development Environment
===============================

Description:
-----------
Complete Python development setup with virtual environments, package management,
and container support for reproducible development.

Benefits:
--------
+ Native Integration - Windows Python installation via winget
+ Virtual Environments - Isolated Python environments for projects
+ Container Option - Containerized Python with Jupyter support
+ Package Management - Pre-configured with essential development packages
+ Code Quality - Black, pylint, mypy, and other linting tools

Components:
----------
1. Core Python
   - Python 3.11 installation via winget
   - pip package manager
   - PATH configuration

2. Virtual Environment
   - Dedicated DevEnv Python environment
   - Isolated package installation
   - Jupyter kernel registration

3. Development Packages
   - IPython, Jupyter, JupyterLab
   - Black, pylint, flake8, mypy
   - pytest, numpy, pandas, matplotlib

4. Container Support (Optional)
   - Docker container with Python environment
   - Jupyter Lab in browser
   - Persistent package storage

Quick Commands:
--------------
python                   # Python interpreter
pip install package     # Install package
jupyter lab             # Start Jupyter Lab

Container Mode:
--------------
# Start Python container
& "$env:DEVENV_DATA_DIR\containers\python\start-python.ps1"

# Start with Jupyter
& "$env:DEVENV_DATA_DIR\containers\python\start-python.ps1" -Jupyter

"@

    Write-Host $header -ForegroundColor Cyan
    
    # Show current installation status
    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow
    
    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component
        
        if ($isInstalled -and $isVerified) {
            Write-Host "+ $component`: Installed and verified" -ForegroundColor Green
            
            # Show additional info for specific components
            switch ($component) {
                'core' {
                    try {
                        $version = python --version 2>$null
                        Write-Host "  Version: $version" -ForegroundColor Gray
                    } catch {}
                }
                'venv' {
                    $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
                    $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
                    Write-Host "  Virtual Env: $venvPath" -ForegroundColor Gray
                }
                'packages' {
                    $venvPath = Get-ModuleConfig $script:ModuleName ".shell.paths.venv_dir"
                    $venvPath = [System.Environment]::ExpandEnvironmentVariables($venvPath)
                    $venvPip = Join-Path $venvPath "Scripts\pip.exe"
                    if (Test-Path $venvPip) {
                        try {
                            $packageCount = (& $venvPip list --format=freeze 2>$null | Measure-Object -Line).Lines
                            Write-Host "  Packages: $packageCount installed" -ForegroundColor Gray
                        } catch {}
                    }
                }
                'container' {
                    $containerEnabled = Get-ModuleConfig $script:ModuleName ".global.container.modules.python.containerize"
                    if ($containerEnabled -eq $true) {
                        try {
                            $containerStatus = docker ps --filter "name=devenv-python" --format "{{.Status}}" 2>$null
                            if ($containerStatus) {
                                Write-Host "  Container: $containerStatus" -ForegroundColor Gray
                            } else {
                                Write-Host "  Container: Not running" -ForegroundColor Gray
                            }
                        } catch {
                            Write-Host "  Container: Docker not available" -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "  Container: Disabled" -ForegroundColor Gray
                    }
                }
            }
        } elseif ($isInstalled) {
            Write-Host "[WARN] $component`: Installed but not verified" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] $component`: Not installed" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}
#endregion

#region Main Execution
try {
    switch ($Action.ToLower()) {
        'grovel' {
            if (Test-ModuleInstallations) { exit 0 } else { exit 1 }
        }
        'install' {
            $success = Install-Module
            if ($success) { exit 0 } else { exit 1 }
        }
        'remove' {
            $success = Remove-Module
            if ($success) { exit 0 } else { exit 1 }
        }
        'verify' {
            $success = Test-ModuleVerification
            if ($success) { exit 0 } else { exit 1 }
        }
        'info' {
            Show-ModuleInfo
            exit 0
        }
        default {
            Write-LogError "Unknown action: $Action" $script:ModuleName
            Write-LogError "Usage: $($MyInvocation.MyCommand.Name) {install|remove|verify|info|grovel} [-Force]" $script:ModuleName
            exit 1
        }
    }
}
catch {
    Write-LogError "Module execution failed: $_" $script:ModuleName
    Write-LogError "Stack trace: $($_.ScriptStackTrace)" $script:ModuleName
    exit 1
}
#endregion