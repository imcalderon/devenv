# VFX Platform build script (Windows)
# Wraps the vfx-bootstrap Python builder with conda run --live-stream
# to avoid output buffering.
#
# Usage:
#   .\build_vfx.ps1 <package>            Build a single package
#   .\build_vfx.ps1 <package> -NoCache   Build without cache
#   .\build_vfx.ps1 -All                 Build entire pipeline
#   .\build_vfx.ps1 -List                List available recipes
#   .\build_vfx.ps1 -Order               Show build order

param(
    [Parameter(Position = 0)]
    [string]$Package,

    [Alias("a")][switch]$All,
    [Alias("l")][switch]$List,
    [Alias("o")][switch]$Order,
    [switch]$NoCache,
    [switch]$ContinueOnError,
    [string]$CondaEnv = "vfx-build"
)

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
$env:CONDA_REPORT_ERRORS = "false"

# Derive paths relative to this script's location in devenv/scripts/
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$devenvRoot = Split-Path -Parent $scriptDir
$condaExe = Join-Path $env:USERPROFILE "miniconda3\Scripts\conda.exe"
$builderDir = Join-Path $devenvRoot "toolkits\vfx-bootstrap"
$vfxRoot = Join-Path $env:USERPROFILE "Development\vfx"
$outputDir = Join-Path $vfxRoot "builds"
$channelDir = Join-Path $vfxRoot "channel"

if (-not (Test-Path $condaExe)) {
    Write-Host "ERROR: conda not found at $condaExe" -ForegroundColor Red
    exit 1
}

# Build the CLI arguments
$cliArgs = @(
    "-m", "builder.cli",
    "--output", $outputDir,
    "--channel-dir", $channelDir
)

if ($List) {
    $cliArgs += "list", "--verbose"
} elseif ($Order) {
    $cliArgs += "order"
} elseif ($All) {
    $cliArgs += "build", "--verbose"
    if ($NoCache) { $cliArgs += "--no-cache" }
    if ($ContinueOnError) { $cliArgs += "--continue-on-error" }
} elseif ($Package) {
    $cliArgs += "build", $Package, "--verbose"
    if ($NoCache) { $cliArgs += "--no-cache" }
} else {
    Write-Host "VFX Platform Build Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\build_vfx.ps1 <package>            Build a single package"
    Write-Host "  .\build_vfx.ps1 -All                 Build entire pipeline"
    Write-Host "  .\build_vfx.ps1 -List                List available recipes"
    Write-Host "  .\build_vfx.ps1 -Order               Show build order"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -NoCache                              Skip build cache"
    Write-Host "  -ContinueOnError                      Don't stop on first failure"
    Write-Host "  -CondaEnv <name>                      Conda environment (default: vfx-build)"
    exit 0
}

# Clean leftover conda-build work dirs for the target package
if ($Package) {
    $condaBld = Join-Path $env:USERPROFILE "miniconda3\envs\$CondaEnv\conda-bld"
    Get-ChildItem "$condaBld\${Package}_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Removing stale: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$ErrorActionPreference = 'Continue'

& $condaExe run --live-stream -n $CondaEnv --cwd $builderDir python @cliArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`nDone." -ForegroundColor Green
