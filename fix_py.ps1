# Fix Python Installation Issues for DevEnv
# Run this before attempting to install Python module

param(
    [switch]$Force
)

Write-Host "DevEnv Python Installation Fix" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# Function to test and fix permissions
function Fix-DirectoryPermissions {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Host "Creating directory: $Path" -ForegroundColor Yellow
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
    
    try {
        $acl = Get-Acl $Path
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $permission = $currentUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
        $acl.SetAccessRule($accessRule)
        Set-Acl $Path $acl
        Write-Host "[OK] Fixed permissions for: $Path" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Could not fix permissions for: $Path" -ForegroundColor Red
        Write-Host "  Error: $_" -ForegroundColor Yellow
    }
}

# 1. Clear Python temp files
Write-Host "`nClearing Python temporary files..." -ForegroundColor Yellow
$tempDirs = @(
    "$env:TEMP\pip-*",
    "$env:LOCALAPPDATA\pip\Cache",
    "$env:LOCALAPPDATA\Temp\pip-*"
)

foreach ($pattern in $tempDirs) {
    Get-ChildItem $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
            Write-Host "  Removed: $($_.Name)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  Could not remove: $($_.Name)" -ForegroundColor Yellow
        }
    }
}

# 2. Fix DevEnv Python directory permissions
$devenvPythonDir = "$env:USERPROFILE\.devenv\python"
Write-Host "`nFixing DevEnv Python directory permissions..." -ForegroundColor Yellow
Fix-DirectoryPermissions $devenvPythonDir
Fix-DirectoryPermissions "$devenvPythonDir\venv"

# 3. Remove existing broken venv if it exists
$venvPath = "$devenvPythonDir\venv"
if (Test-Path $venvPath) {
    Write-Host "`nRemoving existing virtual environment..." -ForegroundColor Yellow
    try {
        # First try to deactivate if active
        if ($env:VIRTUAL_ENV -eq $venvPath) {
            & deactivate 2>$null
        }
        
        # Remove the directory
        Remove-Item $venvPath -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed existing venv" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Could not remove venv completely" -ForegroundColor Red
        Write-Host "  You may need to restart your computer and try again" -ForegroundColor Yellow
    }
}

# 4. Clear Python state in DevEnv
$pythonStateFile = "$env:USERPROFILE\.devenv\state\python.json"
if (Test-Path $pythonStateFile) {
    Write-Host "`nClearing Python module state..." -ForegroundColor Yellow
    Remove-Item $pythonStateFile -Force
    Write-Host "[OK] Cleared Python state" -ForegroundColor Green
}

# 5. Upgrade pip globally (outside venv)
Write-Host "`nUpgrading global pip..." -ForegroundColor Yellow
try {
    $pythonExe = (Get-Command python -ErrorAction Stop).Source
    Write-Host "  Python location: $pythonExe" -ForegroundColor Gray
    
    # Upgrade pip using Python directly
    & $pythonExe -m pip install --upgrade pip --user --no-warn-script-location 2>&1 | Out-String
    Write-Host "[OK] Global pip upgraded" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Could not upgrade global pip" -ForegroundColor Red
    Write-Host "  Make sure Python is installed and in PATH" -ForegroundColor Yellow
}

# 6. Pre-create directories with correct permissions
Write-Host "`nPre-creating Python directories..." -ForegroundColor Yellow
$dirsToCreate = @(
    "$devenvPythonDir",
    "$devenvPythonDir\scripts",
    "$devenvPythonDir\packages",
    "$devenvPythonDir\config"
)

foreach ($dir in $dirsToCreate) {
    Fix-DirectoryPermissions $dir
}

# 7. Set environment variables
Write-Host "`nSetting environment variables..." -ForegroundColor Yellow
$env:PIP_NO_WARN_SCRIPT_LOCATION = "1"
$env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
$env:PYTHONDONTWRITEBYTECODE = "1"

Write-Host "`n[CHECK] Python installation preparation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Run: .\de install python" -ForegroundColor White
Write-Host "2. If it still fails, run as Administrator:" -ForegroundColor White
Write-Host "   Start-Process powershell -Verb RunAs -ArgumentList '-Command cd $PWD; .\de install python'" -ForegroundColor Gray
Write-Host ""

if ($Force) {
    Write-Host "Attempting Python installation now..." -ForegroundColor Yellow
    & "$PSScriptRoot\de.ps1" install python -Force
}