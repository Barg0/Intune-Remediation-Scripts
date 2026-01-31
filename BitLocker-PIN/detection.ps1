# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "BitLocker-PIN"
$logFileName = "detection.log"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false   # Set to $true to capture verbose Debug logs when isolating issues
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
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

try {
    $osVolume = Get-BitLockerVolume | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
    Write-Log "Retrieved OS volume: $($osVolume.MountPoint)" -Tag "Get"
    if ($osVolume) {
        Write-Log "OS volume: MountPoint=$($osVolume.MountPoint) | VolumeStatus=$($osVolume.VolumeStatus) | ProtectionStatus=$($osVolume.ProtectionStatus) | EncryptionPercentage=$($osVolume.EncryptionPercentage) | KeyProtectorCount=$($osVolume.KeyProtector.Count)" -Tag "Debug"
        if ($osVolume.KeyProtector) {
            $protectorTypes = ($osVolume.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ','
            Write-Log "Key protectors: $protectorTypes" -Tag "Debug"
        }
    }
    else {
        Write-Log "Get-BitLockerVolume returned no OS volume" -Tag "Debug"
    }

    if (-not $osVolume) {
        Write-Log "No OS volume found - remediation needed" -Tag "Error"
        Complete-Script -exitCode 1
    }

    # TpmPin present = check further based on VolumeStatus
    $hasTpmPin = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }
    Write-Log "hasTpmPin=$($null -ne $hasTpmPin)" -Tag "Debug"

    if ($hasTpmPin) {
        # FullyDecrypted + TpmPin = restart pending (normal after Enable-BitLocker, before reboot). ProtectionStatus Off is expected here.
        if ($osVolume.VolumeStatus -eq 'FullyDecrypted') {
            Write-Log "Restart pending (FullyDecrypted + TpmPin present, encryption starts after reboot)" -Tag "Success"
            Write-Log "Exit reason: TpmPin present, VolumeStatus=FullyDecrypted (restart pending)" -Tag "Debug"
            Complete-Script -exitCode 0
        }

        # Encrypted + TpmPin + ProtectionStatus Off = suspended/disabled (insecure). Requires manual fix.
        if (($osVolume.VolumeStatus -ne 'FullyDecrypted') -and ($osVolume.ProtectionStatus -eq 'Off')) {
            Write-Log "ProtectionStatus OFF on encrypted volume with TpmPin - protectors suspended (insecure state) - remediation needed" -Tag "Error"
            Write-Log "Exit reason: ProtectionStatus=Off on encrypted volume (requires Resume-BitLocker or manual fix)" -Tag "Debug"
            Complete-Script -exitCode 1
        }

        # Encrypted + TpmPin + ProtectionStatus On = fully compliant
        Write-Log "BitLocker with PIN compliant (TpmPin present, ProtectionStatus=$($osVolume.ProtectionStatus))" -Tag "Success"
        Write-Log "Exit reason: TpmPin present, VolumeStatus=$($osVolume.VolumeStatus), ProtectionStatus=$($osVolume.ProtectionStatus)" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    if ($osVolume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Log "BitLocker not active (FullyDecrypted) - remediation needed" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=FullyDecrypted" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    # In-progress and paused states - do not interfere
    if ($osVolume.VolumeStatus -eq 'EncryptionInProgress') {
        Write-Log "Encryption in progress - skip remediation" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=EncryptionInProgress" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    if ($osVolume.VolumeStatus -eq 'DecryptionInProgress') {
        Write-Log "Decryption in progress - skip remediation (wait for completion)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=DecryptionInProgress" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    if ($osVolume.VolumeStatus -eq 'EncryptionPaused') {
        Write-Log "Encryption paused - skip remediation (resume or complete encryption first)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=EncryptionPaused" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    if ($osVolume.VolumeStatus -eq 'DecryptionPaused') {
        Write-Log "Decryption paused - skip remediation (resume or complete decryption first)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=DecryptionPaused" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    if ($osVolume.VolumeStatus -eq 'FullyEncryptedWipeInProgress') {
        Write-Log "Wipe in progress on encrypted volume - skip remediation" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=FullyEncryptedWipeInProgress" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    # ProtectionStatus Unknown typically means locked volume - cannot assess
    if ($osVolume.ProtectionStatus -eq 'Unknown') {
        Write-Log "ProtectionStatus Unknown (volume may be locked) - skip remediation" -Tag "Info"
        Write-Log "Exit reason: ProtectionStatus=Unknown" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    # Encrypted but no TPM+PIN (e.g. TPM-only or other protector)
    Write-Log "Encrypted but no TPM+PIN protector - remediation needed" -Tag "Info"
    Write-Log "Exit reason: no TpmPin protector" -Tag "Debug"
    Complete-Script -exitCode 1
}
catch {
    Write-Log "Detection error: $_" -Tag "Error"
    Write-Log "Detection exception: $($_.Exception.GetType().FullName) | Message: $($_.Exception.Message) | StackTrace: $($_.ScriptStackTrace)" -Tag "Debug"
    Complete-Script -exitCode 1
}
