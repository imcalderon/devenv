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
#   .\build_vfx.ps1 -Clean               Clean all conda-build work dirs
#   .\build_vfx.ps1 -Clean <package>     Clean work dirs for a specific package

param(
    [Parameter(Position = 0)]
    [string]$Package,

    [Alias("a")][switch]$All,
    [Alias("l")][switch]$List,
    [Alias("o")][switch]$Order,
    [Alias("c")][switch]$Clean,
    [switch]$NoCache,
    [switch]$ContinueOnError,
    [string]$CondaEnv = "vfx-build"
)

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
$env:CONDA_REPORT_ERRORS = "false"
# Suppress VS copyright banner in vcvarsall.bat to prevent cmd.exe parsing errors.
# The "(c)" in "Copyright (c) 2025 Microsoft" breaks if/else blocks in
# conda's vs2022_compiler_vars.bat activation script.
$env:__VSCMD_ARG_NO_LOGO = "1"

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

if ($Clean) {
    $condaBld = Join-Path $env:USERPROFILE "miniconda3\envs\$CondaEnv\conda-bld"
    $broken = Join-Path $condaBld "broken"
    if ($Package) {
        $pattern = "${Package}_*"
        $dirs = Get-ChildItem "$condaBld\$pattern" -Directory -ErrorAction SilentlyContinue
        if ($dirs) {
            $dirs | ForEach-Object {
                Write-Host "Removing: $($_.Name)" -ForegroundColor Yellow
                Remove-Item $_.FullName -Recurse -Force
            }
            Write-Host "Cleaned $($dirs.Count) work dir(s) for $Package" -ForegroundColor Green
        } else {
            Write-Host "No work dirs found for $Package" -ForegroundColor Gray
        }
    } else {
        # Clean all work dirs, broken dir, and src_cache
        $workDirs = Get-ChildItem $condaBld -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "src_cache" }
        if ($workDirs) {
            $workDirs | ForEach-Object {
                Write-Host "Removing: $($_.Name)" -ForegroundColor Yellow
                Remove-Item $_.FullName -Recurse -Force
            }
            Write-Host "Cleaned $($workDirs.Count) dir(s)" -ForegroundColor Green
        } else {
            Write-Host "Nothing to clean" -ForegroundColor Gray
        }
    }
    # Also clean stale user-config.jam from boost builds
    $jamFile = Join-Path $env:USERPROFILE "user-config.jam"
    if (Test-Path $jamFile) {
        Remove-Item $jamFile -Force
        Write-Host "Removed stale user-config.jam" -ForegroundColor Yellow
    }
    exit 0
} elseif ($List) {
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
    Write-Host "  .\build_vfx.ps1 -Clean               Clean all conda-build work dirs"
    Write-Host "  .\build_vfx.ps1 -Clean <package>     Clean work dirs for a package"
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
