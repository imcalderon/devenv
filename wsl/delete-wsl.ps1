# delete-wsl.ps1 - Cleanly destroy a WSL distribution
# Terminates, unregisters, and removes the disk image. No rebuild.
# Run from PowerShell as Administrator
#
# Usage:
#   .\delete-wsl.ps1                                    # Delete AlmaLinux10
#   .\delete-wsl.ps1 -DistroName "AlmaLinux10-test"     # Delete test distro
#   .\delete-wsl.ps1 -IncludeExports                    # Also remove backup exports
#   .\delete-wsl.ps1 -RemoveAll                         # Remove entire $WslRoot

param(
    [string]$DistroName = "AlmaLinux10",
    [string]$WslRoot = "",
    [switch]$IncludeExports,
    [switch]$RemoveAll,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# --- Path resolution ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $WslRoot) {
    $RepoRoot = Split-Path -Parent $ScriptDir
    $WslRoot = Join-Path (Split-Path -Parent $RepoRoot) "WSL\devenv"
}

$ImageDir = Join-Path $WslRoot "image"
$ExportsDir = Join-Path $WslRoot "exports"
$ConfigDir = Join-Path $WslRoot "config"
$DistroDir = Join-Path $WslRoot "distro"

# --- Display plan ---
Write-Host ""
Write-Host "=== WSL Delete ===" -ForegroundColor Cyan
Write-Host "  Distro:          $DistroName"
Write-Host "  WSL Root:        $WslRoot"
Write-Host "  Remove exports:  $IncludeExports"
Write-Host "  Remove all:      $RemoveAll"
Write-Host ""

# --- Confirmation ---
if (-not $Force) {
    $confirm = Read-Host "This will permanently destroy '$DistroName'. Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# --- Terminate running instances ---
Write-Host "Terminating $DistroName..." -ForegroundColor Yellow
try {
    wsl --terminate $DistroName 2>$null
    Start-Sleep -Seconds 2
} catch {
    Write-Host "  (Not running)" -ForegroundColor Gray
}

# --- Unregister the distro ---
$existing = wsl --list --quiet 2>$null | Where-Object { $_ -replace "`0", "" -eq $DistroName }
if ($existing) {
    Write-Host "Unregistering $DistroName..." -ForegroundColor Yellow
    wsl --unregister $DistroName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Unregister may have failed" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 2
    Write-Host "  Unregistered." -ForegroundColor Green
} else {
    Write-Host "Distro '$DistroName' is not registered (already removed or never installed)." -ForegroundColor Yellow
}

# --- Remove disk image directory ---
if (Test-Path $ImageDir) {
    Write-Host "Removing disk image: $ImageDir" -ForegroundColor Yellow
    Remove-Item -Path $ImageDir -Recurse -Force
    Write-Host "  Removed." -ForegroundColor Green
} else {
    Write-Host "Image directory not found: $ImageDir" -ForegroundColor Gray
}

# --- Optionally remove exports ---
if ($IncludeExports -or $RemoveAll) {
    if (Test-Path $ExportsDir) {
        Write-Host "Removing exports: $ExportsDir" -ForegroundColor Yellow
        Remove-Item -Path $ExportsDir -Recurse -Force
        Write-Host "  Removed." -ForegroundColor Green
    }
}

# --- Remove all (entire WslRoot) ---
if ($RemoveAll) {
    # Remove .wslconfig symlink from %USERPROFILE% if it points to our config
    $userWslConfig = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path $userWslConfig) {
        try {
            $item = Get-Item $userWslConfig -Force
            if ($item.LinkType -eq "SymbolicLink") {
                $target = $item.Target
                if ($target -like "$ConfigDir*") {
                    Remove-Item $userWslConfig -Force
                    Write-Host "Removed .wslconfig symlink: $userWslConfig" -ForegroundColor Yellow
                }
            }
        } catch {}
    }

    if (Test-Path $WslRoot) {
        Write-Host "Removing entire WSL root: $WslRoot" -ForegroundColor Yellow
        Remove-Item -Path $WslRoot -Recurse -Force
        Write-Host "  Removed." -ForegroundColor Green
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== Delete Complete ===" -ForegroundColor Cyan
Write-Host "  Distro '$DistroName' has been destroyed." -ForegroundColor Green
if (-not $RemoveAll) {
    Write-Host ""
    Write-Host "  Preserved:" -ForegroundColor Gray
    if (-not $IncludeExports -and (Test-Path $ExportsDir)) {
        Write-Host "    exports/  $ExportsDir" -ForegroundColor Gray
    }
    if (Test-Path $DistroDir) {
        Write-Host "    distro/   $DistroDir (source image for re-install)" -ForegroundColor Gray
    }
    if (Test-Path $ConfigDir) {
        Write-Host "    config/   $ConfigDir" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  To re-install: .\install-wsl.ps1 -WslRoot `"$WslRoot`"" -ForegroundColor White
    Write-Host "  To remove everything: .\delete-wsl.ps1 -RemoveAll" -ForegroundColor White
}
Write-Host ""
