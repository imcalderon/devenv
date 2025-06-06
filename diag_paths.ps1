# DevEnv Path Diagnostic Script
# Finds issues with paths including double slashes

Write-Host "DevEnv Path Diagnostics" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan

# Check all environment variables
Write-Host "`nEnvironment Variables:" -ForegroundColor Yellow
$envVars = @(
    'DEVENV_ROOT',
    'DEVENV_DATA_DIR',
    'DEVENV_CONFIG_FILE',
    'DEVENV_STATE_DIR',
    'DEVENV_LOGS_DIR',
    'DEVENV_BACKUPS_DIR',
    'DEVENV_MODULES_DIR',
    'DEVENV_PYTHON_DIR',
    'ROOT_DIR'
)

$pathIssues = @()
foreach ($var in $envVars) {
    $value = [Environment]::GetEnvironmentVariable($var)
    if ($value) {
        Write-Host "$var = $value" -ForegroundColor Gray
        
        # Check for double slashes
        if ($value -match '\\\\|//' -and $value -notmatch '^\\\\') {
            Write-Host "  [WARNING] Contains double slashes!" -ForegroundColor Yellow
            $pathIssues += "$var contains double slashes: $value"
        }
        
        # Check if path exists
        if ($var -ne 'DEVENV_CONFIG_FILE' -and -not (Test-Path $value)) {
            Write-Host "  [WARNING] Path does not exist!" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "$var = <not set>" -ForegroundColor DarkGray
    }
}

# Check Python-specific paths
Write-Host "`nPython Installation Paths:" -ForegroundColor Yellow
$pythonPaths = @{
    "Python Data Dir" = "$env:USERPROFILE\.devenv\python"
    "Python Venv" = "$env:USERPROFILE\.devenv\python\venv"
    "Temp Dir" = $env:TEMP
    "Local Temp" = "$env:LOCALAPPDATA\Temp"
}

foreach ($key in $pythonPaths.Keys) {
    $path = $pythonPaths[$key]
    Write-Host "$key = $path" -ForegroundColor Gray
    
    if ($path -match '\\\\|//') {
        Write-Host "  [WARNING] Contains double slashes!" -ForegroundColor Yellow
        $pathIssues += "$key contains double slashes: $path"
    }
    
    if (Test-Path $path) {
        try {
            $testFile = Join-Path $path "devenv_test_$([guid]::NewGuid()).tmp"
            New-Item -Path $testFile -ItemType File -Force | Out-Null
            Remove-Item $testFile -Force
            Write-Host "  [OK] Write permissions OK" -ForegroundColor Green
        }
        catch {
            Write-Host "  [ERROR] No write permissions!" -ForegroundColor Red
        }
    }
}

# Check module paths
Write-Host "`nModule Paths:" -ForegroundColor Yellow
$modulesDir = Join-Path $env:DEVENV_ROOT "modules"
if (Test-Path $modulesDir) {
    Get-ChildItem $modulesDir -Directory | ForEach-Object {
        $moduleScript = Join-Path $_.FullName "$($_.Name).ps1"
        if (Test-Path $moduleScript) {
            Write-Host "$($_.Name) module script: $moduleScript" -ForegroundColor Gray
            
            if ($moduleScript -match '\\\\|//') {
                Write-Host "  [WARNING] Contains double slashes!" -ForegroundColor Yellow
                $pathIssues += "$($_.Name) module path contains double slashes"
            }
        }
    }
}

# Summary
if ($pathIssues.Count -gt 0) {
    Write-Host "`n[WARNING] PATH ISSUES FOUND:" -ForegroundColor Yellow
    $pathIssues | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Yellow
    }
    
    Write-Host "`nTo fix double slash issues, run:" -ForegroundColor Cyan
    Write-Host "  .\de.ps1 install" -ForegroundColor White
    Write-Host "The updated wrapper should normalize all paths automatically." -ForegroundColor Gray
}
else {
    Write-Host "`n[SUCCESS] No path issues detected!" -ForegroundColor Green
}

# Python executable check
Write-Host "`nPython Executable:" -ForegroundColor Yellow
try {
    $pythonPath = (Get-Command python -ErrorAction Stop).Source
    Write-Host "Python found at: $pythonPath" -ForegroundColor Green
    & python --version
}
catch {
    Write-Host "Python not found in PATH!" -ForegroundColor Red
    Write-Host "Install Python from: https://www.python.org/downloads/" -ForegroundColor Yellow
}