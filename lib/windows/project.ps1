#region Project Creation
function New-DevEnvProject {
    <#
    .SYNOPSIS
        Creates a new project with DevEnv integration
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,

        [string]$ProjectPath = (Get-Location),

        [string]$Template = "basic",

        [string]$Description = ""
    )

    if ($script:DevEnvContext.Mode -eq "Project") {
        throw "Cannot create project from within project mode. Use global DevEnv instance."
    }

    $projectDir = Join-Path $ProjectPath $ProjectName

    if (Test-Path $projectDir) {
        if (-not $Force) {
            throw "Project directory already exists: $projectDir. Use -Force to overwrite."
        }
        Write-Warning "Project directory exists, removing: $projectDir"
        Remove-Item $projectDir -Recurse -Force
    }

    Write-Host "Creating project: " -NoNewline
    Write-Host $ProjectName -ForegroundColor Cyan
    Write-Host "Location: " -NoNewline
    Write-Host $projectDir -ForegroundColor Yellow
    Write-Host ""

    # Create project structure
    $projectStructure = @(
        "src",
        "bin",
        "docs",
        "tests",
        ".devenv"
    )

    foreach ($dir in $projectStructure) {
        $fullPath = Join-Path $projectDir $dir
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
    }

    # Create project configuration
    $projectConfig = @{
        name = $ProjectName
        version = "1.0.0"
        description = if ($Description) { $Description } else { "DevEnv project: $ProjectName" }
        template = $Template
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        devenv = @{
            version = "3.0.0"
            mode = "project"
            data_dir = ".devenv"
        }
        modules = @{
            order = @("git", "vscode")
        }
    }

    $configPath = Join-Path $projectDir "devenv.json"
    $projectConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8

    # Create README
    $readmeContent = @"
# $ProjectName

$($projectConfig.description)

## DevEnv Setup

This project uses DevEnv for isolated development environment management.

### Quick Start

1. Install development environment:
   ``````powershell
   .\bin\devenv.ps1 install
   ``````

2. Check status:
   ``````powershell
   .\bin\devenv.ps1 status
   ``````

3. Verify everything works:
   ``````powershell
   .\bin\devenv.ps1 verify
   ``````

### Available Commands

- `.\bin\devenv.ps1 install [modules]` - Install development tools
- `.\bin\devenv.ps1 status` - Show environment status
- `.\bin\devenv.ps1 verify` - Verify installations
- `.\bin\devenv.ps1 info` - Show detailed information

### Data Directory

All development tools and configurations are stored in `.devenv/` directory.
This directory is gitignored and contains the complete isolated environment.

Created: $((Get-Date).ToString("yyyy-MM-dd"))
"@

    $readmePath = Join-Path $projectDir "README.md"
    Set-Content -Path $readmePath -Value $readmeContent -Encoding UTF8

    # Create .gitignore
    $gitignoreContent = @"
# DevEnv data directory - contains isolated development environment
.devenv/

# Common build outputs
bin/
obj/
build/
dist/

# IDE files
.vs/
.vscode/settings.json
*.user
*.suo

# OS files
Thumbs.db
.DS_Store
"@

    $gitignorePath = Join-Path $projectDir ".gitignore"
    Set-Content -Path $gitignorePath -Value $gitignoreContent -Encoding UTF8

    # Create DevEnv symlink or copy
    $globalDevEnvPath = $script:DevEnvContext.ScriptPath
    $projectDevEnvPath = Join-Path $projectDir "bin\devenv.ps1"

    try {
        # Try to create symbolic link (requires admin or developer mode)
        New-Item -ItemType SymbolicLink -Path $projectDevEnvPath -Target $globalDevEnvPath -Force | Out-Null
        Write-Host "+ Created symlink: " -NoNewline -ForegroundColor Green
        Write-Host "bin\devenv.ps1 -> $globalDevEnvPath" -ForegroundColor Gray
        $linkType = "symlink"
    } catch {
        # Fall back to copying the file
        Copy-Item -Path $globalDevEnvPath -Destination $projectDevEnvPath -Force
        Write-Host "! Created copy: " -NoNewline -ForegroundColor Yellow
        Write-Host "bin\devenv.ps1" -ForegroundColor Gray
        Write-Host "  (Symlink failed - requires admin or developer mode)" -ForegroundColor Gray
        $linkType = "copy"
    }

    Write-Host ""
    Write-Host "+ Project created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. cd $ProjectName" -ForegroundColor White
    Write-Host "2. .\bin\devenv.ps1 install    # Set up development environment" -ForegroundColor White
    Write-Host "3. .\bin\devenv.ps1 status     # Check environment status" -ForegroundColor White
    Write-Host ""

    return @{
        ProjectDir = $projectDir
        ConfigFile = $configPath
        LinkType = $linkType
        DevEnvPath = $projectDevEnvPath
    }
}
#endregion
