# lib/windows/secrets.ps1 - Secrets management for DevEnv (Windows)
#
# Uses Windows DPAPI via ConvertTo-SecureString for encryption at rest.
# Secrets are stored in ~/.devenv/secrets/ as SecureString XML files.
#
# Environment variable overrides:
#   DEVENV_SECRET_<KEY> - Override any secret

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SecretsDir = Join-Path $env:USERPROFILE ".devenv" "secrets"

# Secret definitions
$script:SecretDefs = @(
    @{ Key = "git_name";          Description = "Git user name";                Type = "text";     Prompt = "Enter your Git name" }
    @{ Key = "git_email";         Description = "Git user email";               Type = "email";    Prompt = "Enter your Git email" }
    @{ Key = "github_token";      Description = "GitHub personal access token"; Type = "token";    Prompt = "Enter your GitHub token" }
    @{ Key = "anthropic_api_key"; Description = "Anthropic API key";            Type = "token";    Prompt = "Enter your Anthropic API key" }
    @{ Key = "ssh_passphrase";    Description = "SSH key passphrase";           Type = "password"; Prompt = "Enter SSH key passphrase" }
    @{ Key = "docker_hub_token";  Description = "Docker Hub access token";      Type = "token";    Prompt = "Enter your Docker Hub token" }
    @{ Key = "npm_token";         Description = "NPM auth token";              Type = "token";    Prompt = "Enter your NPM token" }
    @{ Key = "pypi_token";        Description = "PyPI API token";              Type = "token";    Prompt = "Enter your PyPI token" }
)

function Initialize-Secrets {
    if (-not (Test-Path $script:SecretsDir)) {
        New-Item -Path $script:SecretsDir -ItemType Directory -Force | Out-Null
        # Set restrictive ACL
        $acl = Get-Acl $script:SecretsDir
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $env:USERNAME, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl -Path $script:SecretsDir -AclObject $acl
        Write-Log "INFO" "Initialized secrets directory: $script:SecretsDir" "secrets"
    }
}

function Set-DevEnvSecret {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    Initialize-Secrets
    $secureString = ConvertTo-SecureString $Value -AsPlainText -Force
    $encrypted = ConvertFrom-SecureString $secureString
    $secretFile = Join-Path $script:SecretsDir "$Key.enc"
    Set-Content -Path $secretFile -Value $encrypted -Force
    Write-Log "INFO" "Stored secret: $Key" "secrets"
}

function Get-DevEnvSecret {
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$Default = ""
    )

    # Check environment variable override
    $envVar = "DEVENV_SECRET_$($Key.ToUpper())"
    $envValue = [Environment]::GetEnvironmentVariable($envVar)
    if ($envValue) { return $envValue }

    # Check encrypted file
    $secretFile = Join-Path $script:SecretsDir "$Key.enc"
    if (-not (Test-Path $secretFile)) {
        if ($Default) { return $Default }
        return $null
    }

    try {
        $encrypted = Get-Content -Path $secretFile -Raw
        $secureString = ConvertTo-SecureString $encrypted
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    catch {
        Write-Log "ERROR" "Failed to decrypt secret: $Key" "secrets"
        return $null
    }
}

function Show-Secrets {
    Initialize-Secrets
    Write-Host ""
    Write-Host "Stored Secrets"
    Write-Host "=============="

    foreach ($def in $script:SecretDefs) {
        $envVar = "DEVENV_SECRET_$($def.Key.ToUpper())"
        $envValue = [Environment]::GetEnvironmentVariable($envVar)
        $secretFile = Join-Path $script:SecretsDir "$($def.Key).enc"

        $status = "(not set)"
        if ($envValue) {
            $masked = $envValue.Substring(0, [Math]::Min(3, $envValue.Length)) + "***"
            $status = "$masked (env override)"
        }
        elseif (Test-Path $secretFile) {
            $status = "[encrypted]"
        }

        Write-Host ("  {0,-20} {1,-30} {2}" -f $def.Key, $def.Description, $status)
    }
    Write-Host ""
}

function Reset-Secrets {
    param([string]$Key = "")
    Initialize-Secrets

    if ($Key) {
        $secretFile = Join-Path $script:SecretsDir "$Key.enc"
        if (Test-Path $secretFile) {
            Remove-Item $secretFile -Force
            Write-Log "INFO" "Removed secret: $Key" "secrets"
        }
        else {
            Write-Log "WARN" "Secret not found: $Key" "secrets"
        }
    }
    else {
        $confirm = Read-Host "Remove ALL stored secrets? [y/N]"
        if ($confirm -match '^[Yy]$') {
            Get-ChildItem "$script:SecretsDir/*.enc" | Remove-Item -Force
            Write-Log "INFO" "All secrets removed" "secrets"
        }
    }
}

function Invoke-SecretsWizard {
    Initialize-Secrets
    Write-Host ""
    Write-Host "DevEnv Secrets Wizard"
    Write-Host "====================="
    Write-Host "Configure credentials for your development environment."
    Write-Host "Press Enter to skip any secret, Ctrl+C to abort."
    Write-Host ""

    foreach ($def in $script:SecretDefs) {
        $secretFile = Join-Path $script:SecretsDir "$($def.Key).enc"
        $existing = if (Test-Path $secretFile) { "[stored]" } else { "" }

        if ($def.Type -in @("password", "token")) {
            $secure = Read-Host "$($def.Prompt) $existing" -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        else {
            $value = Read-Host "$($def.Prompt) $existing"
        }

        if ($value) {
            Set-DevEnvSecret -Key $def.Key -Value $value
        }
        elseif ($existing) {
            Write-Host "  Keeping existing value."
        }
        else {
            Write-Host "  Skipped."
        }
    }

    Write-Host ""
    Write-Host "Secrets wizard complete. Use 'devenv secrets show' to review."
}

function Invoke-SecretsCommand {
    param(
        [string]$Action = "wizard",
        [string[]]$Arguments = @()
    )

    switch ($Action) {
        "wizard"   { Invoke-SecretsWizard }
        "show"     { Show-Secrets }
        "set"      {
            if ($Arguments.Count -lt 1) { Write-Error "Usage: devenv secrets set <key> [value]"; return }
            $value = if ($Arguments.Count -ge 2) { $Arguments[1] } else { Read-Host "Enter value for $($Arguments[0])" }
            Set-DevEnvSecret -Key $Arguments[0] -Value $value
        }
        "reset"    { Reset-Secrets -Key ($Arguments | Select-Object -First 1) }
        "validate" {
            Initialize-Secrets
            Write-Host "Validating stored secrets..."
            foreach ($def in $script:SecretDefs) {
                $secretFile = Join-Path $script:SecretsDir "$($def.Key).enc"
                if (Test-Path $secretFile) {
                    $val = Get-DevEnvSecret -Key $def.Key
                    if ($val) { Write-Host "  $($def.Key): OK" }
                    else { Write-Host "  $($def.Key): FAILED" }
                }
            }
        }
        default {
            Write-Host "Usage: devenv secrets [wizard|show|set|reset|validate]"
        }
    }
}
