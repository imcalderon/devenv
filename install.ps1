# DevEnv Windows Installer
# This script installs and configures WSL 2 and sets up the DevEnv project within it.
param (
    [switch]$Force = $False,
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

# Set up logging in the projects directory
$LogFile = "$ProjectsDir\devenv_install.log"
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

# Create DevEnv directory structure in projects directory
$DevEnvDir = "$ProjectsDir\devenv"
$DevEnvConfigDir = "$DevEnvDir\config"
$DevEnvTempDir = "$DevEnvDir\temp"
$WslStorageDir = "$ProjectsDir\wsl\$Distribution"

if (-not (Test-Path $DevEnvDir)) {
    New-Item -Path $DevEnvDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $DevEnvConfigDir)) {
    New-Item -Path $DevEnvConfigDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $DevEnvTempDir)) {
    New-Item -Path $DevEnvTempDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $WslStorageDir)) {
    New-Item -Path $WslStorageDir -ItemType Directory -Force | Out-Null
}

Write-Log "Starting DevEnv Windows installation..."
Write-Log "Log file: $LogFile"
Write-Log "Projects directory: $ProjectsDir"
Write-Log "DevEnv directory: $DevEnvDir"
Write-Log "WSL Storage directory: $WslStorageDir"

# Set default configuration values
$WslUsername = "devuser"
$WslPassword = "Password1"
$WslMemory = "8GB"
$WslProcessors = 4
$WslSwap = "4GB"

# Read configuration from existing config.json if available
$configPath = "$ProjectsDir\devenv\config.json"
if (Test-Path $configPath) {
    try {
        Write-Log "Reading configuration from $configPath..."
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        
        # Extract WSL configuration if available
        if ($null -ne $config.PSObject.Properties['wsl']) {
            Write-Log "Found WSL configuration section"
            
            if ($null -ne $config.wsl.PSObject.Properties['username']) {
                $WslUsername = $config.wsl.username
                Write-Log "Using configured WSL username: $WslUsername"
            }
            
            if ($null -ne $config.wsl.PSObject.Properties['password']) {
                $WslPassword = $config.wsl.password
                Write-Log "Using configured WSL password"
            }
            
            if ($null -ne $config.wsl.PSObject.Properties['memory']) {
                $WslMemory = $config.wsl.memory
                Write-Log "Using configured WSL memory: $WslMemory"
            }
            
            if ($null -ne $config.wsl.PSObject.Properties['processors']) {
                $WslProcessors = $config.wsl.processors
                Write-Log "Using configured WSL processors: $WslProcessors"
            }
            
            if ($null -ne $config.wsl.PSObject.Properties['swap']) {
                $WslSwap = $config.wsl.swap
                Write-Log "Using configured WSL swap: $WslSwap"
            }
        } else {
            # If no WSL section exists, create it in the config
            Write-Log "No WSL configuration found, using defaults and updating config"
            
            # Create WSL configuration object
            $wslConfig = [PSCustomObject]@{
                username = $WslUsername
                password = $WslPassword
                memory = $WslMemory
                processors = $WslProcessors
                swap = $WslSwap
            }
            
            # Add WSL configuration to existing config
            $config | Add-Member -MemberType NoteProperty -Name 'wsl' -Value $wslConfig
            
            # Save updated configuration
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath
            Write-Log "Updated configuration file with WSL settings"
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error reading configuration: $errorMessage" "WARN"
        Write-Log "Using default WSL configuration"
    }
} else {
    Write-Log "Configuration file not found at $configPath, using defaults" "WARN"
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
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to enable WSL features: $errorMessage" "ERROR"
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
    $errorMessage = $_.Exception.Message
    Write-Log "Failed to set WSL 2 as default: $errorMessage" "ERROR"
    
    # Download and install WSL 2 kernel update
    Write-Log "Downloading WSL 2 kernel update..."
    $kernelUpdateUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    $kernelUpdateFile = "$DevEnvTempDir\wsl_update_x64.msi"
    
    try {
        Invoke-WebRequest -Uri $kernelUpdateUrl -OutFile $kernelUpdateFile
        Write-Log "Installing WSL 2 kernel update..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$kernelUpdateFile`" /qn" -Wait
        
        # Try setting default version again
        wsl.exe --set-default-version 2
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Failed to install WSL 2 kernel update: $errorMessage" "ERROR"
        exit 1
    }
}

# Create .wslconfig in projects directory
$wslConfigFile = "$DevEnvConfigDir\.wslconfig"
if (-not (Test-Path $wslConfigFile) -or $Force) {
    Write-Log "Creating .wslconfig in $DevEnvConfigDir..."
    Set-Content -Path $wslConfigFile -Value @"
[wsl2]
memory=$WslMemory
processors=$WslProcessors
swap=$WslSwap
"@

    # Copy the file to user profile for WSL to pick it up
    Copy-Item $wslConfigFile "$env:USERPROFILE\.wslconfig" -Force
    Write-Log "Copied .wslconfig to $env:USERPROFILE\.wslconfig"
}

# Check if distribution is already installed and set up
$distroIsSetup = $false
try {
    # Check if distribution exists
    $existingDistros = wsl.exe --list --verbose 2>$null
    if ($existingDistros -like "*$Distribution*") {
        # Try running a simple command to see if it's set up
        $result = wsl.exe -d $Distribution -e bash -c "echo 'WSL_SETUP_TEST'" 2>$null
        if ($result -like "*WSL_SETUP_TEST*") {
            $distroIsSetup = $true
            Write-Log "Distribution is installed and set up correctly."
        }
    }
} catch {
    $distroIsSetup = $false
}

# Check if distribution is installed in our custom location
$customDistroInstalled = $false
if ($distroIsSetup) {
    $distroInfo = (Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -Recurse | ForEach-Object {
        $distro = ($_ | Get-ItemProperty -Name DistributionName -ErrorAction SilentlyContinue).DistributionName
        if ($distro -eq $Distribution) {
            $basePath = ($_ | Get-ItemProperty -Name BasePath).BasePath
            [PSCustomObject]@{
                Name = $distro
                Path = $basePath -replace '^\\\\\?\\',''
            }
        }
    })
    
    if ($distroInfo -and $distroInfo.Path -like "$WslStorageDir*") {
        $customDistroInstalled = $true
        Write-Log "Distribution is already installed in custom location: $($distroInfo.Path)"
    } else {
        Write-Log "Distribution is installed but not in custom location"
        if ($Force) {
            Write-Log "Force flag is set, will reinstall in custom location"
            $distroIsSetup = $false
            wsl.exe --unregister $Distribution
        }
    }
}

# If not already set up or not in custom location, install/move the distribution
if (-not $customDistroInstalled) {
    if (-not $distroIsSetup) {
        # Install the distribution
        Write-Log "Installing distribution temporarily in default location..."
        try {
            # Check if it's already registered
            if ($existingDistros -like "*$Distribution*") {
                Write-Log "Unregistering existing distribution..."
                wsl.exe --unregister $Distribution
            }
            
            # Install the distribution
            Write-Log "Starting distribution installation - a new window may open for setup..."
            wsl.exe --install -d $Distribution
            
            # Prompt user for interaction
            Write-Host ""
            Write-Host "IMPORTANT: A separate window has opened to complete the WSL setup." -ForegroundColor Yellow
            Write-Host "Please complete the following steps in that window:" -ForegroundColor Yellow
            Write-Host "1. Create a username and password when prompted" -ForegroundColor Yellow
            Write-Host "2. Wait for the installation to complete" -ForegroundColor Yellow
            Write-Host "3. When you see the Linux prompt (like 'username@hostname:~$'), the setup is complete" -ForegroundColor Yellow
            Write-Host ""
            $confirmation = Read-Host "Type 'continue' when you've completed the WSL setup"
            
            while ($confirmation -ne "continue") {
                $confirmation = Read-Host "Please type 'continue' when you've completed the WSL setup"
            }
            
            Write-Log "User confirmed WSL setup is complete."
            
            # Verify the setup
            $setupVerified = $false
            try {
                $result = wsl.exe -d $Distribution -e bash -c "echo 'SETUP_VERIFIED'" 2>$null
                if ($result -like "*SETUP_VERIFIED*") {
                    $setupVerified = $true
                    Write-Log "WSL setup verification successful."
                }
            } catch {
                $setupVerified = $false
            }
            
            if (-not $setupVerified) {
                Write-Log "WSL setup verification failed. Please ensure WSL is set up correctly." "ERROR"
                exit 1
            }
            
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to install distribution: $errorMessage" "ERROR"
            exit 1
        }
    }
    
    # Move to custom location if not already there
    if (-not $customDistroInstalled) {
        Write-Log "Moving WSL distribution to custom location..."
        
        # Shutdown WSL
        wsl.exe --shutdown
        
        # Export the distribution
        $tempTarFile = "$WslStorageDir\temp.tar"
        Write-Log "Exporting distribution to $tempTarFile..."
        wsl.exe --export $Distribution $tempTarFile
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to export distribution: $LASTEXITCODE" "ERROR"
            exit 1
        }
        
        # Unregister the original
        Write-Log "Unregistering original distribution..."
        wsl.exe --unregister $Distribution
        
        # Import to our custom location
        Write-Log "Importing distribution to $WslStorageDir..."
        wsl.exe --import $Distribution $WslStorageDir $tempTarFile --version 2
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to import distribution: $LASTEXITCODE" "ERROR"
            exit 1
        }
        
        # Clean up the tar file
        Remove-Item $tempTarFile -Force
        
        Write-Log "WSL distribution moved to custom location successfully."
    }
}

# Set up the user in WSL
Write-Log "Setting up user in WSL..."

# Check if user already exists
$userExists = wsl.exe -d $Distribution -e bash -c "id -u $WslUsername &>/dev/null && echo 'exists' || echo 'not exists'"

if ($userExists -eq "not exists") {
    Write-Log "Creating user '$WslUsername' in WSL..."
    
    # Create the user setup script
    $userSetupScript = @"
useradd -m -s /bin/bash $WslUsername
echo $WslUsername`:$WslPassword | chpasswd
usermod -aG sudo $WslUsername
echo "$WslUsername ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$WslUsername
chmod 0440 /etc/sudoers.d/$WslUsername
"@
    
    # Execute the user setup commands as root
    wsl.exe -d $Distribution -u root -e bash -c "$userSetupScript"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "User '$WslUsername' created successfully"
    } else {
        Write-Log "Failed to create user. Using existing user instead." "WARN"
    }
} else {
    Write-Log "User '$WslUsername' already exists"
}

# Set the default user for the distribution
Write-Log "Setting '$WslUsername' as default user..."

# Try WSL command first (for newer Windows versions)
try {
    wsl.exe --set-default-user $Distribution $WslUsername 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Default user set successfully using WSL command"
    } else {
        throw "WSL command failed"
    }
} catch {
    # Fall back to creating/updating wsl.conf
    Write-Log "Using configuration file method to set default user..."
    
    $wslConfContent = @"
[user]
default=$WslUsername
"@
    
    wsl.exe -d $Distribution -u root -e bash -c "echo '$wslConfContent' > /etc/wsl.conf"
    
    # Restart WSL distribution
    Write-Log "Restarting WSL distribution to apply changes..."
    wsl.exe --terminate $Distribution
    Start-Sleep -Seconds 3
}

# Install prerequisites and git in WSL
Write-Log "Installing prerequisites in WSL..."
Write-Log "Running: sudo apt-get update && sudo apt-get install -y git curl dos2unix build-essential"

# Use -q for quieter output and filter only important messages
wsl.exe -d $Distribution -u $WslUsername -e bash -c "sudo apt-get update -q && sudo apt-get install -y -q git curl dos2unix build-essential"

# Log a summary of what happened instead of the full verbose output
Write-Log "Prerequisites installation completed."
Write-Log "Installed packages: git, curl, dos2unix, build-essential"

# Define the WSL path for projects
$driveLetter = $ProjectsDir.Substring(0, 1).ToLower()
$wslProjectsPath = "/mnt/$driveLetter/$(($ProjectsDir.Substring(2)) -replace '\\','/')"
Write-Log "WSL Projects path: $wslProjectsPath"

# Create projects directory in WSL
Write-Log "Creating projects directory in WSL..."
wsl.exe -d $Distribution -u $WslUsername -e bash -c "mkdir -p $wslProjectsPath"

# Clone the DevEnv repository
Write-Log "Cloning DevEnv repository in WSL..."
$devenvExists = wsl.exe -d $Distribution -u $WslUsername -e bash -c "test -d ~/.devenv && echo 'exists' || echo 'not exists'"
if ($devenvExists -eq "not exists" -or $Force) {
    if ($Force) {
        wsl.exe -d $Distribution -u $WslUsername -e bash -c "rm -rf ~/.devenv"
    }
    wsl.exe -d $Distribution -u $WslUsername -e bash -c "git clone $DevEnvRepo ~/.devenv"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to clone DevEnv repository: $LASTEXITCODE" "ERROR"
        exit 1
    }
} else {
    Write-Log "DevEnv repository already exists, updating..."
    wsl.exe -d $Distribution -u $WslUsername -e bash -c "cd ~/.devenv && git pull"
}

# Fix permissions and line endings
Write-Log "Fixing permissions and line endings..."
wsl.exe -d $Distribution -u $WslUsername -e bash -c "cd ~/.devenv && find . -name '*.sh' -exec dos2unix {} \; && find . -name '*.sh' -exec chmod +x {} \;"

# Run the DevEnv installer with debugging
Write-Log "Running DevEnv installation..."
Write-Log "This may take a few minutes..."

# Run the installation, but filter the output
$installOutput = wsl.exe -d $Distribution -u $WslUsername -e bash -c "cd ~/.devenv && ./devenv.sh install 2>&1 | grep -E 'INFO|WARN|ERROR|Installing|Configuring|Complete'"
$installOutput | ForEach-Object { Write-Log $_ }

# Check installation result
if ($LASTEXITCODE -ne 0) {
    Write-Log "DevEnv installation completed with errors: $LASTEXITCODE" "ERROR"
} else {
    Write-Log "DevEnv installation completed successfully!"
}

# Launch Windows Terminal with WSL
Write-Log "Launching Windows Terminal with WSL..."
try {
    # Try to open Windows Terminal in the projects directory with WSL
    Start-Process wt.exe -ArgumentList "-d `"$ProjectsDir`" wsl.exe -d $Distribution" -NoNewWindow
} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Failed to launch Windows Terminal: $errorMessage" "WARN"
    Write-Log "Launching WSL directly..."
    wsl.exe -d $Distribution
}

Write-Log "DevEnv Windows installation completed!"