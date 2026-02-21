#region Command Routing
function Invoke-ModeAwareCommand {
    <#
    .SYNOPSIS
        Routes commands based on execution mode
    #>
    param(
        [string]$Action,
        [string[]]$Modules,
        [hashtable]$DevEnvContext
    )

    Write-Host "Executing: " -NoNewline -ForegroundColor Gray
    Write-Host $Action -NoNewline -ForegroundColor White
    if ($Modules) {
        Write-Host " [$($Modules -join ', ')]" -NoNewline -ForegroundColor Cyan
    }
    Write-Host " in $($DevEnvContext.Mode) mode" -ForegroundColor Gray
    Write-Host ""

    switch ($Action) {
        'info' {
            # Check if specific module info requested
            if ($Modules -and @($Modules).Count -eq 1) {
                # Show specific module info
                if (-not (Initialize-ModuleSystem $DevEnvContext)) {
                    Write-Host "Failed to initialize module system" -ForegroundColor Red
                    return
                }

                $availableModules = Get-AvailableModules
                $requestedModule = $availableModules | Where-Object { $_.Name -eq $Modules[0] }

                if ($requestedModule) {
                    try {
                        Write-Host ""
                        Write-Host "Module: $($requestedModule.Name)" -ForegroundColor Cyan
                        Write-Host "=======$('=' * $requestedModule.Name.Length)" -ForegroundColor Cyan

                        # Execute module info command
                        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $requestedModule.Script "info"

                    } catch {
                        Write-Host "Failed to get module information: $_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "Module not found: $($Modules[0])" -ForegroundColor Red
                    Write-Host "Use 'devenv.ps1 list' to see available modules" -ForegroundColor Gray
                }
            } else {
                Show-ModeAwareInfo $DevEnvContext
            }
        }

        'status' {
            Show-ModeAwareStatus $DevEnvContext
        }

        'create-project' {
            if ($DevEnvContext.Mode -eq "Project") {
                throw "Cannot create project from project mode. Use global DevEnv."
            }

            if (-not $Name) {
                $Name = Read-Host "Enter project name"
            }

            $params = @{
                ProjectName = $Name
                Template = $Template
            }

            if ($ProjectPath) { $params["ProjectPath"] = $ProjectPath }
            if ($Description) { $params["Description"] = $Description }

            New-DevEnvProject @params
        }

        'install' {
            try {
                Invoke-ModuleInstallation -RequestedModules $Modules -Force $Force -DevEnvContext $DevEnvContext
            } catch {
                Write-Host ""
                Write-Host "Installation failed: $_" -ForegroundColor Red
                exit 1
            }
        }

        'list' {
            # Enhanced list showing available modules with status
            if (-not (Initialize-ModuleSystem $DevEnvContext)) {
                Write-Host "Failed to initialize module system" -ForegroundColor Red
                return
            }

            $availableModules = Get-AvailableModules

            Write-Host ""
            Write-Host "Available Modules" -ForegroundColor Cyan
            Write-Host "=================" -ForegroundColor Cyan
            Write-Host ""

            if (@($availableModules).Count -eq 0) {
                Write-Host "No modules found" -ForegroundColor Yellow
                return
            }

            foreach ($module in ($availableModules | Sort-Object Runlevel, Name)) {
                $isInstalled = Test-ModuleInstallation $module $DevEnvContext
                $statusIcon = if ($isInstalled) { "[+]" } else { "[ ]" }
                $statusColor = if ($isInstalled) { "Green" } else { "Gray" }

                Write-Host "$statusIcon " -NoNewline -ForegroundColor $statusColor
                Write-Host $module.Name -NoNewline -ForegroundColor Cyan
                Write-Host " (runlevel $($module.Runlevel))" -ForegroundColor Gray

                # Try to get description from module config
                if (Test-Path $module.Config) {
                    try {
                        $config = Get-Content $module.Config | ConvertFrom-Json
                        if ($config.description) {
                            Write-Host "    $($config.description)" -ForegroundColor Gray
                        }
                    } catch {
                        # Ignore config parsing errors for list
                    }
                }
            }

            Write-Host ""
            Write-Host "Legend: [+] Installed, [ ] Not installed" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Usage:" -ForegroundColor Yellow
            Write-Host "  devenv.ps1 install                    # Install all modules" -ForegroundColor White
            Write-Host "  devenv.ps1 install git vscode         # Install specific modules" -ForegroundColor White
            Write-Host "  devenv.ps1 install -Force             # Force reinstall all" -ForegroundColor White
            Write-Host ""
        }

        'verify' {
            # Implementation for verify command
            if (-not (Initialize-ModuleSystem $DevEnvContext)) {
                Write-Host "Failed to initialize module system" -ForegroundColor Red
                return
            }

            $availableModules = Get-AvailableModules
            $installedModules = $availableModules | Where-Object { Test-ModuleInstallation $_ $DevEnvContext }

            Write-Host ""
            Write-Host "DevEnv Verification" -ForegroundColor Cyan
            Write-Host "==================" -ForegroundColor Cyan
            Write-Host ""

            if (@($installedModules).Count -eq 0) {
                Write-Host "No modules installed to verify" -ForegroundColor Yellow
                return
            }

            $verifyCount = 0
            $failCount = 0

            foreach ($module in $installedModules) {
                Write-Host "Verifying $($module.Name)... " -NoNewline

                try {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $module.Script "verify" *>$null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "OK" -ForegroundColor Green
                        $verifyCount++
                    } else {
                        Write-Host "FAILED" -ForegroundColor Red
                        $failCount++
                    }
                } catch {
                    Write-Host "ERROR" -ForegroundColor Red
                    $failCount++
                }
            }

            Write-Host ""
            Write-Host "Verification Summary:" -ForegroundColor Cyan
            Write-Host "Passed: $verifyCount" -ForegroundColor Green
            Write-Host "Failed: $failCount" -ForegroundColor Red

            if ($failCount -gt 0) {
                Write-Host ""
                Write-Host "Run 'devenv.ps1 install -Force' to repair failed modules" -ForegroundColor Yellow
                exit 1
            }
        }

        default {
            Write-Host "Command '$Action' not yet implemented in dual-mode system" -ForegroundColor Yellow
        }
    }
}
#endregion
