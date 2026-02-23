# Powershell script to build installer for ${PROJECT_NAME}
$ErrorActionPreference = "Stop"

$root = Get-Location
$outDir = Join-Path $root "out/installer"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir }

# Activate Visual Studio environment
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -property installationPath
$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"

Write-Host "Activating VS environment: $vcvars"
$cmdOutput = cmd.exe /c "`"$vcvars`" >nul && set"
foreach ($line in $cmdOutput) {
    if ($line -match "^(.*?)=(.*)$") {
        $name = $matches[1]
        $value = $matches[2]
        try { Set-Item -Path "env:\$name" -Value $value -ErrorAction SilentlyContinue } catch {}
    }
}

# Run mkInstaller via py310 environment
$python310 = Join-Path $env:USERPROFILE "miniconda3\envs\py310\python.exe"
$mkInstaller = Join-Path $env:USERPROFILE "mkInstallerun_installer_build.py"
$manifest = Join-Path $root "bazel-bin/${PROJECT_NAME}_manifest.json"

Write-Host "Running: $python310 $mkInstaller --manifest $manifest --root bazel-bin --out $outDir --verbose"
& $python310 $mkInstaller --manifest $manifest --root bazel-bin --out $outDir --verbose
