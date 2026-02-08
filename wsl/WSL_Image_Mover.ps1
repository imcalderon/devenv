# WSL_Image_Mover.ps1 - Relocate an existing WSL distribution to $WslRoot/image/
# Exports, unregisters, and re-imports at the new location
# Run from PowerShell as Administrator
#
# Usage:
#   .\WSL_Image_Mover.ps1 -DistributionName "AlmaLinux10"
#   .\WSL_Image_Mover.ps1 -DistributionName "AlmaLinux10" -WslRoot "E:\WSL\devenv"

param (
    [Parameter(Mandatory=$true)]
    [string]$DistributionName,

    [string]$WslRoot = "",
    [switch]$Force
)

# Ensure script is running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Stop"

# --- Path resolution ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $WslRoot) {
    $RepoRoot = Split-Path -Parent $ScriptDir
    $WslRoot = Join-Path (Split-Path -Parent $RepoRoot) "WSL\devenv"
}

$ImageDir = Join-Path $WslRoot "image"
$ExportsDir = Join-Path $WslRoot "exports"

# --- Check if the distribution exists ---
Write-Host ""
Write-Host "=== WSL Image Mover ===" -ForegroundColor Cyan

$existing = wsl --list --quiet 2>$null | Where-Object { $_ -replace "`0", "" -eq $DistributionName }
if (-not $existing) {
    Write-Host "ERROR: Distribution '$DistributionName' is not registered." -ForegroundColor Red
    exit 1
}

# Get current location from registry
$currentLocation = $null
try {
    $lxssKeys = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction Stop
    foreach ($key in $lxssKeys) {
        $distroName = Get-ItemProperty -Path $key.PSPath -Name DistributionName -ErrorAction SilentlyContinue
        if ($distroName -and $distroName.DistributionName -eq $DistributionName) {
            $basePath = Get-ItemProperty -Path $key.PSPath -Name BasePath -ErrorAction SilentlyContinue
            if ($basePath) {
                $currentLocation = $basePath.BasePath -replace '^\\\\\?\\',''
            }
            break
        }
    }
} catch {
    Write-Host "ERROR: Could not read registry: $_" -ForegroundColor Red
    exit 1
}

if (-not $currentLocation) {
    Write-Host "ERROR: Could not determine current location of the distribution." -ForegroundColor Red
    exit 1
}

Write-Host "  Distribution:     $DistributionName"
Write-Host "  Current location: $currentLocation"
Write-Host "  New location:     $ImageDir"
Write-Host ""

if ($currentLocation -eq $ImageDir) {
    Write-Host "Distribution is already at the target location." -ForegroundColor Green
    exit 0
}

# --- Confirmation ---
if (-not $Force) {
    $confirm = Read-Host "Move '$DistributionName' to $ImageDir? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# --- Create directory structure ---
foreach ($dir in @($ImageDir, $ExportsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# --- Export ---
$tempTarFile = Join-Path $ExportsDir "temp_move_$DistributionName.tar"
Write-Host "Shutting down WSL..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 5

Write-Host "Exporting distribution (this may take several minutes)..." -ForegroundColor Green
wsl --export $DistributionName $tempTarFile
if (-not (Test-Path $tempTarFile)) {
    Write-Host "ERROR: Failed to create export file." -ForegroundColor Red
    exit 1
}
$size = (Get-Item $tempTarFile).Length / 1MB
Write-Host "  Exported: $([math]::Round($size, 1)) MB" -ForegroundColor Green

# --- Unregister ---
Write-Host "Unregistering distribution..." -ForegroundColor Yellow
wsl --unregister $DistributionName
Start-Sleep -Seconds 5

# --- Re-import at new location ---
if (Test-Path $ImageDir) {
    # Clean existing content but keep the directory
    Get-ChildItem $ImageDir | Remove-Item -Recurse -Force
}

Write-Host "Importing to new location..." -ForegroundColor Green
wsl --import $DistributionName $ImageDir $tempTarFile --version 2
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Import failed. Your tar export is at: $tempTarFile" -ForegroundColor Red
    Write-Host "  Recover with: wsl --import $DistributionName $ImageDir $tempTarFile --version 2" -ForegroundColor Yellow
    exit 1
}

# --- Cleanup temp file ---
Write-Host "Removing temporary export file..." -ForegroundColor Yellow
Remove-Item -Path $tempTarFile -Force -ErrorAction SilentlyContinue

# --- Verify ---
Write-Host "Verifying..." -ForegroundColor Green
$testResult = wsl -d $DistributionName -e bash -c "echo 'OK'"
if ($testResult -like "*OK*") {
    Write-Host "  Distribution is working correctly." -ForegroundColor Green
} else {
    Write-Host "  WARNING: Distribution may not be working correctly." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Move Complete ===" -ForegroundColor Cyan
Write-Host "  From: $currentLocation" -ForegroundColor White
Write-Host "  To:   $ImageDir" -ForegroundColor White
Write-Host ""
