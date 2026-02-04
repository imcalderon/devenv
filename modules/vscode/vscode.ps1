#Requires -Version 5.1
<#
.SYNOPSIS
    VSCode Module for DevEnv - Native Windows implementation with container support
.DESCRIPTION
    Native Windows module for Visual Studio Code with extension management,
    settings configuration, and container-based code-server support.
#>

param (
    [Parameter(Position=0, Mandatory=$true)]
    [ValidateSet('install', 'remove', 'verify', 'info', 'grovel')]
    [string]$Action,
    
    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Initialization
$libPath = Join-Path $env:DEVENV_ROOT "lib\windows"
$requiredModules = @('logging.ps1', 'json.ps1', 'module.ps1', 'backup.ps1', 'alias.ps1')

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $libPath $module
    if (Test-Path $modulePath) {
        . $modulePath
    } else {
        Write-Error "Required module not found: $modulePath"
        exit 1
    }
}

$script:ModuleName = "vscode"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # VSCode installation
    'extensions',   # Extension management
    'settings',     # Configuration files
    'container',    # Container-based code-server
    'fonts',        # Development fonts
    'aliases'       # Command aliases
)
#endregion

#region State Management
function Save-ComponentState {
    param([string]$Component, [string]$Status)
    
    $stateDir = Split-Path $script:StateFile -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = [int][DateTimeOffset]::Now.ToUnixTimeSeconds()
    Add-Content -Path $script:StateFile -Value "$Component`:$Status`:$timestamp"
    Write-LogInfo "Saved state for component: $Component ($Status)" $script:ModuleName
}

function Test-ComponentState {
    param([string]$Component)
    
    if (Test-Path $script:StateFile) {
        $content = Get-Content $script:StateFile
        return ($content -match "^$Component`:installed:")
    }
    return $false
}

function Test-Component {
    param([string]$Component)
    
    switch ($Component) {
        'core' {
            # Check if VSCode is installed
            $vscodePaths = @(
                "${env:ProgramFiles}\Microsoft VS Code\Code.exe",
                "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe",
                "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe"
            )
            
            foreach ($path in $vscodePaths) {
                if (Test-Path $path) {
                    return $true
                }
            }
            
            # Check if code command is available in PATH
            try {
                $null = Get-Command code -ErrorAction Stop
                return $true
            } catch {
                return $false
            }
        }
        'extensions' {
            # Check if essential extensions are installed
            if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
                return $false
            }
            
            $requiredExtensions = Get-ModuleConfig $script:ModuleName ".vscode.extensions[]"
            $installedExtensions = code --list-extensions 2>$null
            
            foreach ($extension in $requiredExtensions) {
                if ($installedExtensions -notcontains $extension) {
                    return $false
                }
            }
            return $true
        }
        'settings' {
            # Check if settings are configured
            $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
            $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
            $settingsFile = Join-Path $settingsPath "settings.json"
            return (Test-Path $settingsFile)
        }
        'container' {
            # Check if container configuration exists
            $containerEnabled = Get-ModuleConfig $script:ModuleName ".global.container.modules.vscode.containerize"
            if ($containerEnabled -eq $true) {
                # Check if Docker is available
                try {
                    $null = docker.exe version 2>$null
                    return $LASTEXITCODE -eq 0
                } catch {
                    return $false
                }
            }
            return $true  # Not containerized, so consider it verified
        }
        'fonts' {
            # Check if development fonts are installed
            $fontNames = @("Cascadia Code", "Fira Code", "JetBrains Mono")
            $installedFonts = Get-ChildItem "$env:WINDIR\Fonts" -Name
            
            foreach ($fontName in $fontNames) {
                $fontFound = $installedFonts | Where-Object { $_ -like "*$fontName*" }
                if ($fontFound) {
                    return $true
                }
            }
            return $false
        }
        'aliases' {
            # Check if aliases are configured
            $aliasesFile = Join-Path (Get-AliasesDirectory) "aliases.ps1"
            return (Test-Path $aliasesFile) -and (Get-ModuleAliases $script:ModuleName)
        }
        default {
            return $false
        }
    }
}
#endregion

#region Component Installation
function Install-CoreComponent {
    Write-LogInfo "Installing VSCode core component..." $script:ModuleName
    
    # Check if VSCode is already installed
    if (Test-Component 'core') {
        Write-LogInfo "VSCode is already installed" $script:ModuleName
        return $true
    }
    
    # Install VSCode via winget
    try {
        Write-LogInfo "Installing VSCode via winget..." $script:ModuleName
        winget.exe install --exact --id Microsoft.VisualStudioCode --silent --accept-package-agreements --accept-source-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "VSCode installed successfully via winget" $script:ModuleName
            
            # Add to PATH if not already there
            $vscodePath = "${env:ProgramFiles}\Microsoft VS Code\bin"
            if (Test-Path $vscodePath) {
                $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
                if ($currentPath -notlike "*$vscodePath*") {
                    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$vscodePath", "User")
                    $env:PATH = "$env:PATH;$vscodePath"
                    Write-LogInfo "Added VSCode to PATH" $script:ModuleName
                }
            }
            
            return $true
        } else {
            Write-LogWarning "winget installation failed, trying direct download..." $script:ModuleName
        }
    } catch {
        Write-LogWarning "winget not available, trying direct download: $_" $script:ModuleName
    }
    
    # Fallback to direct download
    try {
        $downloadUrl = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
        $installerPath = Join-Path $env:TEMP "VSCodeUserSetup.exe"
        
        Write-LogInfo "Downloading VSCode installer..." $script:ModuleName
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        
        Write-LogInfo "Installing VSCode..." $script:ModuleName
        Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT", "/NORESTART", "/MERGETASKS=!runcode" -Wait
        
        # Clean up
        Remove-Item $installerPath -Force
        
        # Verify installation
        Start-Sleep -Seconds 3
        if (Test-Component 'core') {
            Write-LogInfo "VSCode installed successfully" $script:ModuleName
            return $true
        } else {
            Write-LogError "VSCode installation verification failed" $script:ModuleName
            return $false
        }
    } catch {
        Write-LogError "Failed to install VSCode: $_" $script:ModuleName
        return $false
    }
}

function Install-ExtensionsComponent {
    Write-LogInfo "Installing VSCode extensions..." $script:ModuleName
    
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-LogError "VSCode not found in PATH" $script:ModuleName
        return $false
    }
    
    $extensions = Get-ModuleConfig $script:ModuleName ".vscode.extensions[]"
    $failedExtensions = @()
    
    foreach ($extension in $extensions) {
        if (-not $extension) { continue }
        
        Write-LogInfo "Installing extension: $extension" $script:ModuleName
        
        try {
            code --install-extension $extension --force
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogInfo "Successfully installed: $extension" $script:ModuleName
            } else {
                Write-LogWarning "Failed to install extension: $extension (exit code: $LASTEXITCODE)" $script:ModuleName
                $failedExtensions += $extension
            }
        } catch {
            Write-LogWarning "Error installing extension ${extension}: $_" $script:ModuleName
            $failedExtensions += $extension
        }
    }
    
    if ($failedExtensions.Count -gt 0) {
        Write-LogWarning "Some extensions failed to install: $($failedExtensions -join ', ')" $script:ModuleName
    }
    
    return $true
}

function Install-SettingsComponent {
    Write-LogInfo "Installing VSCode settings..." $script:ModuleName
    
    try {
        # Get settings configuration
        $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
        $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
        $settingsFile = Join-Path $settingsPath "settings.json"
        
        # Create settings directory
        if (-not (Test-Path $settingsPath)) {
            New-Item -Path $settingsPath -ItemType Directory -Force | Out-Null
        }
        
        # Backup existing settings
        if (Test-Path $settingsFile) {
            Backup-File $settingsFile $script:ModuleName
        }
        
        # Get settings from module config
        $settings = Get-ModuleConfig $script:ModuleName ".vscode.settings"
        
        if ($settings) {
            # Convert to JSON and write to file
            $settingsJson = $settings | ConvertTo-Json -Depth 10
            Set-Content -Path $settingsFile -Value $settingsJson -Encoding UTF8
            Write-LogInfo "VSCode settings configured: $settingsFile" $script:ModuleName
        }
        
        # Configure keybindings if specified
        $keybindings = Get-ModuleConfig $script:ModuleName ".vscode.keybindings"
        if ($keybindings) {
            $keybindingsFile = Join-Path $settingsPath "keybindings.json"
            $keybindingsJson = $keybindings | ConvertTo-Json -Depth 10
            Set-Content -Path $keybindingsFile -Value $keybindingsJson -Encoding UTF8
            Write-LogInfo "VSCode keybindings configured: $keybindingsFile" $script:ModuleName
        }
        
        return $true
    } catch {
        Write-LogError "Failed to configure VSCode settings: $_" $script:ModuleName
        return $false
    }
}

function Install-ContainerComponent {
    Write-LogInfo "Installing VSCode container component..." $script:ModuleName
    
    # Check if containerization is enabled
    $containerEnabled = Get-ModuleConfig $script:ModuleName ".global.container.modules.vscode.containerize"
    if ($containerEnabled -ne $true) {
        Write-LogInfo "VSCode containerization not enabled" $script:ModuleName
        return $true
    }
    
    # Check if Docker is available
    try {
        $null = docker.exe version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-LogWarning "Docker not available, skipping container setup" $script:ModuleName
            return $true
        }
    } catch {
        Write-LogWarning "Docker not available, skipping container setup" $script:ModuleName
        return $true
    }
    
    # Create container configuration
    try {
        $containerDir = Join-Path $env:DEVENV_DATA_DIR "containers\vscode"
        if (-not (Test-Path $containerDir)) {
            New-Item -Path $containerDir -ItemType Directory -Force | Out-Null
        }
        
        # Create Dockerfile for code-server
        $dockerfile = Join-Path $containerDir "Dockerfile"
        $dockerfileContent = @"
FROM codercom/code-server:latest

# Install additional tools
USER root
RUN apt-get update && apt-get install -y \\
    git \\
    curl \\
    wget \\
    unzip \\
    && rm -rf /var/lib/apt/lists/*

# Create workspace directory
RUN mkdir -p /home/coder/workspace
WORKDIR /home/coder/workspace

# Switch back to coder user
USER coder

# Expose port
EXPOSE 8443

# Start code-server
CMD ["code-server", "--bind-addr", "0.0.0.0:8443", "--auth", "password", "/home/coder/workspace"]
"@
        
        Set-Content -Path $dockerfile -Value $dockerfileContent -Encoding UTF8
        
        # Create docker-compose.yml
        $composeFile = Join-Path $containerDir "docker-compose.yml"
        $composeContent = @"
version: '3.8'

services:
  code-server:
    build: .
    container_name: devenv-vscode
    ports:
      - "8443:8443"
    volumes:
      - $($env:USERPROFILE.Replace('\', '/')):/home/coder/host-home
      - $($env:DEVENV_ROOT.Replace('\', '/')):/home/coder/workspace/devenv
      - vscode-extensions:/home/coder/.local/share/code-server/extensions
      - vscode-config:/home/coder/.local/share/code-server/User
    environment:
      - PASSWORD=`${DEVENV_VSCODE_PASSWORD:-changeme}
      - SUDO_PASSWORD=`${DEVENV_SUDO_PASSWORD:-changeme}
    restart: unless-stopped

volumes:
  vscode-extensions:
  vscode-config:
"@
        
        Set-Content -Path $composeFile -Value $composeContent -Encoding UTF8
        
        # Create start script
        $startScript = Join-Path $containerDir "start-code-server.ps1"
        $startScriptContent = @"
# Start VSCode code-server container
param([switch]`$Rebuild)

`$containerDir = "$containerDir"
Push-Location `$containerDir

try {
    if (`$Rebuild) {
        Write-Host "Rebuilding code-server container..." -ForegroundColor Yellow
        docker-compose down
        docker-compose build --no-cache
    }
    
    Write-Host "Starting code-server container..." -ForegroundColor Green
    docker-compose up -d
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "VSCode Server is starting up!" -ForegroundColor Green
        Write-Host "URL: http://localhost:8443" -ForegroundColor Cyan
        Write-Host "Password: (set DEVENV_VSCODE_PASSWORD env var)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Give it a moment to start, then open the URL in your browser." -ForegroundColor White
    } else {
        Write-Host "Failed to start code-server container" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}
"@
        
        Set-Content -Path $startScript -Value $startScriptContent -Encoding UTF8
        
        Write-LogInfo "VSCode container configuration created at: $containerDir" $script:ModuleName
        return $true
    } catch {
        Write-LogError "Failed to configure VSCode container: $_" $script:ModuleName
        return $false
    }
}

function Install-FontsComponent {
    Write-LogInfo "Installing development fonts..." $script:ModuleName
    
    try {
        # Download and install popular coding fonts
        $fontsToInstall = @(
            @{
                Name = "Cascadia Code"
                Url = "https://github.com/microsoft/cascadia-code/releases/latest/download/CascadiaCode.zip"
                Pattern = "*.ttf"
            },
            @{
                Name = "Fira Code"
                Url = "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
                Pattern = "ttf/*.ttf"
            }
        )
        
        foreach ($font in $fontsToInstall) {
            Write-LogInfo "Installing font: $($font.Name)" $script:ModuleName
            
            try {
                $tempDir = Join-Path $env:TEMP "fonts_$([System.Guid]::NewGuid().ToString('N')[0..7] -join '')"
                New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                
                $zipPath = Join-Path $tempDir "$($font.Name).zip"
                Invoke-WebRequest -Uri $font.Url -OutFile $zipPath
                
                Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
                
                # Find font files
                $fontFiles = Get-ChildItem -Path $tempDir -Filter $font.Pattern -Recurse
                
                foreach ($fontFile in $fontFiles) {
                    $fontName = $fontFile.BaseName
                    $targetPath = Join-Path $env:WINDIR "Fonts\$($fontFile.Name)"
                    
                    # Copy font to Windows Fonts directory
                    Copy-Item -Path $fontFile.FullName -Destination $targetPath -Force
                    
                    # Register font in registry
                    $regKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                    Set-ItemProperty -Path $regKey -Name "$fontName (TrueType)" -Value $fontFile.Name
                }
                
                Write-LogInfo "Successfully installed font: $($font.Name)" $script:ModuleName
                
                # Clean up
                Remove-Item -Path $tempDir -Recurse -Force
            } catch {
                Write-LogWarning "Failed to install font $($font.Name): $_" $script:ModuleName
            }
        }
        
        return $true
    } catch {
        Write-LogError "Failed to install fonts: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing VSCode aliases..." $script:ModuleName
    
    # Add module aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    
    foreach ($category in $aliasCategories) {
        if (Add-ModuleAliases $script:ModuleName $category) {
            Write-LogInfo "Added aliases for category: $category" $script:ModuleName
        } else {
            Write-LogWarning "Failed to add aliases for category: $category" $script:ModuleName
        }
    }
    
    return $true
}
#endregion

#region Main Module Functions
function Install-Component {
    param([string]$Component)
    
    if ((Test-ComponentState $Component) -and (Test-Component $Component) -and -not $Force) {
        Write-LogInfo "Component $Component already installed and verified" $script:ModuleName
        return $true
    }
    
    $result = switch ($Component) {
        'core' { Install-CoreComponent }
        'extensions' { Install-ExtensionsComponent }
        'settings' { Install-SettingsComponent }
        'container' { Install-ContainerComponent }
        'fonts' { Install-FontsComponent }
        'aliases' { Install-AliasesComponent }
        default { 
            Write-LogError "Unknown component: $Component" $script:ModuleName
            $false
        }
    }
    
    if ($result) {
        Save-ComponentState $Component 'installed'
        Write-LogInfo "Successfully installed component: $Component" $script:ModuleName
    } else {
        Write-LogError "Failed to install component: $Component" $script:ModuleName
    }
    
    return $result
}

function Test-ModuleInstallation {
    Write-LogInfo "Checking VSCode module installation status..." $script:ModuleName
    
    $needsInstallation = $false
    
    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component
        
        if (-not $isInstalled -or -not $isVerified) {
            Write-LogInfo "Component $component needs installation" $script:ModuleName
            $needsInstallation = $true
        }
    }
    
    return -not $needsInstallation
}

function Install-Module {
    Write-LogInfo "Installing $($script:ModuleName) module..." $script:ModuleName
    
    if (-not $Force -and (Test-ModuleInstallation)) {
        Write-LogInfo "Module already installed and verified" $script:ModuleName
        Show-ModuleInfo
        return $true
    }
    
    # Create backup before installation
    New-Backup $script:ModuleName
    
    # Install each component
    foreach ($component in $script:Components) {
        Write-LogInfo "Installing component: $component" $script:ModuleName
        
        if (-not (Install-Component $component)) {
            Write-LogError "Failed to install component: $component" $script:ModuleName
            return $false
        }
    }
    
    Write-LogInfo "VSCode module installation completed successfully" $script:ModuleName
    Show-ModuleInfo
    
    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName
    
    # Create backup before removal
    New-Backup $script:ModuleName
    
    # Stop container if running
    $containerDir = Join-Path $env:DEVENV_DATA_DIR "containers\vscode"
    if (Test-Path $containerDir) {
        try {
            Push-Location $containerDir
            docker-compose down 2>$null
            Pop-Location
        } catch {
            # Ignore errors
        }
    }
    
    # Remove aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    foreach ($category in $aliasCategories) {
        Remove-ModuleAliases $script:ModuleName $category
    }
    
    # Remove settings (backup first)
    $settingsPath = Get-ModuleConfig $script:ModuleName ".shell.paths.config_dir"
    $settingsPath = [System.Environment]::ExpandEnvironmentVariables($settingsPath)
    if (Test-Path $settingsPath) {
        Backup-File $settingsPath $script:ModuleName
        Remove-Item $settingsPath -Recurse -Force
    }
    
    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }
    
    Write-LogInfo "VSCode module configuration removed" $script:ModuleName
    Write-LogWarning "VSCode application and extensions were preserved" $script:ModuleName
    
    return $true
}

function Test-ModuleVerification {
    Write-LogInfo "Verifying $($script:ModuleName) module installation..." $script:ModuleName
    
    $allVerified = $true
    
    foreach ($component in $script:Components) {
        if (-not (Test-Component $component)) {
            Write-LogError "Verification failed for component: $component" $script:ModuleName
            $allVerified = $false
        } else {
            Write-LogInfo "Component verified: $component" $script:ModuleName
        }
    }
    
    if ($allVerified) {
        Write-LogInfo "VSCode module verification completed successfully" $script:ModuleName
        
        # Show VSCode version
        try {
            $version = code --version 2>$null | Select-Object -First 1
            Write-LogInfo "VSCode version: $version" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine VSCode version" $script:ModuleName
        }
    }
    
    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Visual Studio Code Development Environment
==========================================

Description:
-----------
Complete VSCode setup with extensions, settings, and container support.
Includes both native Windows installation and containerized code-server option.

Benefits:
--------
+ Native Integration - Full Windows VSCode with system integration
+ Container Option - Browser-based VSCode via code-server
+ Extension Management - Automated installation of development extensions
+ Optimized Settings - Pre-configured for development workflows
+ Font Installation - Popular coding fonts automatically installed

Components:
----------
1. Core VSCode
   - Native Windows installation via winget
   - Command-line integration
   - System PATH configuration

2. Extensions
   - Python development tools
   - Git integration
   - Container development
   - Language support

3. Settings & Configuration
   - Optimized editor settings
   - Custom keybindings
   - Workspace configuration

4. Container Support (Optional)
   - Browser-based code-server
   - Docker container with development tools
   - Persistent configuration and extensions

Quick Commands:
--------------
code .                   # Open current directory
code file.txt           # Open specific file
code --install-extension ext-id  # Install extension

Container Mode:
--------------
# Start code-server container
& "$env:DEVENV_DATA_DIR\containers\vscode\start-code-server.ps1"

# Access via browser at http://localhost:8443
# Password: set via DEVENV_VSCODE_PASSWORD env var

"@

    Write-Host $header -ForegroundColor Cyan
    
    # Show current installation status
    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow
    
    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component
        
        if ($isInstalled -and $isVerified) {
            Write-Host "+ $component`: Installed and verified" -ForegroundColor Green
            
            # Show additional info for specific components
            switch ($component) {
                'core' {
                    try {
                        $version = code --version 2>$null | Select-Object -First 1
                        Write-Host "  Version: $version" -ForegroundColor Gray
                    } catch {}
                }
                'extensions' {
                    try {
                        $extCount = (code --list-extensions 2>$null | Measure-Object -Line).Lines
                        Write-Host "  Extensions: $extCount installed" -ForegroundColor Gray
                    } catch {}
                }
                'container' {
                    $containerEnabled = Get-ModuleConfig $script:ModuleName ".global.container.modules.vscode.containerize"
                    if ($containerEnabled -eq $true) {
                        try {
                            $containerStatus = docker ps --filter "name=devenv-vscode" --format "{{.Status}}" 2>$null
                            if ($containerStatus) {
                                Write-Host "  Container: $containerStatus" -ForegroundColor Gray
                            } else {
                                Write-Host "  Container: Not running" -ForegroundColor Gray
                            }
                        } catch {
                            Write-Host "  Container: Docker not available" -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "  Container: Disabled" -ForegroundColor Gray
                    }
                }
            }
        } elseif ($isInstalled) {
            Write-Host "[WARN] $component`: Installed but not verified" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] $component`: Not installed" -ForegroundColor Red
        }
    }
    
    Write-Host ""
}
#endregion

#region Main Execution
try {
    switch ($Action.ToLower()) {
        'grovel' {
            exit (Test-ModuleInstallation ? 0 : 1)
        }
        'install' {
            $success = Install-Module
            if ($success) { exit 0 } else { exit 1 }
        }
        'remove' {
            $success = Remove-Module
            if ($success) { exit 0 } else { exit 1 }
        }
        'verify' {
            $success = Test-ModuleVerification
            if ($success) { exit 0 } else { exit 1 }
        }
        'info' {
            Show-ModuleInfo
            exit 0
        }
        default {
            Write-LogError "Unknown action: $Action" $script:ModuleName
            Write-LogError "Usage: $($MyInvocation.MyCommand.Name) {install|remove|verify|info|grovel} [-Force]" $script:ModuleName
            exit 1
        }
    }
}
catch {
    Write-LogError "Module execution failed: $_" $script:ModuleName
    Write-LogError "Stack trace: $($_.ScriptStackTrace)" $script:ModuleName
    exit 1
}
#endregion