# Install VS 2022 Build Tools with C++ workload and Windows 11 SDK
# Required for conda-build VFX pipeline (imath, OpenEXR, USD, etc.)
#
# Usage:
#   .\install_vs_buildtools.ps1            # Install with defaults
#   .\install_vs_buildtools.ps1 -Verify    # Check if already installed
#
# Installs:
#   - MSVC v143 compiler toolset (cl.exe, link.exe)
#   - Windows 11 SDK 10.0.26100 (headers, libs, UCRT)
#   - CMake and Ninja for Visual Studio (recommended)

param(
    [switch]$Verify
)

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

function Test-MsvcInstalled {
    if (-not (Test-Path $vsWhere)) { return $false }
    $install = & $vsWhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return -not [string]::IsNullOrEmpty($install)
}

function Test-WindowsSdkInstalled {
    $sdkKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
    if (-not (Test-Path $sdkKey)) { return $false }
    $roots = Get-ItemProperty $sdkKey -ErrorAction SilentlyContinue
    return $null -ne $roots -and $null -ne $roots.KitsRoot10
}

if ($Verify) {
    $msvc = Test-MsvcInstalled
    $sdk  = Test-WindowsSdkInstalled
    if ($msvc -and $sdk) {
        Write-Host "[OK] VS 2022 Build Tools with C++ workload and Windows SDK found." -ForegroundColor Green
        exit 0
    }
    if (-not $msvc) {
        Write-Host "[MISSING] MSVC compiler toolset (cl.exe) not found." -ForegroundColor Red
    }
    if (-not $sdk) {
        Write-Host "[MISSING] Windows 10/11 SDK not found in registry." -ForegroundColor Red
    }
    Write-Host "Run this script without -Verify to install." -ForegroundColor Yellow
    exit 1
}

if (Test-MsvcInstalled) {
    Write-Host "[OK] VS 2022 Build Tools C++ workload already installed." -ForegroundColor Green
    if (-not (Test-WindowsSdkInstalled)) {
        Write-Host "[WARN] Windows SDK not found - adding it now..." -ForegroundColor Yellow
    } else {
        Write-Host "Nothing to do." -ForegroundColor Gray
        exit 0
    }
}

Write-Host "Installing VS 2022 Build Tools (C++ workload + Windows 11 SDK)..." -ForegroundColor Cyan
Write-Host "This will take several minutes and requires internet access." -ForegroundColor Gray
Write-Host ""

$workloads = @(
    "Microsoft.VisualStudio.Workload.VCTools",
    "Microsoft.VisualStudio.Component.Windows11SDK.26100"
)
$overrideArgs = "--passive --wait --add " + ($workloads -join " --add ") + " --includeRecommended"

winget install Microsoft.VisualStudio.2022.BuildTools `
    --exact `
    --accept-package-agreements `
    --accept-source-agreements `
    --override $overrideArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: winget install failed (exit code $LASTEXITCODE)." -ForegroundColor Red
    Write-Host "Try running VS Installer manually and selecting:" -ForegroundColor Yellow
    Write-Host "  'Desktop development with C++' workload" -ForegroundColor Yellow
    Write-Host "  including 'Windows 11 SDK (10.0.26100.0)'" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Done. Verifying installation..." -ForegroundColor Cyan
if (Test-MsvcInstalled) {
    Write-Host "[OK] MSVC compiler toolset installed." -ForegroundColor Green
} else {
    Write-Host "[WARN] MSVC may need a restart to be detected. Try rebooting." -ForegroundColor Yellow
}
if (Test-WindowsSdkInstalled) {
    Write-Host "[OK] Windows SDK found." -ForegroundColor Green
} else {
    Write-Host "[WARN] Windows SDK registry entry not found yet. Try rebooting." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "You may need to restart your terminal before running build_vfx.ps1." -ForegroundColor Cyan
