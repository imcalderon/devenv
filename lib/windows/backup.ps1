# lib/windows/backup.ps1 - PowerShell backup utilities

# Get backup directory for module
function Get-BackupDirectory {
    param (
        [string]$Module = ""
    )
    
    # Get backup directory from module config if available
    $backupBase = "$env:USERPROFILE\.devenv\backups"
    
    if ($Module -and (Test-Path "$env:ROOT_DIR\modules\$Module\config.json")) {
        $configBackupDir = Get-ModuleConfig $Module ".backup.dir" $backupBase $Module
        if ($configBackupDir) {
            $backupBase = $configBackupDir
        }
    }
    
    # Create timestamped backup directory
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDir = "$backupBase\$timestamp"
    
    if ($Module) {
        $backupDir = "$backupDir\$Module"
    }
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    return $backupDir
}

# Backup a file with module context
function Backup-File {
    param (
        [string]$Path,
        [string]$Module = ""
    )
    
    if (-not (Test-Path $Path)) {
        Write-LogWarning "Path not found for backup: $Path" $Module
        return $false
    }
    
    $backupDir = Get-BackupDirectory $Module
    
    if (Test-Path $Path -PathType Leaf) {
        # It's a file
        $fileName = Split-Path $Path -Leaf
        $destPath = "$backupDir\$fileName.backup"
        
        try {
            Copy-Item -Path $Path -Destination $destPath -Force
            Write-LogInfo "Backed up $Path to $destPath" $Module
        }
        catch {
            Write-LogError "Failed to backup file ${Path}: $_" $Module
            return $false
        }
    }
    elseif (Test-Path $Path -PathType Container) {
        # It's a directory
        $dirName = Split-Path $Path -Leaf
        $destPath = "$backupDir\$dirName.backup"
        
        try {
            # Create the destination directory
            New-Item -Path $destPath -ItemType Directory -Force | Out-Null
            
            # Copy all items recursively
            Copy-Item -Path "$Path\*" -Destination $destPath -Recurse -Force
            Write-LogInfo "Backed up directory $Path to $destPath" $Module
        }
        catch {
            Write-LogError "Failed to backup directory ${Path}: $_" $Module
            return $false
        }
    }
    else {
        Write-LogWarning "Unknown path type for backup: $Path" $Module
        return $false
    }
    
    return $true
}

# Restore a file with module context
function Restore-File {
    param (
        [string]$File,
        [string]$Module = ""
    )
    
    # Get backup directory from module config
    $backupBase = "$env:USERPROFILE\.devenv\backups"
    
    if ($Module -and (Test-Path "$env:ROOT_DIR\modules\$Module\config.json")) {
        $configBackupDir = Get-ModuleConfig $Module ".backup.dir" $backupBase $Module
        if ($configBackupDir) {
            $backupBase = $configBackupDir
        }
    }
    
    # Find latest backup
    $latestBackup = Get-ChildItem -Path $backupBase -Directory | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    
    if (-not $latestBackup) {
        Write-LogError "No backup directory found" $Module
        return $false
    }
    
    $backupFile = ""
    if ($Module) {
        $backupFile = "$($latestBackup.FullName)\$Module\$(Split-Path $File -Leaf).backup"
    }
    else {
        $backupFile = "$($latestBackup.FullName)\$(Split-Path $File -Leaf).backup"
    }
    
    if (Test-Path $backupFile) {
        try {
            Copy-Item -Path $backupFile -Destination $File -Force
            Write-LogInfo "Restored $File from backup" $Module
            return $true
        }
        catch {
            Write-LogError "Failed to restore file ${File}: $_" $Module
            return $false
        }
    }
    else {
        Write-LogError "No backup found for file: $File" $Module
        return $false
    }
}

# Cleanup old backups based on module retention policy
function Remove-OldBackups {
    param (
        [string]$Module = ""
    )
    
    # Get backup configuration
    $backupBase = "$env:USERPROFILE\.devenv\backups"
    $retentionDays = 30
    
    if ($Module -and (Test-Path "$env:ROOT_DIR\modules\$Module\config.json")) {
        $configBackupDir = Get-ModuleConfig $Module ".backup.dir" $backupBase $Module
        if ($configBackupDir) {
            $backupBase = $configBackupDir
        }
        
        $configRetention = Get-ModuleConfig $Module ".backup.retention_days" 30 $Module
        if ($configRetention) {
            $retentionDays = $configRetention
        }
    }
    
    # Find and remove old backups
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)
    
    Get-ChildItem -Path $backupBase -Directory | Where-Object {
        $_.LastWriteTime -lt $cutoffDate
    } | ForEach-Object {
        try {
            Remove-Item -Path $_.FullName -Recurse -Force
            Write-LogInfo "Removed old backup: $($_.FullName)" $Module
        }
        catch {
            Write-LogError "Failed to remove old backup $($_.FullName): $_" $Module
        }
    }
    
    Write-LogInfo "Cleaned up backups older than $retentionDays days" $Module
    return $true
}

# Create a full backup for a module
function New-Backup {
    param (
        [string]$Module = ""
    )
    
    # Get backup paths from module config if available
    $backupPaths = @()
    
    if ($Module -and (Test-Path "$env:ROOT_DIR\modules\$Module\config.json")) {
        $backupPaths = @(Get-ModuleConfig $Module ".backup.paths[]" @() "windows")
    }
    
    foreach ($path in $backupPaths) {
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
        
        if (Test-Path $expandedPath) {
            Backup-File $expandedPath $Module
        }
    }
    
    return $true
}