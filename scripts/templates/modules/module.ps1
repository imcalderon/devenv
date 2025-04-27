# modules/module.ps1 - Example module implementation for Windows

param (
    [Parameter(Position=0)]
    [string]$Action,
    
    [Parameter(Position=1)]
    [switch]$Force
)

# Load required utilities
. "$PSScriptRoot\..\..\lib\windows\logging.ps1"
. "$PSScriptRoot\..\..\lib\windows\json.ps1"
. "$PSScriptRoot\..\..\lib\windows\module.ps1"
. "$PSScriptRoot\..\..\lib\windows\backup.ps1"
. "$PSScriptRoot\..\..\lib\windows\alias.ps1"

# Initialize module
Initialize-Module "example"

# State file for tracking installation status
$STATE_FILE = "$env:USERPROFILE\.devenv\state\example.state"

# Define module components
$COMPONENTS = @(
    "core",     # Base installation
    "config"    # Configuration
)

# Display module information
function Show-ModuleInfo {
    Write-Host ""
    Write-Host "📦 Module: Example" -ForegroundColor Cyan
    Write-Host "================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Description:" -ForegroundColor Cyan
    Write-Host "-----------"
    Write-Host "Detailed description of what this module does and its primary purpose."
    Write-Host ""
    Write-Host "Benefits:" -ForegroundColor Cyan
    Write-Host "--------"
    Write-Host "✓ Benefit 1 - Detail about the first benefit"
    Write-Host "✓ Benefit 2 - Detail about the second benefit"
    Write-Host "✓ Benefit 3 - Detail about the third benefit"
    Write-Host ""
    Write-Host "Components:" -ForegroundColor Cyan
    Write-Host "----------"
    Write-Host "1. Core System"
    Write-Host "   - What the core system provides"
    Write-Host "   - Dependencies and requirements"
    Write-Host ""
    Write-Host "2. Configuration"
    Write-Host "   - What configurations are managed"
    Write-Host "   - Where configs are stored"
    Write-Host ""
    Write-Host "Quick Start:" -ForegroundColor Cyan
    Write-Host "-----------"
    Write-Host "1. Initial setup:"
    Write-Host "   > devenv install example"
    Write-Host ""

    # Show current installation status
    Write-Host "Current Status:" -ForegroundColor Cyan
    Write-Host "-------------"
    foreach ($component in $COMPONENTS) {
        if (Test-ComponentState $component) {
            Write-Host "✓ ${component}: Installed" -ForegroundColor Green
            # Show version if applicable
            switch ($component) {
                "core" {
                    try {
                        $version = "unknown"
                        # Example of how to get version info
                        # $version = (Get-Command example -ErrorAction SilentlyContinue).Version
                        if ($version) {
                            Write-Host "  Version: $version" -ForegroundColor Gray
                        }
                    } catch {}
                }
            }
        } else {
            Write-Host "✗ ${component}: Not installed" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Save component state
function Save-ComponentState {
    param (
        [string]$Component,
        [string]$Status
    )
    
    New-Item -Path (Split-Path $STATE_FILE -Parent) -ItemType Directory -Force | Out-Null
    Add-Content -Path $STATE_FILE -Value "$Component`:$Status`:"$(Get-Date -UFormat "%s")
}

# Check component state
function Test-ComponentState {
    param ([string]$Component)
    
    if (Test-Path $STATE_FILE) {
        $content = Get-Content $STATE_FILE
        return ($content -match "^$Component`:installed:")
    }
    return $false
}

# Install specific component
function Install-Component {
    param ([string]$Component)
    
    if ((Test-ComponentState $Component) -and (Test-Component $Component)) {
        Write-LogInfo "Component $Component already installed and verified" "example"
        return $true
    }
    
    switch ($Component) {
        "core" {
            if (Install-Core) {
                Save-ComponentState "core" "installed"
                return $true
            }
        }
        "config" {
            if (Install-Config) {
                Save-ComponentState "config" "installed"
                return $true
            }
        }
    }
    return $false
}

# Install core component
function Install-Core {
    Write-LogInfo "Installing example core..." "example"
    
    # Implementation specific to Windows
    # Example: installing via Chocolatey
    try {
        # Check if example is already installed
        $installed = $false
        # Example check: $installed = Get-Command example -ErrorAction SilentlyContinue
        
        if (-not $installed) {
            # Install the example package
            # Example: choco install example -y
            
            # For demonstration, we'll just create a dummy file
            $exampleDir = "$env:USERPROFILE\.example"
            New-Item -Path $exampleDir -ItemType Directory -Force | Out-Null
            New-Item -Path "$exampleDir\example.txt" -ItemType File -Force | Out-Null
        }
        
        return $true
    } catch {
        Write-LogError "Failed to install example core: $_" "example"
        return $false
    }
}

# Install configuration
function Install-Config {
    Write-LogInfo "Configuring example..." "example"
    
    try {
        # Get configuration path from module config
        $configPath = Get-ModuleConfig "example" ".platforms.windows.shell.paths.config_dir"
        $configPath = [System.Environment]::ExpandEnvironmentVariables($configPath)
        
        # Create configuration directory
        New-Item -Path $configPath -ItemType Directory -Force | Out-Null
        
        # Create basic configuration file
        $configFile = "$configPath\config.json"
        
        # Example JSON configuration
        $configContent = @"
{
    "exampleSetting": true,
    "examplePath": "$env:USERPROFILE\\.example",
    "options": {
        "option1": "value1",
        "option2": "value2"
    }
}
"@
        
        Set-Content -Path $configFile -Value $configContent
        
        return $true
    } catch {
        Write-LogError "Failed to configure example: $_" "example"
        return $false
    }
}

# Verify specific component
function Test-Component {
    param ([string]$Component)
    
    switch ($Component) {
        "core" {
            # Verify core installation
            # Example: Test-Path "$env:USERPROFILE\.example\example.txt"
            return $true
        }
        "config" {
            # Verify configuration
            $configPath = Get-ModuleConfig "example" ".platforms.windows.shell.paths.config_dir"
            $configPath = [System.Environment]::ExpandEnvironmentVariables($configPath)
            return (Test-Path "$configPath\config.json")
        }
        default {
            return $false
        }
    }
}

# Grovel checks existence and basic functionality
function Test-Example {
    $status = $true
    
    foreach ($component in $COMPONENTS) {
        if (-not (Test-ComponentState $component) -or -not (Test-Component $component)) {
            Write-LogInfo "Component $component needs installation" "example"
            $status = $false
        }
    }
    
    return $status
}

# Install with state awareness
function Install-Example {
    param ([bool]$Force = $false)
    
    if ($Force -or -not (Test-Example)) {
        New-Backup
    }
    
    foreach ($component in $COMPONENTS) {
        if ($Force -or -not (Test-ComponentState $component) -or -not (Test-Component $component)) {
            Write-LogInfo "Installing component: $component" "example"
            if (-not (Install-Component $component)) {
                Write-LogError "Failed to install component: $component" "example"
                return $false
            }
        } else {
            Write-LogInfo "Skipping already installed and verified component: $component" "example"
        }
    }
    
    # Show module information after successful installation
    Show-ModuleInfo
    
    return $true
}

# Remove module configuration
function Remove-Example {
    Write-LogInfo "Removing example configuration..." "example"
    
    try {
        # Get configuration path from module config
        $configPath = Get-ModuleConfig "example" ".platforms.windows.shell.paths.config_dir"
        $configPath = [System.Environment]::ExpandEnvironmentVariables($configPath)
        
        # Backup existing configuration
        if (Test-Path "$configPath\config.json") {
            Backup-File "$configPath\config.json" "example"
        }
        
        # Remove configuration directory
        if (Test-Path $configPath) {
            Remove-Item -Path $configPath -Recurse -Force
        }
        
        # Remove example directory
        $exampleDir = "$env:USERPROFILE\.example"
        if (Test-Path $exampleDir) {
            Remove-Item -Path $exampleDir -Recurse -Force
        }
        
        # Remove state file
        if (Test-Path $STATE_FILE) {
            Remove-Item -Path $STATE_FILE -Force
        }
        
        return $true
    } catch {
        Write-LogError "Failed to remove example configuration: $_" "example"
        return $false
    }
}

# Verify entire installation
function Verify-Example {
    $status = $true
    
    foreach ($component in $COMPONENTS) {
        if (-not (Test-Component $component)) {
            Write-LogError "Verification failed for component: $component" "example"
            $status = $false
        }
    }
    
    if ($status) {
        Write-LogInfo "Example verification completed successfully" "example"
    }
    
    return $status
}

# Execute requested action
switch ($Action) {
    "grovel" {
        Test-Example
    }
    "install" {
        Install-Example $Force
    }
    "verify" {
        Verify-Example
    }
    "info" {
        Show-ModuleInfo
    }
    "remove" {
        Remove-Example
    }
    default {
        Write-LogError "Unknown action: $Action" "example"
        Write-LogError "Usage: .\example.ps1 {install|remove|verify|info} [-Force]"
        exit 1
    }
}