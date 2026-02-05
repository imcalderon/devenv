# reset-wsl.ps1 - Reset and provision AlmaLinux WSL for devenv
# Run from PowerShell as Administrator

param(
    [string]$DistroName = "AlmaLinux10",
    [string]$WslRoot = "",  # Where to store WSL (default: parent of this script's dir)
    [string]$ImagePath = "",  # Path to .wsl image file
    [string]$Username = "devuser",
    [string]$Password = "devenv",
    [string]$Timezone = "America/Chicago",
    [switch]$SkipDevenvClone,
    [switch]$FullSetup
)

# Auto-detect paths relative to script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Set defaults if not provided
if (-not $WslRoot) {
    $WslRoot = Split-Path -Parent $RepoRoot  # Parent of devenv repo
}
if (-not $ImagePath) {
    $ImagePath = Join-Path $WslRoot "AlmaLinux-10.1_x64.wsl"
}

$InstallPath = Join-Path $WslRoot $DistroName
$BootstrapScript = Join-Path $ScriptDir "bootstrap-wsl.sh"
$SetupScript = Join-Path $ScriptDir "setup-devenv.sh"

$ErrorActionPreference = "Stop"

Write-Host "=== WSL Reset Script ===" -ForegroundColor Cyan
Write-Host "Distro: $DistroName"
Write-Host "Install Path: $InstallPath"
Write-Host "Image: $ImagePath"
Write-Host ""

# Check if distro exists and unregister
$existing = wsl --list --quiet 2>$null | Where-Object { $_ -replace "`0", "" -eq $DistroName }
if ($existing) {
    Write-Host "Unregistering existing $DistroName..." -ForegroundColor Yellow
    wsl --unregister $DistroName
    Start-Sleep -Seconds 2
}

# Clean up install directory if it exists
if (Test-Path $InstallPath) {
    Write-Host "Cleaning up $InstallPath..." -ForegroundColor Yellow
    Remove-Item -Path $InstallPath -Recurse -Force
}

# Create install directory
Write-Host "Creating $InstallPath..." -ForegroundColor Green
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

# Import the WSL image
Write-Host "Importing $ImagePath..." -ForegroundColor Green
wsl --import $DistroName $InstallPath $ImagePath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to import WSL image"
}

Write-Host "Import complete. Starting bootstrap..." -ForegroundColor Green
Start-Sleep -Seconds 2

# Convert Windows path to WSL path for the bootstrap script
$WslBootstrapPath = "/mnt/" + ($BootstrapScript -replace "\\", "/" -replace ":", "").ToLower()
$WslBootstrapPath = $WslBootstrapPath -replace "/mnt/e/", "/mnt/e/"

Write-Host "Running bootstrap script: $WslBootstrapPath" -ForegroundColor Green
wsl -d $DistroName --user root -- bash $WslBootstrapPath $Username $Password $Timezone
if ($LASTEXITCODE -ne 0) {
    throw "Bootstrap script failed"
}

# Shutdown to apply wsl.conf
Write-Host "Shutting down WSL to apply configuration..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 3

if ($FullSetup) {
    Write-Host "Running full setup (devenv + Claude Code + gh CLI)..." -ForegroundColor Green

    $WslSetupPath = "/mnt/" + ($SetupScript -replace "\\", "/" -replace ":", "").ToLower()

    wsl -d $DistroName -- bash $WslSetupPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Full setup had errors, check output above" -ForegroundColor Yellow
    }
}
elseif (-not $SkipDevenvClone) {
    Write-Host "Starting $DistroName and cloning devenv..." -ForegroundColor Green

    # Clone devenv only (using single line to avoid CRLF issues)
    wsl -d $DistroName -- bash -c "set -e; echo '=== Cloning devenv ==='; git clone -b crossplatform https://github.com/imcalderon/devenv.git ~/devenv; echo ''; echo '=== DevEnv cloned to ~/devenv ==='; echo 'To install, run: cd ~/devenv && ./devenv install'"
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "To start: wsl -d $DistroName" -ForegroundColor White
if (-not $FullSetup) {
    Write-Host "To install devenv: cd ~/devenv && ./devenv install" -ForegroundColor White
    Write-Host "For full setup: .\reset-wsl.ps1 -FullSetup" -ForegroundColor White
}
else {
    Write-Host "To start Claude: claude" -ForegroundColor White
    Write-Host "To view issues: gh issue list --repo imcalderon/devenv" -ForegroundColor White
}
Write-Host ""
