# DevEnv Windows Installer
# This script installs and configures WSL 2 and sets up the DevEnv project within it.

param (
    [switch]$Force = $false,
    [string]$Distribution = "Ubuntu-20.04",
    [string]$ProjectsDir = "E:\proj",
    [string]$DevEnvRepo = "https://github.com/imcalderon/devenv.git"
)

# Ensure script is running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Please restart as Administrator." -ForegroundColor Red
    exit 1
}

# Set up logging
$LogFile = "$env:USERPROFILE\devenv_install.log"
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $logMessage
    
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARN" { Write-Host $Message -ForegroundColor Yellow }
        "INFO" { Write-Host $Message -ForegroundColor Green }
        default { Write-Host $Message }
    }
}

# Clear previous log if $Force is true
if ($Force) {
    if (Test-Path $LogFile) {
        Remove-Item $LogFile -Force
    }
}

Write-Log "Starting DevEnv Windows installation..."
Write-Log "Log file: $LogFile"

# Create Projects directory if it doesn't exist
if (-not (Test-Path $ProjectsDir)) {
    Write-Log "Creating Projects directory: $ProjectsDir"
    New-Item -Path $ProjectsDir -ItemType Directory -Force | Out-Null
}

# Check if WSL is already installed
$wslInstalled = $null
try {
    $wslInstalled = Get-Command wsl.exe -ErrorAction Stop
    Write-Log "WSL is already installed: $($wslInstalled.Version)"
} catch {
    Write-Log "WSL is not installed. Installing WSL..." "INFO"
}

# Install WSL if not already installed
if ($null -eq $wslInstalled) {
    Write-Log "Enabling WSL feature..."
    try {
        # Enable WSL feature
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
        
        # Enable Virtual Machine Platform
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
        
        Write-Log "WSL features enabled. A system restart is required."
        $restart = Read-Host "Do you want to restart now? (y/n)"
        if ($restart -eq "y") {
            Restart-Computer -Force
            exit 0
        } else {
            Write-Log "Please restart your computer before continuing." "WARN"
            exit 0
        }
    } catch {
        Write-Log "Failed to enable WSL features: $_" "ERROR"
        exit 1
    }
}

# Check if WSL 2 is set as default
try {
    $wslVersion = wsl.exe --status | Select-String "Default Version"
    if (-not ($wslVersion -like "*2")) {
        Write-Log "Setting WSL 2 as default..."
        wsl.exe --set-default-version 2
    } else {
        Write-Log "WSL 2 is already set as default."
    }
} catch {
    Write-Log "Failed to set WSL 2 as default: $_" "ERROR"
    
    # Download and install WSL 2 kernel update
    Write-Log "Downloading WSL 2 kernel update..."
    $kernelUpdateUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    $kernelUpdateFile = "$env:TEMP\wsl_update_x64.msi"
    
    try {
        Invoke-WebRequest -Uri $kernelUpdateUrl -OutFile $kernelUpdateFile
        Write-Log "Installing WSL 2 kernel update..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$kernelUpdateFile`" /qn" -Wait
        
        # Try setting default version again
        wsl.exe --set-default-version 2
    } catch {
        Write-Log "Failed to install WSL 2 kernel update: $_" "ERROR"
        exit 1
    }
}

# Check if distribution is installed
$distroInstalled = $false
try {
    $wslList = wsl.exe --list
    $distroInstalled = $wslList -like "*$Distribution*"
} catch {
    Write-Log "Failed to check installed WSL distributions: $_" "ERROR"
}

# Install distribution if not already installed
if (-not $distroInstalled) {
    Write-Log "Installing $Distribution..."
    try {
        wsl.exe --install -d $Distribution
        
        # Wait for distribution to be installed
        $timeout = 300  # 5 minutes
        $elapsed = 0
        $installed = $false
        
        while (-not $installed -and $elapsed -lt $timeout) {
            Start-Sleep -Seconds 5
            $elapsed += 5
            
            $wslList = wsl.exe --list
            $installed = $wslList -like "*$Distribution*"
            
            if ($installed) {
                Write-Log "$Distribution installed successfully."
                break
            } else {
                Write-Log "Waiting for $Distribution installation... ($elapsed seconds elapsed)"
            }
        }
        
        if (-not $installed) {
            Write-Log "Timed out waiting for $Distribution installation." "ERROR"
            exit 1
        }
    } catch {
        Write-Log "Failed to install $Distribution: $_" "ERROR"
        exit 1
    }
}

# Configure WSL
Write-Log "Configuring WSL..."

# Create .wslconfig in user profile
$wslConfigFile = "$env:USERPROFILE\.wslconfig"
if (-not (Test-Path $wslConfigFile) -or $Force) {
    Write-Log "Creating .wslconfig..."
    Set-Content -Path $wslConfigFile -Value @"
[wsl2]
memory=8GB
processors=4
swap=4GB
"@
}

# Create .devenv directory for icons and resources
$devenvDir = "$env:USERPROFILE\.devenv"
if (-not (Test-Path $devenvDir)) {
    Write-Log "Creating .devenv directory..."
    New-Item -Path $devenvDir -ItemType Directory -Force | Out-Null
}

rem # Create icons directory
rem $iconsDir = "$devenvDir\icons"
rem if (-not (Test-Path $iconsDir)) {
rem     New-Item -Path $iconsDir -ItemType Directory -Force | Out-Null
rem }

rem # Download devenv icon for Windows Terminal
rem $iconUrl = "https://github.com/imcalderon/devenv/main/resources/devenv-icon.png"
rem $iconPath = "$iconsDir\devenv.png"
rem try {
rem     if (-not (Test-Path $iconPath) -or $Force) {
rem         Write-Log "Downloading DevEnv icon..."
rem         Invoke-WebRequest -Uri $iconUrl -OutFile $iconPath
rem     }