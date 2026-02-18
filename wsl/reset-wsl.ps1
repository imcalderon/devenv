# reset-wsl.ps1 - Reset WSL distro to clean state from existing source image
# Unregisters current distro and re-imports from $WslRoot/distro/
# Does NOT run bootstrap unless --Bootstrap is specified
# Run from PowerShell as Administrator
#
# Usage:
#   .\reset-wsl.ps1                          # Reset only (no bootstrap)
#   .\reset-wsl.ps1 -Bootstrap               # Reset + run bootstrap
#   .\reset-wsl.ps1 -Export                   # Export backup before reset
#   .\reset-wsl.ps1 -Bootstrap -Export        # Export, reset, bootstrap

param(
    [string]$DistroName = "AlmaLinux10",
    [string]$WslRoot = "",
    [string]$ImageFile = "",
    [string]$Username = "devuser",
    [string]$Password = "devenv",
    [string]$Timezone = "America/Chicago",
    [switch]$Bootstrap,
    [switch]$Export,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# --- Path resolution ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Load secrets.local if present (provides defaults for unset params) ---
$RepoRoot = Split-Path -Parent $ScriptDir
$SecretsFile = Join-Path $RepoRoot "secrets.local"
if (Test-Path $SecretsFile) {
    Write-Host "Loading defaults from secrets.local..." -ForegroundColor Gray
    Get-Content $SecretsFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                $val = $parts[1].Trim().Trim('"').Trim("'")
                if ($val) {
                    switch ($key) {
                        "WSL_USERNAME"     { if ($Username -eq "devuser")           { $Username = $val } }
                        "WSL_PASSWORD"     { if ($Password -eq "devenv")            { $Password = $val } }
                        "WSL_TIMEZONE"     { if ($Timezone -eq "America/Chicago")   { $Timezone = $val } }
                    }
                }
            }
        }
    }
}

if (-not $WslRoot) {
    $WslRoot = Join-Path (Split-Path -Parent $RepoRoot) "WSL\devenv"
}

$ImageDir = Join-Path $WslRoot "image"
$DistroDir = Join-Path $WslRoot "distro"
$ExportsDir = Join-Path $WslRoot "exports"
$BootstrapScript = Join-Path $ScriptDir "bootstrap-wsl.sh"

# Find source image
if (-not $ImageFile) {
    # Look for .wsl files in distro directory
    $images = Get-ChildItem -Path $DistroDir -Filter "*.wsl" -ErrorAction SilentlyContinue
    if ($images) {
        $ImageFile = $images[0].FullName
    } else {
        Write-Host "ERROR: No .wsl image found in $DistroDir" -ForegroundColor Red
        Write-Host "  Run install-wsl.ps1 first, or specify -ImageFile" -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path $ImageFile)) {
    Write-Host "ERROR: Image file not found: $ImageFile" -ForegroundColor Red
    exit 1
}

# --- Display plan ---
Write-Host ""
Write-Host "=== WSL Reset ===" -ForegroundColor Cyan
Write-Host "  Distro:      $DistroName"
Write-Host "  Image:       $ImageFile"
Write-Host "  Disk:        $ImageDir"
Write-Host "  Bootstrap:   $Bootstrap"
Write-Host "  Export:       $Export"
Write-Host ""

# --- Confirmation ---
if (-not $Force) {
    $confirm = Read-Host "This will destroy and recreate '$DistroName'. Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# --- Export backup if requested ---
if ($Export) {
    $existing = wsl --list --quiet 2>$null | Where-Object { $_ -replace "`0", "" -eq $DistroName }
    if ($existing) {
        if (-not (Test-Path $ExportsDir)) {
            New-Item -ItemType Directory -Path $ExportsDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $exportFile = Join-Path $ExportsDir "$DistroName-$timestamp.tar"
        Write-Host "Exporting backup to: $exportFile" -ForegroundColor Green
        Write-Host "  (This may take several minutes)" -ForegroundColor Yellow
        wsl --export $DistroName $exportFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Export failed. Continuing with reset..." -ForegroundColor Yellow
        } else {
            $size = (Get-Item $exportFile).Length / 1MB
            Write-Host "  Exported: $([math]::Round($size, 1)) MB" -ForegroundColor Green
        }
    } else {
        Write-Host "No existing distro to export." -ForegroundColor Yellow
    }
}

# --- Terminate and unregister ---
$existing = wsl --list --quiet 2>$null | Where-Object { $_ -replace "`0", "" -eq $DistroName }
if ($existing) {
    Write-Host "Terminating $DistroName..." -ForegroundColor Yellow
    wsl --terminate $DistroName 2>$null
    Start-Sleep -Seconds 2

    Write-Host "Unregistering $DistroName..." -ForegroundColor Yellow
    wsl --unregister $DistroName
    Start-Sleep -Seconds 2
}

# --- Clean up image directory ---
if (Test-Path $ImageDir) {
    Write-Host "Cleaning up $ImageDir..." -ForegroundColor Yellow
    Remove-Item -Path $ImageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ImageDir -Force | Out-Null

# --- Re-import ---
Write-Host "Importing $DistroName from source image..." -ForegroundColor Green
wsl --import $DistroName $ImageDir $ImageFile
if ($LASTEXITCODE -ne 0) {
    throw "Failed to import WSL image"
}
Write-Host "  Import complete." -ForegroundColor Green
Start-Sleep -Seconds 2

# --- Bootstrap (only if flag set) ---
if ($Bootstrap) {
    if (-not (Test-Path $BootstrapScript)) {
        Write-Host "WARNING: Bootstrap script not found: $BootstrapScript" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Running bootstrap script..." -ForegroundColor Green

        $WslBootstrapPath = "/mnt/" + ($BootstrapScript -replace "\\", "/" -replace ":", "").ToLower()

        # Pass secrets.local path as 4th arg if it exists
        $WslSecretsArg = ""
        if (Test-Path $SecretsFile) {
            $WslSecretsArg = "/mnt/" + ($SecretsFile -replace "\\", "/" -replace ":", "").ToLower()
        }
        wsl -d $DistroName --user root -- bash $WslBootstrapPath $Username $Password $Timezone $WslSecretsArg
        if ($LASTEXITCODE -ne 0) {
            throw "Bootstrap script failed"
        }

        # Shutdown to apply wsl.conf
        Write-Host "Shutting down WSL to apply configuration..." -ForegroundColor Yellow
        wsl --shutdown
        Start-Sleep -Seconds 3

        Write-Host "Bootstrap complete." -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Skipping bootstrap (use -Bootstrap to run it)" -ForegroundColor Yellow
}

# --- Summary ---
Write-Host ""
Write-Host "=== Reset Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Start WSL:  wsl -d $DistroName" -ForegroundColor White
if ($Bootstrap) {
    Write-Host "  User:       $Username" -ForegroundColor White
} else {
    Write-Host "  NOTE: No user configured. Log in as root or run bootstrap:" -ForegroundColor Yellow
    Write-Host "    .\reset-wsl.ps1 -Bootstrap" -ForegroundColor White
}
Write-Host ""
