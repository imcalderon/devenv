# lib/windows/alias.ps1 - PowerShell alias utilities

# Get the aliases directory path
function Get-AliasesDirectory {
    $aliasesDir = "$env:USERPROFILE\.devenv\aliases"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $aliasesDir)) {
        New-Item -Path $aliasesDir -ItemType Directory -Force | Out-Null
    }
    
    return $aliasesDir
}

# Add aliases for a module
function Add-ModuleAliases {
    param (
        [string]$Module,
        [string]$Category = ""
    )
    
    # Get the aliases directory
    $aliasesDir = Get-AliasesDirectory
    $aliasesFile = "$aliasesDir\aliases.ps1"
    
    # Create aliases file if it doesn't exist
    if (-not (Test-Path $aliasesFile)) {
        Set-Content -Path $aliasesFile -Value "# DevEnv Aliases`n" -Force
    }
    
    # Remove existing aliases for this module/category if they exist
    $content = Get-Content -Path $aliasesFile -Raw
    $markerStart = "# BEGIN ${Module}${Category:+_$Category} aliases"
    $markerEnd = "# END ${Module}${Category:+_$Category} aliases"
    
    $pattern = "(?s)$markerStart.*?$markerEnd\r?\n?"
    $content = $content -replace $pattern, ""
    
    # Get aliases from module config
    $query = ".shell.aliases"
    if ($Category) {
        $query = "$query.$Category"
    }
    
    $aliases = @{}
    
    # Try to get platform-specific aliases first
    $platformAliases = Get-ModuleConfig $Module ".platforms.windows$query" $null "windows"
    
    if ($platformAliases) {
        # Convert from PSObject to hashtable
        foreach ($prop in $platformAliases.PSObject.Properties) {
            $aliases[$prop.Name] = $prop.Value
        }
    }
    
    # If no platform-specific aliases, try global aliases
    if ($aliases.Count -eq 0) {
        $globalAliases = Get-ModuleConfig $Module ".global$query" $null
        
        if ($globalAliases) {
            # Convert from PSObject to hashtable
            foreach ($prop in $globalAliases.PSObject.Properties) {
                $aliases[$prop.Name] = $prop.Value
            }
        }
    }
    
    # If we found aliases, add them to the file
    if ($aliases.Count -gt 0) {
        # Create the aliases block
        $aliasesBlock = "$markerStart`n"
        
        foreach ($alias in $aliases.Keys) {
            $cmd = $aliases[$alias]
            $aliasesBlock += "function $alias { $cmd `$args }`n"
        }
        
        $aliasesBlock += "$markerEnd`n"
        
        # Add the block to the content
        $content = $content + "`n" + $aliasesBlock
        
        # Write back to the file
        Set-Content -Path $aliasesFile -Value $content -Force
        
        Write-LogInfo "Added aliases for $Module${Category:+ ($Category)}" "alias"
    }
    
    # Add profile integration if not already done
    Add-ProfileIntegration
    
    return $true
}

# Remove aliases for a module
function Remove-ModuleAliases {
    param (
        [string]$Module,
        [string]$Category = ""
    )
    
    $aliasesDir = Get-AliasesDirectory
    $aliasesFile = "$aliasesDir\aliases.ps1"
    
    if (Test-Path $aliasesFile) {
        # Remove existing aliases for this module/category
        $content = Get-Content -Path $aliasesFile -Raw
        $markerStart = "# BEGIN ${Module}${Category:+_$Category} aliases"
        $markerEnd = "# END ${Module}${Category:+_$Category} aliases"
        
        $pattern = "(?s)$markerStart.*?$markerEnd\r?\n?"
        $content = $content -replace $pattern, ""
        
        # Write back to the file
        Set-Content -Path $aliasesFile -Value $content -Force
        
        Write-LogInfo "Removed aliases for $Module${Category:+ ($Category)}" "alias"
    }
    
    return $true
}

# List all aliases for a module
function Get-ModuleAliases {
    param (
        [string]$Module,
        [string]$Category = ""
    )
    
    $aliasesDir = Get-AliasesDirectory
    $aliasesFile = "$aliasesDir\aliases.ps1"
    
    if (Test-Path $aliasesFile) {
        $content = Get-Content -Path $aliasesFile -Raw
        $markerStart = "# BEGIN ${Module}${Category:+_$Category} aliases"
        $markerEnd = "# END ${Module}${Category:+_$Category} aliases"
        
        if ($content -match "(?s)($markerStart.*?$markerEnd)") {
            return $matches[1]
        }
    }
    
    return $null
}

# Add profile integration to load aliases
function Add-ProfileIntegration {
    $profilePath = $PROFILE.CurrentUserAllHosts
    $aliasesDir = Get-AliasesDirectory
    $aliasesFile = "$aliasesDir\aliases.ps1"
    
    # Create profile directory if it doesn't exist
    if (-not (Test-Path (Split-Path $profilePath -Parent))) {
        New-Item -Path (Split-Path $profilePath -Parent) -ItemType Directory -Force | Out-Null
    }
    
    # Create profile if it doesn't exist
    if (-not (Test-Path $profilePath)) {
        Set-Content -Path $profilePath -Value "# PowerShell Profile`n" -Force
    }
    
    # Add aliases loading if not already present
    $profileContent = Get-Content -Path $profilePath -Raw -ErrorAction SilentlyContinue
    
    if (-not $profileContent -or -not ($profileContent -match "\.devenv\\aliases\\aliases\.ps1")) {
        $loadCode = "`n# DevEnv Aliases`nif (Test-Path `"$aliasesFile`") {`n    . `"$aliasesFile`"`n}`n"
        Add-Content -Path $profilePath -Value $loadCode
        
        Write-LogInfo "Added aliases integration to PowerShell profile" "alias"
    }
    
    return $true
}