# install-wsl.ps1 - First-time AlmaLinux 10 WSL setup
# Downloads image, imports distro, generates .wslconfig, runs bootstrap
# Run from PowerShell as Administrator
#
# Usage:
#   .\install-wsl.ps1
#   .\install-wsl.ps1 -WslRoot "E:\WSL\devenv" -Memory "16GB"
#   .\install-wsl.ps1 -DistroName "AlmaLinux10-test" -SkipBootstrap

param(
    [string]$DistroName = "AlmaLinux10",
    [string]$WslRoot = "",
    [string]$Memory = "8GB",
    [string]$Swap = "4GB",
    [int]$Processors = 4,
    [string]$Username = "devuser",
    [string]$Password = "devenv",
    [string]$Timezone = "America/Chicago",
    [string]$ImageUrl = "https://github.com/AlmaLinux/wsl-images/releases/download/10.1-20250127/AlmaLinux-10.1_x64.wsl",
    [switch]$SkipBootstrap,
    [switch]$SkipWslConfig
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
                        "WSL_MEMORY"       { if ($Memory -eq "8GB")                 { $Memory = $val } }
                        "WSL_SWAP"         { if ($Swap -eq "4GB")                   { $Swap = $val } }
                        "WSL_PROCESSORS"   { if ($Processors -eq 4)                 { $Processors = [int]$val } }
                    }
                }
            }
        }
    }
}

if (-not $WslRoot) {
    # Default: parent of repo root (keeps WSL data alongside devenv)
    $WslRoot = Join-Path (Split-Path -Parent $RepoRoot) "WSL\devenv"
}

# Contained directory structure under $WslRoot
$ImageDir = Join-Path $WslRoot "image"
$DistroDir = Join-Path $WslRoot "distro"
$ConfigDir = Join-Path $WslRoot "config"
$ExportsDir = Join-Path $WslRoot "exports"

$ImageFilename = Split-Path -Leaf $ImageUrl
$ImagePath = Join-Path $DistroDir $ImageFilename
$BootstrapScript = Join-Path $ScriptDir "bootstrap-wsl.sh"

# --- Display plan ---
Write-Host ""
Write-Host "=== WSL Install ===" -ForegroundColor Cyan
Write-Host "  Distro:       $DistroName"
Write-Host "  WSL Root:     $WslRoot"
Write-Host "  Image Dir:    $ImageDir"
Write-Host "  Memory:       $Memory"
Write-Host "  Swap:         $Swap"
Write-Host "  Processors:   $Processors"
Write-Host "  Username:     $Username"
Write-Host "  Bootstrap:    $(-not $SkipBootstrap)"
Write-Host ""

# --- Check if distro already exists ---
$existing = wsl --list --quiet 2>$null | Where-Object { $_ -replace "`0", "" -eq $DistroName }
if ($existing) {
    Write-Host "ERROR: Distro '$DistroName' already exists." -ForegroundColor Red
    Write-Host "  Use reset-wsl.ps1 to reset it, or delete-wsl.ps1 to remove it first." -ForegroundColor Yellow
    exit 1
}

# --- Create directory structure ---
Write-Host "Creating directory structure under $WslRoot..." -ForegroundColor Green
foreach ($dir in @($ImageDir, $DistroDir, $ConfigDir, $ExportsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  Created: $dir"
    } else {
        Write-Host "  Exists:  $dir"
    }
}

# --- Download image if not present ---
if (-not (Test-Path $ImagePath)) {
    Write-Host ""
    Write-Host "Downloading AlmaLinux 10 image..." -ForegroundColor Green
    Write-Host "  URL: $ImageUrl"
    Write-Host "  To:  $ImagePath"
    Write-Host "  (This may take a few minutes)" -ForegroundColor Yellow

    try {
        $ProgressPreference = 'SilentlyContinue'  # Speed up Invoke-WebRequest
        Invoke-WebRequest -Uri $ImageUrl -OutFile $ImagePath -UseBasicParsing
        $ProgressPreference = 'Continue'
    } catch {
        Write-Host "ERROR: Failed to download image: $_" -ForegroundColor Red
        Write-Host "  You can manually download from: $ImageUrl" -ForegroundColor Yellow
        Write-Host "  Place the file at: $ImagePath" -ForegroundColor Yellow
        exit 1
    }

    $size = (Get-Item $ImagePath).Length / 1MB
    Write-Host "  Downloaded: $([math]::Round($size, 1)) MB" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Image already exists: $ImagePath" -ForegroundColor Green
}

# --- Import the WSL distro ---
Write-Host ""
Write-Host "Importing WSL distro '$DistroName'..." -ForegroundColor Green
Write-Host "  Image:  $ImagePath"
Write-Host "  Disk:   $ImageDir"

wsl --import $DistroName $ImageDir $ImagePath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to import WSL image"
}
Write-Host "  Import complete." -ForegroundColor Green
Start-Sleep -Seconds 2

# --- Generate .wslconfig ---
if (-not $SkipWslConfig) {
    Write-Host ""
    Write-Host "Generating .wslconfig..." -ForegroundColor Green

    $wslConfig = @"
# Generated by devenv install-wsl.ps1
# WSL2 global settings for $DistroName

[wsl2]
memory=$Memory
swap=$Swap
processors=$Processors

[experimental]
autoMemoryReclaim=gradual
"@

    $wslConfigPath = Join-Path $ConfigDir ".wslconfig"
    Set-Content -Path $wslConfigPath -Value $wslConfig -Encoding UTF8
    Write-Host "  Saved to: $wslConfigPath"

    # Symlink to %USERPROFILE%\.wslconfig
    $userWslConfig = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path $userWslConfig) {
        $existingTarget = $null
        try {
            $item = Get-Item $userWslConfig -Force
            if ($item.LinkType -eq "SymbolicLink") {
                $existingTarget = $item.Target
            }
        } catch {}

        if ($existingTarget -eq $wslConfigPath) {
            Write-Host "  Symlink already exists: $userWslConfig -> $wslConfigPath"
        } else {
            # Backup existing .wslconfig
            $backup = "$userWslConfig.backup"
            Copy-Item $userWslConfig $backup -Force
            Write-Host "  Backed up existing .wslconfig to: $backup" -ForegroundColor Yellow
            Remove-Item $userWslConfig -Force
            New-Item -ItemType SymbolicLink -Path $userWslConfig -Target $wslConfigPath | Out-Null
            Write-Host "  Symlinked: $userWslConfig -> $wslConfigPath"
        }
    } else {
        New-Item -ItemType SymbolicLink -Path $userWslConfig -Target $wslConfigPath | Out-Null
        Write-Host "  Symlinked: $userWslConfig -> $wslConfigPath"
    }
} else {
    Write-Host ""
    Write-Host "Skipping .wslconfig generation (--SkipWslConfig)" -ForegroundColor Yellow
}

# --- Run bootstrap ---
if (-not $SkipBootstrap) {
    if (-not (Test-Path $BootstrapScript)) {
        Write-Host "WARNING: Bootstrap script not found: $BootstrapScript" -ForegroundColor Yellow
        Write-Host "  Skipping bootstrap. Run it manually later." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Running bootstrap script..." -ForegroundColor Green

        # Convert Windows path to WSL path
        $WslBootstrapPath = "/mnt/" + ($BootstrapScript -replace "\\", "/" -replace ":", "").ToLower()

        Write-Host "  Script: $WslBootstrapPath"
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
    Write-Host "Skipping bootstrap (--SkipBootstrap)" -ForegroundColor Yellow
    Write-Host "  Run manually: wsl -d $DistroName --user root -- bash <path>/bootstrap-wsl.sh" -ForegroundColor Yellow
}

# --- Summary ---
Write-Host ""
Write-Host "=== Install Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  WSL Root:    $WslRoot" -ForegroundColor White
Write-Host "    image/     Disk image (ext4.vhdx)" -ForegroundColor Gray
Write-Host "    distro/    Source image ($ImageFilename)" -ForegroundColor Gray
Write-Host "    config/    .wslconfig" -ForegroundColor Gray
Write-Host "    exports/   Backup exports" -ForegroundColor Gray
Write-Host ""
Write-Host "  Start WSL:   wsl -d $DistroName" -ForegroundColor White
if (-not $SkipBootstrap) {
    Write-Host "  User:        $Username (password: $Password - change with 'passwd')" -ForegroundColor White
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. wsl -d $DistroName" -ForegroundColor White
Write-Host "  2. Run setup-devenv.sh for full environment setup" -ForegroundColor White
Write-Host "  3. gh auth login     # GitHub authentication" -ForegroundColor White
Write-Host "  4. claude            # Claude Code setup" -ForegroundColor White
Write-Host ""
