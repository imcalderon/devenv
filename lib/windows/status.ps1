#region Enhanced Status Display
function Show-ModeAwareStatus {
    <#
    .SYNOPSIS
        Shows status information appropriate for the current mode
    #>
    param([hashtable]$DevEnvContext)

    Write-Host ""
    Write-Host "DevEnv Status Report" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    Write-Host ""

    # Execution context
    Write-Host "Execution Context" -ForegroundColor Yellow
    Write-Host "-----------------" -ForegroundColor Yellow
    Write-Host "Mode: " -NoNewline

    if ($DevEnvContext.Mode -eq "Project") {
        Write-Host "Project-Specific" -ForegroundColor Magenta
        Write-Host "Project Name: " -NoNewline
        Write-Host (Split-Path $DevEnvContext.ProjectRoot -Leaf) -ForegroundColor White
        Write-Host "Project Root: " -NoNewline
        Write-Host $DevEnvContext.ProjectRoot -ForegroundColor Gray
        Write-Host "Project Config: " -NoNewline
        Write-Host $DevEnvContext.ConfigFile -ForegroundColor Gray

        if ($DevEnvContext.IsSymlink) {
            Write-Host "DevEnv Link: " -NoNewline
            Write-Host "Symlink OK" -ForegroundColor Green
            Write-Host "Global DevEnv: " -NoNewline
            Write-Host $DevEnvContext.GlobalDevEnvPath -ForegroundColor Gray
        } else {
            Write-Host "DevEnv Link: " -NoNewline
            Write-Host "Copy" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Global System-Wide" -ForegroundColor Green
        Write-Host "DevEnv Root: " -NoNewline
        Write-Host (Split-Path $DevEnvContext.ScriptPath -Parent) -ForegroundColor Gray
        Write-Host "Global Config: " -NoNewline
        Write-Host $DevEnvContext.ConfigFile -ForegroundColor Gray
    }

    Write-Host "Data Directory: " -NoNewline
    Write-Host $DevEnvContext.DataDir -ForegroundColor Yellow
    Write-Host ""

    # Configuration status
    Write-Host "Configuration" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow

    if (Test-Path $DevEnvContext.ConfigFile) {
        Write-Host "Config File: " -NoNewline
        Write-Host "Found OK" -ForegroundColor Green

        try {
            $config = Get-Content $DevEnvContext.ConfigFile | ConvertFrom-Json
            if ($config.modules -and $config.modules.order) {
                Write-Host "Configured Modules: " -NoNewline
                Write-Host ($config.modules.order -join ", ") -ForegroundColor Cyan
            }
        } catch {
            Write-Host "Config Parse: " -NoNewline
            Write-Host "Error" -ForegroundColor Red
        }
    } else {
        Write-Host "Config File: " -NoNewline
        Write-Host "Missing" -ForegroundColor Red
    }

    Write-Host ""

    # Data directory contents
    Write-Host "Environment Data" -ForegroundColor Yellow
    Write-Host "----------------" -ForegroundColor Yellow

    $dataDirs = @{
        "State" = Join-Path $DevEnvContext.DataDir "state"
        "Tools" = Join-Path $DevEnvContext.DataDir "tools"
        "Config" = Join-Path $DevEnvContext.DataDir "config"
        "Logs" = Join-Path $DevEnvContext.DataDir "logs"
        "Backups" = Join-Path $DevEnvContext.DataDir "backups"
    }

    foreach ($dir in $dataDirs.GetEnumerator()) {
        Write-Host "$($dir.Key): " -NoNewline
        if (Test-Path $dir.Value) {
            $items = @(Get-ChildItem $dir.Value -ErrorAction SilentlyContinue)
            Write-Host "$(@($items).Count) items" -ForegroundColor Green
        } else {
            Write-Host "Not created" -ForegroundColor Yellow
        }
    }

    Write-Host ""

    # Module status (simplified for now)
    Write-Host "Module Status" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow

    $stateDir = Join-Path $DevEnvContext.DataDir "state"
    if (Test-Path $stateDir) {
        $stateFiles = @(Get-ChildItem $stateDir -Filter "*.state" -ErrorAction SilentlyContinue)
        if (@($stateFiles).Count -gt 0) {
            foreach ($stateFile in $stateFiles) {
                $moduleName = $stateFile.BaseName
                Write-Host "$moduleName`: " -NoNewline
                Write-Host "Installed" -ForegroundColor Green
            }
        } else {
            Write-Host "No modules installed" -ForegroundColor Gray
        }
    } else {
        Write-Host "No state directory" -ForegroundColor Gray
    }

    Write-Host ""
}

function Show-ModeAwareInfo {
    <#
    .SYNOPSIS
        Shows information and guidance appropriate for the current mode
    #>
    param([hashtable]$DevEnvContext)

    if ($DevEnvContext.Mode -eq "Project") {
        Write-Host ""
        Write-Host "[PROJ] Project Environment Information" -ForegroundColor Cyan
        Write-Host "=====================================" -ForegroundColor Cyan
        Write-Host ""

        $projectName = Split-Path $DevEnvContext.ProjectRoot -Leaf
        Write-Host "Project: " -NoNewline
        Write-Host $projectName -ForegroundColor White
        Write-Host ""

        # Load project config
        if (Test-Path $DevEnvContext.ConfigFile) {
            try {
                $projectConfig = Get-Content $DevEnvContext.ConfigFile | ConvertFrom-Json
                Write-Host "Description: " -NoNewline
                Write-Host $projectConfig.description -ForegroundColor Gray
                Write-Host "Template: " -NoNewline
                Write-Host $projectConfig.template -ForegroundColor Cyan
                Write-Host "Created: " -NoNewline
                Write-Host $projectConfig.created -ForegroundColor Gray
                Write-Host ""
            } catch {
                Write-Host "Could not read project configuration" -ForegroundColor Yellow
            }
        }

        Write-Host "Available Commands:" -ForegroundColor Yellow
        Write-Host "- .\bin\devenv.ps1 install        # Install development tools" -ForegroundColor White
        Write-Host "- .\bin\devenv.ps1 status         # Show environment status" -ForegroundColor White
        Write-Host "- .\bin\devenv.ps1 verify         # Verify installations" -ForegroundColor White
        Write-Host "- .\bin\devenv.ps1 list           # List available modules" -ForegroundColor White
        Write-Host ""

        Write-Host "Project Structure:" -ForegroundColor Yellow
        $items = Get-ChildItem $DevEnvContext.ProjectRoot | Sort-Object Name
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                Write-Host "[DIR] $($item.Name)/" -ForegroundColor Blue
            } else {
                Write-Host "[FILE] $($item.Name)" -ForegroundColor Gray
            }
        }

    } else {
        # Global mode - show system analysis and project creation guidance
        Write-Host ""
        Write-Host "[GLOBAL] DevEnv Global Mode" -ForegroundColor Cyan
        Write-Host "===========================" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "Available Actions:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Project Management:" -ForegroundColor Cyan
        Write-Host "- .\devenv.ps1 create-project -Name MyProject    # Create new project" -ForegroundColor White
        Write-Host "- .\devenv.ps1 list                              # List available modules" -ForegroundColor White
        Write-Host ""
        Write-Host "Global Tools:" -ForegroundColor Cyan
        Write-Host "- .\devenv.ps1 install git vscode               # Install global tools" -ForegroundColor White
        Write-Host "- .\devenv.ps1 status                           # Show global status" -ForegroundColor White
        Write-Host ""

        Write-Host "Quick Start:" -ForegroundColor Yellow
        Write-Host "1. Create a new project:" -ForegroundColor White
        Write-Host "   .\devenv.ps1 create-project -Name MyProject" -ForegroundColor Gray
        Write-Host "2. Navigate to project:" -ForegroundColor White
        Write-Host "   cd MyProject" -ForegroundColor Gray
        Write-Host "3. Set up project environment:" -ForegroundColor White
        Write-Host "   .\bin\devenv.ps1 install" -ForegroundColor Gray
        Write-Host ""
    }
}
#endregion
