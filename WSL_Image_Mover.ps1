# WSL Image Mover
# This script moves an existing WSL distribution to a custom location

param (
    [Parameter(Mandatory=$true)]
    [string]$DistributionName,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath,
    
    [switch]$Force = $false,
    
    [switch]$DeleteOriginal = $true
)

# Ensure script is running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Please restart as Administrator." -ForegroundColor Red
    exit 1
}

# Function to log messages
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(
        switch ($Level) {
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            "INFO" { "Green" }
            default { "White" }
        }
    )
}

# Check if the distribution exists
Write-Log "Checking if distribution '$DistributionName' exists..." "INFO"
$distroExists = $false
$currentLocation = $null
$registryKey = $null

try {
    $lxssKeys = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction Stop
    foreach ($key in $lxssKeys) {
        $distroName = Get-ItemProperty -Path $key.PSPath -Name DistributionName -ErrorAction SilentlyContinue
        if ($distroName -and $distroName.DistributionName -eq $DistributionName) {
            $distroExists = $true
            $registryKey = $key.PSPath
            Write-Log "Distribution found: $DistributionName" "INFO"
            
            # Get the BasePath while we're here since we'll need it later
            $basePath = Get-ItemProperty -Path $key.PSPath -Name BasePath -ErrorAction SilentlyContinue
            if ($basePath) {
                $currentLocation = $basePath.BasePath -replace '^\\\\\?\\',''
                Write-Log "Current location: $currentLocation" "INFO"
            }
            
            break
        }
    }
    
    if (-not $distroExists) {
        Write-Log "Distribution not found: $DistributionName" "ERROR"
        exit 1
    }
} catch {
    Write-Log "Error checking for distribution: $_" "ERROR"
    exit 1
}

if (-not $currentLocation) {
    Write-Log "Could not determine current location of the distribution" "ERROR"
    exit 1
}

# Check if destination path exists, create if not
if (-not (Test-Path $DestinationPath)) {
    Write-Log "Destination path does not exist, creating..." "INFO"
    try {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    } catch {
        Write-Log "Error creating destination path: $_" "ERROR"
        exit 1
    }
}

# Prepare full destination path
$destinationDir = Join-Path $DestinationPath $DistributionName
if (Test-Path $destinationDir) {
    if ($Force) {
        Write-Log "Destination directory exists, removing due to -Force option..." "WARN"
        try {
            Remove-Item -Path $destinationDir -Recurse -Force
        } catch {
            Write-Log "Error removing existing destination directory: $_" "ERROR"
            exit 1
        }
    } else {
        Write-Log "Destination directory already exists: $destinationDir" "ERROR"
        Write-Log "Use -Force to overwrite" "ERROR"
        exit 1
    }
}

# Create the destination directory
try {
    New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
} catch {
    Write-Log "Error creating destination directory: $_" "ERROR"
    exit 1
}

# Create a temporary file path for the tar archive
$tempTarFile = Join-Path $DestinationPath "temp_$DistributionName.tar"
Write-Log "Temporary tar file will be: $tempTarFile" "INFO"

# Shutdown all WSL instances
Write-Log "Shutting down all WSL instances..." "INFO"
wsl --shutdown
Start-Sleep -Seconds 5

# Export the distribution
Write-Log "Exporting distribution to tar file (this may take several minutes)..." "INFO"
try {
    wsl --export $DistributionName $tempTarFile
    if (-not (Test-Path $tempTarFile)) {
        Write-Log "Failed to create tar file" "ERROR"
        exit 1
    }
} catch {
    Write-Log "Error exporting distribution: $_" "ERROR"
    exit 1
}

# Unregister the distribution
Write-Log "Unregistering original distribution..." "INFO"
try {
    $unregisterOutput = wsl --unregister $DistributionName 2>&1
    Write-Log "Unregister output: $unregisterOutput" "INFO"
    # Give the system time to fully process the unregister
    Start-Sleep -Seconds 10
} catch {
    Write-Log "Error unregistering distribution: $_" "ERROR"
    Write-Log "Waiting additional time before continuing..." "WARN"
    Start-Sleep -Seconds 15
}

# Verify the distribution is actually unregistered
$stillExists = $false
try {
    $lxssKeys = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction Stop
    foreach ($key in $lxssKeys) {
        $distroName = Get-ItemProperty -Path $key.PSPath -Name DistributionName -ErrorAction SilentlyContinue
        if ($distroName -and $distroName.DistributionName -eq $DistributionName) {
            $stillExists = $true
            Write-Log "WARNING: Distribution still exists in registry after unregister command!" "WARN"
            break
        }
    }
} catch {
    Write-Log "Error verifying unregistration: $_" "WARN"
}

if ($stillExists) {
    Write-Log "Attempting to force remove registry key..." "WARN"
    try {
        Remove-Item -Path $registryKey -Recurse -Force
        Start-Sleep -Seconds 5
    } catch {
        Write-Log "Error removing registry key: $_" "ERROR"
        Write-Log "This may cause problems with import. Continuing anyway..." "WARN"
    }
}

# Import the distribution to the new location
Write-Log "Importing distribution to new location..." "INFO"
try {
    wsl --import $DistributionName $destinationDir $tempTarFile --version 2
} catch {
    Write-Log "Error importing distribution: $_" "ERROR"
    Write-Log "The original distribution has been unregistered but failed to import" "ERROR"
    Write-Log "You can try manually importing with: wsl --import $DistributionName $destinationDir $tempTarFile --version 2" "INFO"
    exit 1
}

# Verify the import using registry
Write-Log "Verifying the import..." "INFO"
$importVerified = $false
$newLocation = $null
try {
    Start-Sleep -Seconds 5  # Give the system a moment to update
    $lxssKeys = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction Stop
    foreach ($key in $lxssKeys) {
        $distroName = Get-ItemProperty -Path $key.PSPath -Name DistributionName -ErrorAction SilentlyContinue
        if ($distroName -and $distroName.DistributionName -eq $DistributionName) {
            $importVerified = $true
            $basePath = Get-ItemProperty -Path $key.PSPath -Name BasePath -ErrorAction SilentlyContinue
            if ($basePath) {
                $newLocation = $basePath.BasePath -replace '^\\\\\?\\',''
                Write-Log "New location: $newLocation" "INFO"
            }
            break
        }
    }
    
    if (-not $importVerified) {
        Write-Log "Failed to verify imported distribution in registry" "ERROR"
        Write-Log "You can try manually importing with: wsl --import $DistributionName $destinationDir $tempTarFile --version 2" "INFO"
        exit 1
    }
} catch {
    Write-Log "Error verifying import: $_" "ERROR"
    exit 1
}

# Clean up temporary files
if (Test-Path $tempTarFile) {
    Write-Log "Removing temporary tar file..." "INFO"
    try {
        Remove-Item -Path $tempTarFile -Force
    } catch {
        Write-Log "Warning: Failed to remove temporary tar file: $_" "WARN"
        Write-Log "You can remove it manually: $tempTarFile" "WARN"
    }
}

# Delete original location if specified and successful
if ($DeleteOriginal -and $currentLocation -and $newLocation -and $importVerified) {
    Write-Log "Deleting original image location: $currentLocation" "INFO"
    try {
        if (Test-Path $currentLocation) {
            # Check if it's a directory and not the same as the new location
            if ((Get-Item $currentLocation) -is [System.IO.DirectoryInfo] -and 
                ($currentLocation -ne $newLocation)) {
                Remove-Item -Path $currentLocation -Recurse -Force
                Write-Log "Original image location deleted successfully" "INFO"
            } else {
                Write-Log "Original location is not a directory or is the same as new location, skipping deletion" "WARN"
            }
        } else {
            Write-Log "Original location no longer exists, nothing to delete" "INFO"
        }
    } catch {
        Write-Log "Error deleting original location: $_" "WARN"
        Write-Log "You can delete it manually: $currentLocation" "WARN"
    }
}

# Show results
Write-Log "WSL Image Move Operation Complete" "INFO"
Write-Log "Distribution: $DistributionName" "INFO"
Write-Log "Original Location: $currentLocation" "INFO"
Write-Log "New Location: $newLocation" "INFO"

# Test the distribution
Write-Log "Testing the distribution..." "INFO"
try {
    $testResult = wsl -d $DistributionName -e bash -c "echo 'WSL Test Successful'"
    if ($testResult -like "*WSL Test Successful*") {
        Write-Log "Distribution is working correctly" "INFO"
    } else {
        Write-Log "Warning: Distribution might not be working correctly" "WARN"
    }
} catch {
    Write-Log "Error testing distribution: $_" "ERROR"
}

# Get the default user
$defaultUser = $null
try {
    $wslConf = wsl -d $DistributionName -e bash -c "cat /etc/wsl.conf 2>/dev/null | grep -A 1 '\[user\]' | grep 'default=' | cut -d= -f2"
    if ($wslConf) {
        $defaultUser = $wslConf.Trim()
        Write-Log "Default user is set to: $defaultUser" "INFO"
    } else {
        Write-Log "Could not determine default user from wsl.conf" "WARN"
    }
} catch {
    Write-Log "Error getting default user: $_" "WARN"
}

Write-Log "Migration completed successfully" "INFO"