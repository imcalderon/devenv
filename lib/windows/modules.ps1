#region Module Management Integration
function Initialize-ModuleSystem {
    <#
    .SYNOPSIS
        Loads the DevEnv module management system
    #>
    param([hashtable]$DevEnvContext)

    $script:ROOT_DIR = $env:DEVENV_ROOT
    $script:MODULES_DIR = Join-Path $script:ROOT_DIR "modules"
    $script:LIB_DIR = Join-Path $script:ROOT_DIR "lib\windows"

    # Load Windows utilities
    $requiredLibs = @(
        'logging.ps1',
        'json.ps1',
        'module.ps1',
        'backup.ps1',
        'alias.ps1'
    )

    foreach ($lib in $requiredLibs) {
        $libPath = Join-Path $script:LIB_DIR $lib
        if (Test-Path $libPath) {
            . $libPath
            Write-Verbose "Loaded library: $lib"
        } else {
            Write-Warning "Required library not found: $libPath"
            return $false
        }
    }

    # Initialize logging for DevEnv core
    Initialize-Logging "devenv"

    return $true
}

function Get-AvailableModules {
    <#
    .SYNOPSIS
        Gets list of available modules from the modules directory
    #>

    $availableModules = @()

    if (Test-Path $script:MODULES_DIR) {
        $moduleDirectories = Get-ChildItem $script:MODULES_DIR -Directory

        foreach ($moduleDir in $moduleDirectories) {
            $moduleName = $moduleDir.Name
            $moduleScript = Join-Path $moduleDir.FullName "$moduleName.ps1"
            $moduleConfig = Join-Path $moduleDir.FullName "config.json"

            # Check if module has Windows PowerShell implementation
            if (Test-Path $moduleScript) {
                $isEnabled = $true

                # Check if module is enabled in config
                if (Test-Path $moduleConfig) {
                    try {
                        $config = Get-Content $moduleConfig | ConvertFrom-Json
                        $isEnabled = $config.enabled -eq $true

                        # Check Windows platform support
                        if ($config.platforms -and $config.platforms.windows) {
                            $isEnabled = $isEnabled -and ($config.platforms.windows.enabled -eq $true)
                        }
                    } catch {
                        Write-Warning "Failed to parse config for module: $moduleName"
                    }
                }

                if ($isEnabled) {
                    $availableModules += @{
                        Name = $moduleName
                        Script = $moduleScript
                        Config = $moduleConfig
                        Runlevel = if (Test-Path $moduleConfig) {
                            try {
                                $cfg = Get-Content $moduleConfig | ConvertFrom-Json
                                if ($cfg.runlevel) { $cfg.runlevel } else { 999 }
                            } catch { 999 }
                        } else { 999 }
                    }
                }
            }
        }
    }

    return $availableModules
}

function Get-ModuleExecutionOrder {
    <#
    .SYNOPSIS
        Gets modules in proper execution order based on configuration and runlevels
    #>
    param(
        [string[]]$RequestedModules = @(),
        [hashtable]$DevEnvContext
    )

    $availableModules = Get-AvailableModules

    # ensure we always have an array, even if empty
    if (-not $RequestedModules) {
        $RequestedModules = @()
    }

    # If specific modules requested, filter to those
    if (@($RequestedModules).Count -gt 0) {
        $filteredModules = @()
        foreach ($requested in $RequestedModules) {
            $module = $availableModules | Where-Object { $_.Name -eq $requested }
            if ($module) {
                $filteredModules += $module
            } else {
                Write-Warning "Module not found or not available: $requested"
            }
        }
        $availableModules = $filteredModules
    } else {
        # Use configured order from config.json
        # First try platform-specific order
        $configOrder = $null
        $platform = "windows"  # Since this is the PowerShell version

        if ($script:Config -and $script:Config.platforms -and $script:Config.platforms.$platform -and
            $script:Config.platforms.$platform.modules -and $script:Config.platforms.$platform.modules.order) {
            $configOrder = $script:Config.platforms.$platform.modules.order
        }

        # Fallback to global order if it exists
        if (-not $configOrder -and $script:Config -and $script:Config.global -and
            $script:Config.global.modules -and $script:Config.global.modules.order) {
            $configOrder = $script:Config.global.modules.order
        }

        if ($configOrder) {
            $orderedModules = @()

            # Ensure configOrder is treated as array
            $configOrderArray = @($configOrder)

            # Add modules in configured order first
            foreach ($moduleName in $configOrderArray) {
                $module = $availableModules | Where-Object { $_.Name -eq $moduleName }
                if ($module) {
                    $orderedModules += $module
                }
            }

            # Add any remaining modules not in the configured order
            foreach ($module in $availableModules) {
                if ($module.Name -notin $configOrderArray) {
                    $orderedModules += $module
                }
            }

            $availableModules = $orderedModules
        } else {
            # Fall back to runlevel ordering
            $availableModules = $availableModules | Sort-Object Runlevel, Name
        }
    }

    return @($availableModules)
}

function Test-ModuleInstallation {
    <#
    .SYNOPSIS
        Checks if a module is already installed
    #>
    param(
        [hashtable]$Module,
        [hashtable]$DevEnvContext
    )

    try {
        # Ensure Module is not null and has Script property
        if (-not $Module -or -not $Module.Script) {
            return $false
        }

        & $Module.Script "grovel" *>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Install-DevEnvModule {
    <#
    .SYNOPSIS
        Installs a specific module
    #>
    param(
        [hashtable]$Module,
        [bool]$Force = $false,
        [hashtable]$DevEnvContext
    )

    $moduleName = $Module.Name
    Write-Host "Installing module: " -NoNewline
    Write-Host $moduleName -ForegroundColor Cyan

    try {
        # Check if already installed (unless forcing)
        if (-not $Force) {
            if (Test-ModuleInstallation $Module $DevEnvContext) {
                Write-Host "  Already installed and verified" -ForegroundColor Green
                return $true
            }
        }

        # Execute module installation
        $forceFlag = if ($Force) { "-Force" } else { "" }

        Write-Host "  Executing: $($Module.Script) install $forceFlag" -ForegroundColor Gray

        if ($Force) {
            & $Module.Script "install" -Force
        } else {
            & $Module.Script "install"
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Completed successfully" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  Failed with exit code: $LASTEXITCODE" -ForegroundColor Red
            return $false
        }

    } catch {
        Write-Host "  Error: $_" -ForegroundColor Red
        return $false
    }
}

function Invoke-ModuleInstallation {
    <#
    .SYNOPSIS
        Main module installation orchestration
    #>
    param(
        [string[]]$RequestedModules = @(),
        [bool]$Force = $false,
        [hashtable]$DevEnvContext
    )

    # Ensure RequestedModules is always an array
    if (-not $RequestedModules) {
        $RequestedModules = @()
    }

    Write-Host ""
    Write-Host "DevEnv Module Installation" -ForegroundColor Cyan
    Write-Host "==========================" -ForegroundColor Cyan
    Write-Host ""

    # Initialize module system
    if (-not (Initialize-ModuleSystem $DevEnvContext)) {
        throw "Failed to initialize module system"
    }

    # Get modules to install - ensure we get an array back
    $modulesToInstall = @(Get-ModuleExecutionOrder -RequestedModules $RequestedModules -DevEnvContext $DevEnvContext)

    if (@($modulesToInstall).Count -eq 0) {
        if (@($RequestedModules).Count -gt 0) {
            Write-Host "No valid modules found in request: $($RequestedModules -join ', ')" -ForegroundColor Yellow
        } else {
            Write-Host "No modules available for installation" -ForegroundColor Yellow
        }
        return
    }

    Write-Host "Installation Plan:" -ForegroundColor Yellow
    foreach ($module in $modulesToInstall) {
        $status = if (Test-ModuleInstallation $module $DevEnvContext) { "Update" } else { "Install" }
        $forceIndicator = if ($Force) { " (forced)" } else { "" }
        Write-Host "  $($module.Name) - $status$forceIndicator" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Data Directory: " -NoNewline
    Write-Host $DevEnvContext.DataDir -ForegroundColor Yellow
    Write-Host ""

    # Confirm installation
    if (-not $Force -and @($modulesToInstall).Count -gt 1) {
        $response = Read-Host "Proceed with installation? (y/N)"
        if ($response -notmatch "^[Yy]") {
            Write-Host "Installation cancelled" -ForegroundColor Yellow
            return
        }
        Write-Host ""
    }

    # Execute installations
    $successCount = 0
    $failureCount = 0
    $startTime = Get-Date

    foreach ($module in $modulesToInstall) {
        $moduleStartTime = Get-Date

        if (Install-DevEnvModule -Module $module -Force $Force -DevEnvContext $DevEnvContext) {
            $successCount++
        } else {
            $failureCount++
        }

        $moduleEndTime = Get-Date
        $moduleElapsed = $moduleEndTime - $moduleStartTime
        Write-Host "  Time: $($moduleElapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Gray
        Write-Host ""
    }

    # Installation summary
    $endTime = Get-Date
    $totalElapsed = $endTime - $startTime

    Write-Host "Installation Summary" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    Write-Host "Successful: " -NoNewline
    Write-Host $successCount -ForegroundColor Green
    Write-Host "Failed: " -NoNewline
    Write-Host $failureCount -ForegroundColor Red
    Write-Host "Total Time: " -NoNewline
    Write-Host "$($totalElapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Yellow
    Write-Host ""

    if ($failureCount -gt 0) {
        Write-Host "Some modules failed to install. Check the output above for details." -ForegroundColor Yellow
        Write-Host "You can retry failed modules individually or use -Force to retry all." -ForegroundColor Gray
        exit 1
    } else {
        Write-Host "All modules installed successfully!" -ForegroundColor Green

        # Show next steps
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "- Run 'devenv.ps1 status' to verify your environment" -ForegroundColor White
        Write-Host "- Run 'devenv.ps1 verify' to test all components" -ForegroundColor White
        Write-Host "- Check individual module info with 'devenv.ps1 info <module>'" -ForegroundColor White
        Write-Host ""
    }
}
#endregion
