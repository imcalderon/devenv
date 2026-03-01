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
    [switch]$Purge,
    [switch]$NoCache,
    [switch]$ContinueOnError,
    [string]$CondaEnv = "vfx-build"
)

# Robust directory removal for Windows MAX_PATH issues
function Remove-DirectoryRobust {
    param([string]$Path)
    if (Test-Path $Path) {
        # cmd /c rd is often more reliable for very long paths than PowerShell's Remove-Item
        cmd /c "rd /s /q `"$Path`"" 2>$null
        if (Test-Path $Path) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
$env:CONDA_REPORT_ERRORS = "false"
# Suppress VS copyright banner in vcvarsall.bat to prevent cmd.exe parsing errors.
# The "(c)" in "Copyright (c) 2025 Microsoft" breaks if/else blocks in
# conda's vs2022_compiler_vars.bat activation script.
$env:__VSCMD_ARG_NO_LOGO = "1"

# Prevent conda from modifying the prompt with parentheses, which breaks .bat parsing.
$env:CONDA_CHANGEPS1 = "0"
$env:CONDA_BUILD_NO_ENV_EXPORT = "1"
$env:CONDA_EMIT_ENV_VARS_FILE = "0"

# Use a simple prompt for the build session
$env:PROMPT = "`$P`$G"

# Derive paths relative to this script's location in devenv/scripts/
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$devenvRoot = Split-Path -Parent $scriptDir
# DEVENV_TOOLS_DIR: set this env var to redirect installs off C: (e.g. "D:\tools")
$toolsDir = if ($env:DEVENV_TOOLS_DIR) { $env:DEVENV_TOOLS_DIR } else { $env:USERPROFILE }

# Redirect TEMP to the tools drive to avoid cross-drive move errors (C: to D:) 
# and to shorten paths to avoid MAX_PATH (260 chars) limits.
$localTemp = Join-Path $toolsDir "temp"
if (-not (Test-Path $localTemp)) { New-Item -Path $localTemp -ItemType Directory -Force | Out-Null }
$env:TEMP = $localTemp
$env:TMP = $localTemp

$condaExe = Join-Path $toolsDir "miniconda3\Scripts\conda.exe"
$builderDir = Join-Path $devenvRoot "toolkits\vfx-bootstrap"
$vfxRoot = Join-Path $toolsDir "Development\vfx"
$outputDir = Join-Path $vfxRoot "builds"
$channelDir = Join-Path $vfxRoot "channel"

if (-not (Test-Path $condaExe)) {
    Write-Host "ERROR: conda not found at $condaExe" -ForegroundColor Red
    exit 1
}

# Map positional "list" or "order" to the correct switches if they are passed as the Package argument
if ($Package -eq "list") { $List = $true; $Package = $null }
if ($Package -eq "order") { $Order = $true; $Package = $null }

# Find conda-build executable in the environment
$condaBldExe = Join-Path $toolsDir "miniconda3\envs\$CondaEnv\Scripts\conda-build.exe"
if (-not (Test-Path $condaBldExe)) { $condaBldExe = "conda-build" }

# Build the CLI arguments (shared between conda run and direct python)
$cliArgs = @(
    "--output", $outputDir,
    "--channel-dir", $channelDir,
    "--conda-build", $condaBldExe
)

if ($Clean -or $Purge) {
    if ($Clean) {
        $condaBld = Join-Path $toolsDir "miniconda3\envs\$CondaEnv\conda-bld"
        if ($Package) {
            $pattern = "${Package}_*"
            $dirs = Get-ChildItem "$condaBld\$pattern" -Directory -ErrorAction SilentlyContinue
            if ($dirs) {
                $dirs | ForEach-Object {
                    Write-Host "Removing work dir: $($_.Name)" -ForegroundColor Yellow
                    Remove-DirectoryRobust $_.FullName
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
                    Remove-DirectoryRobust $_.FullName
                }
                Write-Host "Cleaned $($workDirs.Count) conda-build dir(s)" -ForegroundColor Green
            } else {
                Write-Host "No conda-build work dirs to clean" -ForegroundColor Gray
            }
        }
        # Also clean stale user-config.jam from boost builds
        $jamFile = Join-Path $env:USERPROFILE "user-config.jam"
        if (Test-Path $jamFile) {
            Remove-Item $jamFile -Force
            Write-Host "Removed stale user-config.jam" -ForegroundColor Yellow
        }
    }

    if ($Purge) {
        Write-Host "Purging build artifacts..." -ForegroundColor Cyan
        if (Test-Path $outputDir) {
            Write-Host "Removing builds: $outputDir" -ForegroundColor Yellow
            Remove-DirectoryRobust $outputDir
        }
        if (Test-Path $channelDir) {
            Write-Host "Removing channel: $channelDir" -ForegroundColor Yellow
            Remove-DirectoryRobust $channelDir
        }
        Write-Host "Purge complete." -ForegroundColor Green
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
    $condaBld = Join-Path $toolsDir "miniconda3\envs\$CondaEnv\conda-bld"
    Get-ChildItem "$condaBld\${Package}_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Removing stale: $($_.Name)"
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Use the environment's python directly instead of 'conda run' to bypass activation shell hooks
$envPython = Join-Path $toolsDir "miniconda3\envs\$CondaEnv\python.exe"
if (-not (Test-Path $envPython)) {
    Write-Host "WARNING: Environment python not found at $envPython, falling back to conda run" -ForegroundColor Yellow
    & $condaExe run --live-stream -n $CondaEnv --cwd $builderDir python @cliArgs
} else {
    # Set the path to include condabin for the subprocess
    $env:PATH = "$(Join-Path $toolsDir 'miniconda3\condabin');$env:PATH"
    # Set PYTHONPATH to the builder directory
    $env:PYTHONPATH = $builderDir
    & $envPython -m builder.cli @cliArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`nDone." -ForegroundColor Green
