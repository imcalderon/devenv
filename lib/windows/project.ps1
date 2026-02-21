#region Project Creation

# Render a .tmpl file by substituting registered scaffold variables
function Render-ScaffoldTemplate {
    param(
        [string]$TemplateFile,
        [string]$OutputFile,
        [hashtable]$Variables
    )

    $content = Get-Content $TemplateFile -Raw
    foreach ($key in $Variables.Keys) {
        $val = $Variables[$key]
        # Replace ${VAR} with value
        $content = $content.Replace("`${$key}", $val)
    }

    $destDir = Split-Path $OutputFile -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path $OutputFile -Value $content -Encoding UTF8
}

# Recursively copy and render a scaffold directory
function Copy-ScaffoldDirectory {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [hashtable]$Variables
    )

    if (-not (Test-Path $SourceDir)) { return }

    $items = Get-ChildItem $SourceDir -Recurse
    foreach ($item in $items) {
        if ($item.PSIsContainer) { continue }

        $relPath = $item.FullName.Substring($SourceDir.Length + 1)
        $destPath = Join-Path $TargetDir $relPath

        if ($item.Extension -eq ".tmpl") {
            $destPath = $destPath.Substring(0, $destPath.Length - 5)
            Render-ScaffoldTemplate -TemplateFile $item.FullName -OutputFile $destPath -Variables $Variables
        } else {
            $parentDir = Split-Path $destPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path $item.FullName -Destination $destPath -Force
        }
    }
}

function New-DevEnvProject {
    <#
    .SYNOPSIS
        Creates a new project with DevEnv integration using workflow templates
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName,

        [string]$ProjectPath = (Get-Location),

        [string]$Template = "vfx:standard",

        [string]$Description = ""
    )

    if ($script:DevEnvContext.Mode -eq "Project") {
        throw "Cannot create project from within project mode. Use global DevEnv instance."
    }

    $projectDir = Join-Path $ProjectPath $ProjectName
    $devenvRoot = $env:DEVENV_ROOT
    $scaffoldsRoot = Join-Path $devenvRoot "scaffolds"
    $workflowsRoot = Join-Path $devenvRoot "workflows"

    # Parse type:subtype
    $baseType = $Template
    $subtype = ""
    if ($Template -match ":") {
        $parts = $Template -split ":"
        $baseType = $parts[0]
        $subtype = $parts[1]
    }

    # Validate workflow
    $workflowDir = Join-Path $workflowsRoot $baseType
    $workflowFile = Join-Path $workflowDir "workflow.json"
    if (-not (Test-Path $workflowFile)) {
        throw "Unknown project type: $baseType. Workflows found in $workflowsRoot"
    }

    $workflow = Get-Content $workflowFile | ConvertFrom-Json

    # Validate subtype and determine scaffold path
    $scaffoldPath = ""
    if ($subtype -and $workflow.subtypes) {
        if ($workflow.subtypes.$subtype) {
            $scaffoldPath = $workflow.subtypes.$subtype.scaffold
        } else {
            throw "Unknown sub-type '$subtype' for workflow '$baseType'"
        }
    } else {
        $scaffoldPath = $workflow.scaffold
    }

    if ([string]::IsNullOrWhiteSpace($scaffoldPath)) {
        throw "No scaffold defined for template $Template"
    }

    $fullScaffoldDir = Join-Path $scaffoldsRoot $scaffoldPath

    if (Test-Path $projectDir) {
        if (-not $Force) {
            throw "Project directory already exists: $projectDir. Use -Force to overwrite."
        }
        Write-Warning "Project directory exists, removing: $projectDir"
        Remove-Item $projectDir -Recurse -Force
    }

    Write-Host "Creating $Template project: " -NoNewline
    Write-Host $ProjectName -ForegroundColor Cyan
    Write-Host "Location: " -NoNewline
    Write-Host $projectDir -ForegroundColor Yellow
    Write-Host ""

    # Collect variables for substitution
    $vars = @{
        "PROJECT_NAME" = $ProjectName
        "PROJECT_TYPE" = $Template
        "HOME" = $env:USERPROFILE.Replace('\', '/')
    }

    # Load workflow variables
    if ($workflow.variables) {
        foreach ($prop in $workflow.variables.PSObject.Properties) {
            $vars[$prop.Name] = [string]$prop.Value
        }
    }

    # Overlay subtype variables
    if ($subtype -and $workflow.subtypes.$subtype.variables) {
        foreach ($prop in $workflow.subtypes.$subtype.variables.PSObject.Properties) {
            $vars[$prop.Name] = [string]$prop.Value
        }
    }

    # Create target directory
    New-Item -Path $projectDir -ItemType Directory -Force | Out-Null

    # 1. Copy common scaffold
    $commonDir = Join-Path $scaffoldsRoot "common"
    if (Test-Path $commonDir) {
        Write-Verbose "Applying common scaffold..."
        Copy-ScaffoldDirectory -SourceDir $commonDir -TargetDir $projectDir -Variables $vars
    }

    # 2. Copy type-specific scaffold
    if (Test-Path $fullScaffoldDir) {
        Write-Verbose "Applying $Template scaffold from $fullScaffoldDir..."
        Copy-ScaffoldDirectory -SourceDir $fullScaffoldDir -TargetDir $projectDir -Variables $vars
    }

    # 3. Create project configuration (devenv.json)
    $projectConfig = @{
        name = $ProjectName
        version = "1.0.0"
        description = if ($Description) { $Description } else { $workflow.description }
        template = $Template
        created = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        devenv = @{
            version = "3.0.0"
            mode = "project"
            data_dir = ".devenv"
        }
        modules = @{
            order = if ($workflow.modules.windows) { $workflow.modules.windows } else { @("git", "vscode") }
        }
        variables = $vars
    }

    $configPath = Join-Path $projectDir "devenv.json"
    $projectConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8

    # Create bin directory if it doesn't exist
    $binDir = Join-Path $projectDir "bin"
    if (-not (Test-Path $binDir)) {
        New-Item -Path $binDir -ItemType Directory -Force | Out-Null
    }

    # Create DevEnv symlink or copy
    $globalDevEnvPath = $script:DevEnvContext.ScriptPath
    $projectDevEnvPath = Join-Path $binDir "devenv.ps1"

    try {
        New-Item -ItemType SymbolicLink -Path $projectDevEnvPath -Target $globalDevEnvPath -Force | Out-Null
        $linkType = "symlink"
    } catch {
        Copy-Item -Path $globalDevEnvPath -Destination $projectDevEnvPath -Force
        $linkType = "copy"
    }

    # Initialize git repo
    try {
        $null = Get-Command git -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0) {
            Push-Location $projectDir
            & git init -q
            & git add -A
            & git commit -q -m "Initial scaffold: $Template project"
            Pop-Location
        }
    } catch {}

    Write-Host ""
    Write-Host "+ Project created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. cd $ProjectName" -ForegroundColor White
    Write-Host "2. .\bin\devenv.ps1 install    # Set up environment" -ForegroundColor White
    if (Test-Path (Join-Path $projectDir "environment.yml")) {
        Write-Host "   (This will create a conda environment from environment.yml)" -ForegroundColor Gray
    }
    Write-Host "3. .\bin\devenv.ps1 status     # Check status" -ForegroundColor White
    Write-Host ""

    return @{
        ProjectDir = $projectDir
        ConfigFile = $configPath
        LinkType = $linkType
        DevEnvPath = $projectDevEnvPath
    }
}
#endregion
