# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "BitLocker-PIN"
$logFileName = "remove.log"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $true
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$Message,
        [string]$Tag = "Info"
    )

    if (-not $log) { return }

    if (($Tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($Tag -eq "Get")   -and (-not $logGet))   { return }
    if (($Tag -eq "Run")   -and (-not $logRun))   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    }
    else {
        $rawTag = "Error  "
    }

    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Get"     { "Blue" }
        "Run"     { "Magenta" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow" }
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    if ($enableLogFile) {
        try {
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        }
        catch {
            # Logging must never block script execution
        }
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

# ---------------------------[ Exit Function ]---------------------------
function Complete-Script {
    param([int]$exitCode)

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $exitCode
}

# ---------------------------[ Script Start ]---------------------------
$ErrorActionPreference = 'Stop'

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName (REMOVE)" -Tag "Info"

try {
    Import-Module BitLocker -ErrorAction Stop
    Write-Log "Imported BitLocker module" -Tag "Run"

    $osVolume = Get-BitLockerVolume | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
    Write-Log "Retrieved OS volume: $($osVolume.MountPoint)" -Tag "Get"

    if (-not $osVolume) {
        Write-Log "OS volume not found" -Tag "Error"
        Complete-Script -exitCode 1
    }

    Write-Log "VolumeStatus: $($osVolume.VolumeStatus) | ProtectionStatus: $($osVolume.ProtectionStatus) | KeyProtectorCount: $($osVolume.KeyProtector.Count)" -Tag "Debug"

    # Step 1: Disable BitLocker (starts decryption if encrypted)
    if ($osVolume.VolumeStatus -ne 'FullyDecrypted') {
        Write-Log "Disabling BitLocker and starting decryption..." -Tag "Run"
        Disable-BitLocker -MountPoint $osVolume.MountPoint -ErrorAction Stop
        Write-Log "BitLocker disabled - decryption started" -Tag "Success"

        # Wait for decryption to complete
        Write-Log "Waiting for decryption to complete..." -Tag "Info"
        do {
            Start-Sleep -Seconds 5
            $osVolume = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
            Write-Log "Decryption progress: $($osVolume.EncryptionPercentage)% | Status: $($osVolume.VolumeStatus)" -Tag "Debug"
        } while ($osVolume.VolumeStatus -eq 'DecryptionInProgress')

        Write-Log "Decryption complete" -Tag "Success"
    }
    else {
        Write-Log "Volume already FullyDecrypted - skipping decryption" -Tag "Info"
    }

    # Step 2: Remove all key protectors
    $osVolume = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
    if ($osVolume.KeyProtector.Count -gt 0) {
        Write-Log "Removing $($osVolume.KeyProtector.Count) key protector(s)..." -Tag "Run"
        foreach ($protector in $osVolume.KeyProtector) {
            Write-Log "Removing protector: Type=$($protector.KeyProtectorType) | Id=$($protector.KeyProtectorId)" -Tag "Debug"
            Remove-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $protector.KeyProtectorId -ErrorAction Stop
            Write-Log "Removed $($protector.KeyProtectorType) protector" -Tag "Success"
        }
    }
    else {
        Write-Log "No key protectors to remove" -Tag "Info"
    }

    # Final state
    $osVolume = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
    Write-Log "Final state: VolumeStatus=$($osVolume.VolumeStatus) | KeyProtectorCount=$($osVolume.KeyProtector.Count)" -Tag "Info"
    Write-Log "BitLocker removed successfully - device is clean for fresh run" -Tag "Success"

    Complete-Script -exitCode 0
}
catch {
    Write-Log "Remove failed: $_" -Tag "Error"
    Write-Log "Exception: $($_.Exception.GetType().FullName) | Message: $($_.Exception.Message)" -Tag "Debug"
    Complete-Script -exitCode 1
}
