#Requires -Version 5.1
<#
.SYNOPSIS
    Git Module for DevEnv - Windows implementation
.DESCRIPTION
    Configures Git for Windows with SSH key management, Git Credential Manager,
    posh-git prompt integration, and productivity aliases.
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

$script:ModuleName = "git"
$script:StateFile = Join-Path $env:DEVENV_STATE_DIR "$($script:ModuleName).state"
$script:ConfigFile = Join-Path $env:DEVENV_MODULES_DIR "$($script:ModuleName)\config.json"

$null = Initialize-Module $script:ModuleName

$script:Components = @(
    'core',         # Git installation verification
    'ssh',          # SSH key and agent configuration
    'config',       # Git global configuration
    'posh_git',     # posh-git prompt integration
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
            try {
                $null = git --version 2>$null
                return $LASTEXITCODE -eq 0
            } catch {
                return $false
            }
        }
        'ssh' {
            $sshDir = Join-Path $env:USERPROFILE ".ssh"
            $keyFile = Join-Path $sshDir "id_ed25519"
            $configFile = Join-Path $sshDir "config"
            return (Test-Path $keyFile) -and (Test-Path $configFile)
        }
        'config' {
            try {
                $branch = git config --global init.defaultBranch 2>$null
                return ($null -ne $branch) -and ($branch.Length -gt 0)
            } catch {
                return $false
            }
        }
        'posh_git' {
            return (Get-Module -ListAvailable -Name posh-git) -ne $null
        }
        'aliases' {
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
    Write-LogInfo "Verifying Git installation..." $script:ModuleName

    try {
        $gitVersion = git --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Git is installed: $gitVersion" $script:ModuleName
            return $true
        }
    } catch {}

    # Attempt install via winget
    try {
        Write-LogInfo "Installing Git via winget..." $script:ModuleName
        winget.exe install --exact --id Git.Git --silent --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-LogInfo "Git installed successfully via winget" $script:ModuleName

            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            Start-Sleep -Seconds 3

            try {
                $gitVersion = git --version 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-LogInfo "Git installation verified: $gitVersion" $script:ModuleName
                    return $true
                }
            } catch {}

            Write-LogWarning "Git installed but could not be verified immediately. Restart your shell." $script:ModuleName
            return $true
        }
    } catch {
        Write-LogError "Failed to install Git: $_" $script:ModuleName
    }

    Write-LogError "Git installation failed" $script:ModuleName
    return $false
}

function Install-SshComponent {
    Write-LogInfo "Configuring SSH..." $script:ModuleName

    try {
        $sshDir = Join-Path $env:USERPROFILE ".ssh"

        # Create SSH directory
        if (-not (Test-Path $sshDir)) {
            New-Item -Path $sshDir -ItemType Directory -Force | Out-Null
        }

        $keyFile = Join-Path $sshDir "id_ed25519"

        # Generate SSH key if it doesn't exist
        if (-not (Test-Path $keyFile)) {
            Write-LogInfo "Generating ED25519 SSH key..." $script:ModuleName

            $gitEmail = Get-ModuleConfig $script:ModuleName ".git.config.`"user.email`""
            if ([string]::IsNullOrWhiteSpace($gitEmail)) {
                $gitEmail = git config --global user.email 2>$null
            }
            if ([string]::IsNullOrWhiteSpace($gitEmail)) {
                $gitEmail = "devenv@localhost"
                Write-LogWarning "No email configured, using placeholder: $gitEmail" $script:ModuleName
            }

            ssh-keygen -t ed25519 -C $gitEmail -f $keyFile -N '""'

            if ($LASTEXITCODE -ne 0) {
                Write-LogError "Failed to generate SSH key" $script:ModuleName
                return $false
            }

            Write-LogInfo "SSH key generated at: $keyFile" $script:ModuleName
        } else {
            Write-LogInfo "SSH key already exists: $keyFile" $script:ModuleName
        }

        # Configure SSH config for GitHub
        $sshConfig = Join-Path $sshDir "config"

        if (Test-Path $sshConfig) {
            Backup-File $sshConfig $script:ModuleName
        }

        $sshHosts = Get-ModuleConfig $script:ModuleName ".git.ssh.hosts"

        $configContent = "# SSH configuration managed by devenv`r`n`r`n"

        if ($sshHosts) {
            foreach ($hostEntry in $sshHosts) {
                $hostName = $hostEntry.host
                $hostUser = $hostEntry.user
                $identityFile = $hostEntry.identity_file -replace '\$HOME', $env:USERPROFILE

                $configContent += "Host $hostName`r`n"
                $configContent += "    User $hostUser`r`n"
                $configContent += "    IdentityFile $identityFile`r`n"
                $configContent += "    IdentitiesOnly yes`r`n"
                $configContent += "`r`n"
            }
        } else {
            # Default GitHub configuration
            $configContent += "Host github.com`r`n"
            $configContent += "    User git`r`n"
            $configContent += "    IdentityFile $keyFile`r`n"
            $configContent += "    IdentitiesOnly yes`r`n"
            $configContent += "`r`n"
        }

        Set-Content -Path $sshConfig -Value $configContent -Encoding UTF8

        # Start Windows OpenSSH agent service and add key
        try {
            $agentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
            if ($agentService) {
                if ($agentService.Status -ne 'Running') {
                    if ($agentService.StartType -eq 'Disabled') {
                        Write-LogInfo "Enabling ssh-agent service..." $script:ModuleName
                        Set-Service ssh-agent -StartupType Manual
                    }
                    Start-Service ssh-agent
                    Write-LogInfo "Started ssh-agent service" $script:ModuleName
                }

                # Add key to agent
                ssh-add $keyFile 2>$null
                Write-LogInfo "Added SSH key to agent" $script:ModuleName
            } else {
                Write-LogWarning "OpenSSH agent service not found. Install OpenSSH optional feature." $script:ModuleName
            }
        } catch {
            Write-LogWarning "Could not configure ssh-agent: $_" $script:ModuleName
        }

        # Add github.com to known_hosts
        $knownHosts = Join-Path $sshDir "known_hosts"
        try {
            $githubKeys = ssh-keyscan github.com 2>$null
            if ($githubKeys) {
                Add-Content -Path $knownHosts -Value $githubKeys
                Write-LogInfo "Added github.com to known_hosts" $script:ModuleName
            }
        } catch {
            Write-LogWarning "Could not scan github.com SSH keys" $script:ModuleName
        }

        return $true
    } catch {
        Write-LogError "Error configuring SSH: $_" $script:ModuleName
        return $false
    }
}

function Install-ConfigComponent {
    Write-LogInfo "Configuring Git..." $script:ModuleName

    try {
        # Read base git config directly (not via Get-ModuleConfig which returns
        # the platform-specific section first, shadowing the full base config)
        $baseConfig = Get-JsonValue $script:ConfigFile ".git.config" $null $script:ModuleName

        # Read Windows-specific overrides
        $windowsOverrides = Get-JsonValue $script:ConfigFile ".platforms.windows.git.config" $null $script:ModuleName

        # Build merged config: base + Windows overrides
        $mergedConfig = @{}
        if ($baseConfig) {
            foreach ($prop in $baseConfig.PSObject.Properties) {
                $mergedConfig[$prop.Name] = $prop.Value
            }
        }
        if ($windowsOverrides) {
            foreach ($prop in $windowsOverrides.PSObject.Properties) {
                $mergedConfig[$prop.Name] = $prop.Value
            }
        }

        foreach ($key in $mergedConfig.Keys) {
            $value = $mergedConfig[$key]

            # Handle empty values that need user input
            if ([string]::IsNullOrWhiteSpace($value)) {
                switch ($key) {
                    "user.name" {
                        $value = git config --global user.name 2>$null
                        if ([string]::IsNullOrWhiteSpace($value)) {
                            Write-LogWarning "Git user.name not set. Run: git config --global user.name 'Your Name'" $script:ModuleName
                            continue
                        }
                    }
                    "user.email" {
                        $value = git config --global user.email 2>$null
                        if ([string]::IsNullOrWhiteSpace($value)) {
                            Write-LogWarning "Git user.email not set. Run: git config --global user.email 'you@example.com'" $script:ModuleName
                            continue
                        }
                    }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                git config --global $key $value
                Write-LogInfo "Set git config $key = $value" $script:ModuleName
            }
        }

        return $true
    } catch {
        Write-LogError "Error configuring Git: $_" $script:ModuleName
        return $false
    }
}

function Install-PoshGitComponent {
    Write-LogInfo "Installing posh-git..." $script:ModuleName

    try {
        # Check if posh-git is already installed
        if (Get-Module -ListAvailable -Name posh-git) {
            Write-LogInfo "posh-git is already installed" $script:ModuleName
        } else {
            # Install posh-git from PSGallery
            Write-LogInfo "Installing posh-git from PSGallery..." $script:ModuleName

            # Ensure NuGet provider is available (avoids interactive prompt)
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue

            # Use Save-Module + copy to avoid ShouldContinue issues in non-interactive sessions
            $tempDir = Join-Path $env:TEMP "devenv-posh-git"
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            PowerShellGet\Save-Module -Name posh-git -Path $tempDir -Force
            $userModulesDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell\Modules"
            if (-not (Test-Path $userModulesDir)) {
                New-Item -Path $userModulesDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path (Join-Path $tempDir "posh-git") -Destination $userModulesDir -Recurse -Force
            Remove-Item $tempDir -Recurse -Force

            Write-LogInfo "posh-git installed successfully" $script:ModuleName
        }

        # Add posh-git to PowerShell profile
        $profilePath = $PROFILE.CurrentUserAllHosts

        if (-not (Test-Path (Split-Path $profilePath -Parent))) {
            New-Item -Path (Split-Path $profilePath -Parent) -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path $profilePath)) {
            Set-Content -Path $profilePath -Value "# PowerShell Profile`n" -Force
        }

        $profileContent = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue

        if (-not $profileContent -or -not ($profileContent -match "Import-Module posh-git")) {
            $poshGitCode = "`r`n# posh-git (DevEnv)`r`nif (Get-Module -ListAvailable -Name posh-git) {`r`n    Import-Module posh-git`r`n}`r`n"
            Add-Content -Path $profilePath -Value $poshGitCode
            Write-LogInfo "Added posh-git to PowerShell profile" $script:ModuleName
        }

        return $true
    } catch {
        Write-LogError "Error installing posh-git: $_" $script:ModuleName
        return $false
    }
}

function Install-AliasesComponent {
    Write-LogInfo "Installing Git aliases..." $script:ModuleName

    # Add module aliases from config
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"

    if ($aliasCategories) {
        foreach ($category in $aliasCategories) {
            if (Add-ModuleAliases $script:ModuleName $category) {
                Write-LogInfo "Added aliases for category: $category" $script:ModuleName
            } else {
                Write-LogWarning "Failed to add aliases for category: $category" $script:ModuleName
            }
        }
    } else {
        # Try adding aliases without category (flat structure)
        if (Add-ModuleAliases $script:ModuleName "git") {
            Write-LogInfo "Added git aliases" $script:ModuleName
        } else {
            Write-LogWarning "Failed to add git aliases" $script:ModuleName
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
        'ssh' { Install-SshComponent }
        'config' { Install-ConfigComponent }
        'posh_git' { Install-PoshGitComponent }
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
    Write-LogInfo "Checking Git module installation status..." $script:ModuleName

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
            # posh_git is optional
            if ($component -eq 'posh_git') {
                Write-LogWarning "Optional component $component skipped" $script:ModuleName
            } else {
                Write-LogError "Failed to install component: $component" $script:ModuleName
                return $false
            }
        }
    }

    Write-LogInfo "Git module installation completed successfully" $script:ModuleName
    Show-ModuleInfo

    return $true
}

function Remove-Module {
    Write-LogInfo "Removing $($script:ModuleName) module..." $script:ModuleName

    # Create backup before removal
    New-Backup $script:ModuleName

    # Remove git aliases
    $aliasCategories = Get-ModuleConfig $script:ModuleName ".shell.aliases | keys[]"
    if ($aliasCategories) {
        foreach ($category in $aliasCategories) {
            Remove-ModuleAliases $script:ModuleName $category
        }
    } else {
        Remove-ModuleAliases $script:ModuleName "git"
    }

    # Remove posh-git from profile
    $profilePath = $PROFILE.CurrentUserAllHosts
    if (Test-Path $profilePath) {
        $content = Get-Content -Path $profilePath -Raw
        $content = $content -replace "(?s)# posh-git \(DevEnv\).*?Import-Module posh-git\r?\n\}\r?\n", ""
        Set-Content -Path $profilePath -Value $content -Force
    }

    # Remove SSH config but preserve keys
    $sshConfig = Join-Path $env:USERPROFILE ".ssh\config"
    if (Test-Path $sshConfig) {
        Backup-File $sshConfig $script:ModuleName
        Remove-Item $sshConfig -Force
    }

    # Remove state file
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
    }

    Write-LogInfo "Git module configuration removed" $script:ModuleName
    Write-LogWarning "SSH keys and .gitconfig were preserved. Remove manually if needed." $script:ModuleName

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
        Write-LogInfo "Git module verification completed successfully" $script:ModuleName

        try {
            $version = git --version 2>$null
            Write-LogInfo "Git version: $version" $script:ModuleName
        } catch {
            Write-LogWarning "Could not determine Git version" $script:ModuleName
        }

        # Test GitHub SSH connection
        try {
            $sshResult = ssh -T git@github.com -o BatchMode=yes -o StrictHostKeyChecking=no 2>&1
            if ($sshResult -match "successfully authenticated") {
                Write-LogInfo "GitHub SSH connection successful" $script:ModuleName
            } else {
                Write-LogWarning "GitHub SSH not configured - add your SSH key to GitHub" $script:ModuleName
            }
        } catch {
            Write-LogWarning "Could not test GitHub SSH connection" $script:ModuleName
        }
    }

    return $allVerified
}

function Show-ModuleInfo {
    $header = @"

Git Development Environment (Windows)
======================================

Description:
-----------
Professional Git environment with SSH key management,
Git Credential Manager, posh-git prompt integration, and productivity aliases.

Components:
----------
1. Core Git
   - Git for Windows (installed via winget)
   - Git Credential Manager

2. SSH Configuration
   - ED25519 key generation
   - GitHub SSH setup
   - Windows OpenSSH agent

3. Git Configuration
   - Global settings (user, editor, branch)
   - Windows-specific (autocrlf, credential manager)

4. posh-git Integration
   - Git status in PowerShell prompt
   - Tab completion for git commands

5. Aliases
   - Productivity aliases (g, ga, gst, gc, gp, etc.)

Quick Commands:
--------------
gst                      # Git status
ga file.txt              # Git add
gc -m "message"          # Git commit
gp                       # Git push
glg                      # Git log graph

"@

    Write-Host $header -ForegroundColor Cyan

    Write-Host "Current Status:" -ForegroundColor Yellow
    Write-Host "-------------" -ForegroundColor Yellow

    foreach ($component in $script:Components) {
        $isInstalled = Test-ComponentState $component
        $isVerified = Test-Component $component

        if ($isInstalled -and $isVerified) {
            Write-Host "+ $component`: Installed and verified" -ForegroundColor Green

            switch ($component) {
                'core' {
                    try {
                        $version = git --version 2>$null
                        Write-Host "  Version: $version" -ForegroundColor Gray
                    } catch {}
                }
                'ssh' {
                    $keyFile = Join-Path $env:USERPROFILE ".ssh\id_ed25519"
                    if (Test-Path $keyFile) {
                        Write-Host "  SSH Key: Present" -ForegroundColor Gray
                    }
                }
                'posh_git' {
                    $poshGit = Get-Module -ListAvailable -Name posh-git
                    if ($poshGit) {
                        Write-Host "  Version: $($poshGit.Version)" -ForegroundColor Gray
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
            if (Test-ModuleInstallation) { exit 0 } else { exit 1 }
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
