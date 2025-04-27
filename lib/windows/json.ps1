# lib/windows/json.ps1 - PowerShell JSON utilities

# Ensure we have admin privileges
function Assert-AdminPrivileges {
    param ([string]$ModuleName = "")
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-LogInfo "Requesting admin privileges..." $ModuleName
        
        # Check if we're in an elevated PowerShell session
        $elevatedProcess = Start-Process -FilePath PowerShell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command Get-Date" -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
        
        if (-not $elevatedProcess -or $elevatedProcess.ExitCode -ne 0) {
            Write-LogError "Failed to get admin privileges" $ModuleName
            return $false
        }
    }
    
    return $true
}

# Get value from JSON file with module context
function Get-JsonValue {
    param (
        [string]$File,
        [string]$Query,
        $Default = $null,
        [string]$ModuleName = ""
    )
    
    if (-not (Test-Path $File)) {
        Write-LogError "JSON file not found: $File" $ModuleName
        return $Default
    }
    
    try {
        # Load the JSON file
        $json = Get-Content $File -Raw | ConvertFrom-Json
        
        # Parse the query
        $parts = $Query -replace '^\.' -split '\.'
        $current = $json
        
        foreach ($part in $parts) {
            # Check for array index notation
            if ($part -match '\[\d+\]$') {
                $name = $part -replace '\[\d+\]$'
                $index = [int]($part -replace '^[^\[]+\[(\d+)\]$', '$1')
                
                if (-not $name) {
                    # Pure array index
                    if ($current -isnot [array]) {
                        return $Default
                    }
                    if ($index -ge $current.Length) {
                        return $Default
                    }
                    $current = $current[$index]
                } else {
                    # Property with array index
                    if (-not (Get-Member -InputObject $current -Name $name -MemberType Properties)) {
                        return $Default
                    }
                    $prop = $current.$name
                    if ($prop -isnot [array]) {
                        return $Default
                    }
                    if ($index -ge $prop.Length) {
                        return $Default
                    }
                    $current = $prop[$index]
                }
            }
            elseif ($part -match '\[\]$') {
                # Return all array elements
                $name = $part -replace '\[\]$'
                
                if (-not $name) {
                    # Pure array notation
                    if ($current -isnot [array]) {
                        return $Default
                    }
                    return $current
                } else {
                    # Property that is an array
                    if (-not (Get-Member -InputObject $current -Name $name -MemberType Properties)) {
                        return $Default
                    }
                    $prop = $current.$name
                    if ($prop -isnot [array]) {
                        return $Default
                    }
                    return $prop
                }
            }
            else {
                # Regular property
                if (-not (Get-Member -InputObject $current -Name $part -MemberType Properties -ErrorAction SilentlyContinue)) {
                    return $Default
                }
                $current = $current.$part
            }
        }
        
        return $current
    }
    catch {
        Write-LogError "Failed to parse JSON query: $Query - $_" $ModuleName
        return $Default
    }
}

# Validate JSON file with optional schema
function Test-JsonFile {
    param (
        [string]$File,
        [string]$Schema = "",
        [string]$ModuleName = ""
    )
    
    if (-not (Test-Path $File)) {
        Write-LogError "JSON file not found: $File" $ModuleName
        return $false
    }
    
    try {
        # Basic JSON syntax validation
        Get-Content $File -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        Write-LogError "Invalid JSON syntax in file: $File - $_" $ModuleName
        return $false
    }
    
    # Schema validation if schema file provided
    if ($Schema -and (Test-Path $Schema)) {
        try {
            $jsonContent = Get-Content $File -Raw | ConvertFrom-Json
            $jsonSchema = Get-Content $Schema -Raw | ConvertFrom-Json
            
            # Basic schema validation (simplified)
            # For more complex validation, a dedicated JSON schema validator should be used
            
            # TODO: Implement proper JSON schema validation
            # This would typically use a module like Test-Json with a schema parameter
            
            Write-LogInfo "Schema validation is not fully implemented yet" $ModuleName
        }
        catch {
            Write-LogError "JSON schema validation failed for file: $File - $_" $ModuleName
            return $false
        }
    }
    
    return $true
}

# Get a specific configuration value with module-specific platform awareness
function Get-ConfigValue {
    param (
        [string]$File,
        [string]$Key,
        $Default = $null,
        [string]$Platform = "",
        [string]$ModuleName = ""
    )
    
    # Determine platform if not provided
    if (-not $Platform) {
        $Platform = "windows"  # Default for this utility
    }
    
    # Try platform-specific value first
    $platformValue = Get-JsonValue $File ".platforms.$Platform$Key" $null $ModuleName
    
    if ($null -ne $platformValue) {
        return $platformValue
    }
    
    # Fall back to global value
    $globalValue = Get-JsonValue $File ".global$Key" $Default $ModuleName
    
    return $globalValue
}