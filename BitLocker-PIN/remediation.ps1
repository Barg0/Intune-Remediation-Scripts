# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "BitLocker-PIN"
$logFileName = "remediation.log"

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
    if (-not (Get-Module -ListAvailable -Name BitLocker)) {
        Write-Log "BitLocker module not available" -Tag "Error"
        Complete-Script -exitCode 1
    }
    Import-Module BitLocker -ErrorAction Stop
    Write-Log "Imported BitLocker module" -Tag "Run"

    $osVolume = Get-BitLockerVolume | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
    Write-Log "Retrieved OS volume: $($osVolume.MountPoint)" -Tag "Get"
    Write-Log "OS volume: MountPoint=$($osVolume.MountPoint) | VolumeStatus=$($osVolume.VolumeStatus) | ProtectionStatus=$($osVolume.ProtectionStatus) | EncryptionPercentage=$($osVolume.EncryptionPercentage) | KeyProtectorCount=$($osVolume.KeyProtector.Count)" -Tag "Debug"
    if ($osVolume.KeyProtector) {
        $protectorTypes = ($osVolume.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ','
        Write-Log "Key protectors: $protectorTypes" -Tag "Debug"
    }

    if (-not $osVolume) {
        Write-Log "OS volume not found" -Tag "Error"
        Complete-Script -exitCode 1
    }

    # TpmPin present = check further based on VolumeStatus
    $hasTpmPin = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }

    if ($hasTpmPin) {
        # FullyDecrypted + TpmPin = restart pending (normal after Enable-BitLocker, before reboot). Do not touch.
        if ($osVolume.VolumeStatus -eq 'FullyDecrypted') {
            Write-Log "Restart pending (FullyDecrypted + TpmPin present, encryption starts after reboot) - no action" -Tag "Success"
            Write-Log "Exit reason: TpmPin present, VolumeStatus=FullyDecrypted (avoids duplicate AAD key before reboot)" -Tag "Debug"
            Complete-Script -exitCode 0
        }

        # Encrypted + TpmPin + ProtectionStatus Off = suspended/disabled (insecure). Requires manual fix.
        if (($osVolume.VolumeStatus -ne 'FullyDecrypted') -and ($osVolume.ProtectionStatus -eq 'Off')) {
            Write-Log "ProtectionStatus OFF on encrypted volume with TpmPin - protectors suspended (insecure state)" -Tag "Error"
            Write-Log "This requires manual intervention: Resume-BitLocker -MountPoint C: or Disable-BitLocker → wait → re-run remediation" -Tag "Info"
            Write-Log "Exit reason: ProtectionStatus=Off on encrypted volume (cannot auto-fix)" -Tag "Debug"
            Complete-Script -exitCode 1
        }

        # Encrypted + TpmPin + ProtectionStatus On = fully compliant, no action
        Write-Log "Already compliant (TpmPin present, VolumeStatus=$($osVolume.VolumeStatus), ProtectionStatus=$($osVolume.ProtectionStatus)) - no action" -Tag "Success"
        Write-Log "Exit reason: TpmPin present (fully compliant)" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    $pinValue = Get-Date -Format 'yyyyMM'

    $securePin = ConvertTo-SecureString $pinValue -AsPlainText -Force
    # Write-Log "Using date-based PIN: $pinValue (YYYYMM)" -Tag "Debug"
    Write-Log "PIN: length=$($pinValue.Length) | SecureString created" -Tag "Debug"

    # In-progress, paused, and wipe states - do not interfere
    if ($osVolume.VolumeStatus -eq 'DecryptionInProgress') {
        Write-Log "Decryption in progress - cannot remediate (wait for completion)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=DecryptionInProgress" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    if ($osVolume.VolumeStatus -eq 'EncryptionPaused') {
        Write-Log "Encryption paused - cannot remediate (run Resume-BitLocker first)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=EncryptionPaused" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    if ($osVolume.VolumeStatus -eq 'DecryptionPaused') {
        Write-Log "Decryption paused - cannot remediate (resume or complete decryption first)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=DecryptionPaused" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    if ($osVolume.VolumeStatus -eq 'FullyEncryptedWipeInProgress') {
        Write-Log "Wipe in progress on encrypted volume - cannot remediate (wait for completion)" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=FullyEncryptedWipeInProgress" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    if ($osVolume.VolumeStatus -eq 'EncryptionInProgress') {
        # Check if TpmPin already exists - if so, we're good; if not, we can't add mid-encryption
        $hasTpmPinInProgress = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }
        if ($hasTpmPinInProgress) {
            Write-Log "Encryption in progress with TpmPin present - compliant, wait for completion" -Tag "Success"
            Complete-Script -exitCode 0
        }
        else {
            Write-Log "Encryption in progress without TpmPin - cannot add protector mid-encryption" -Tag "Info"
            Write-Log "Exit reason: VolumeStatus=EncryptionInProgress, no TpmPin" -Tag "Debug"
            Complete-Script -exitCode 1
        }
    }

    # ProtectionStatus Unknown typically means locked volume
    if ($osVolume.ProtectionStatus -eq 'Unknown') {
        Write-Log "ProtectionStatus Unknown (volume may be locked) - cannot remediate" -Tag "Error"
        Write-Log "Exit reason: ProtectionStatus=Unknown" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    if ($osVolume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Log "OS volume FullyDecrypted - enabling BitLocker with TPM+PIN" -Tag "Run"

        # Safety: do not clear if TpmPin is present (e.g. race / re-run before reboot).
        $existingTpmPin = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }
        if ($existingTpmPin) {
            Write-Log "TPM+PIN already present in FullyDecrypted branch - do not clear (restart pending)" -Tag "Success"
            Complete-Script -exitCode 0
        }

        if ($osVolume.KeyProtector.Count -gt 0) {
            Write-Log "Removing $($osVolume.KeyProtector.Count) existing key protector(s) to start clean (e.g. from previous failed run)" -Tag "Run"
            foreach ($protector in $osVolume.KeyProtector) {
                Write-Log "Removing protector: Type=$($protector.KeyProtectorType) | Id=$($protector.KeyProtectorId)" -Tag "Debug"
                try {
                    Remove-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $protector.KeyProtectorId -ErrorAction Stop
                    Write-Log "Removed $($protector.KeyProtectorType) protector" -Tag "Success"
                }
                catch {
                    Write-Log "Failed to remove protector $($protector.KeyProtectorType): $_" -Tag "Error"
                    throw
                }
            }
            $osVolume = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
            Write-Log "After removal: KeyProtectorCount=$($osVolume.KeyProtector.Count)" -Tag "Debug"
        }

        Write-Log "Calling Add-BitLockerKeyProtector -MountPoint $($osVolume.MountPoint) -RecoveryPasswordProtector" -Tag "Debug"
        Add-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
        Write-Log "Added RecoveryPassword protector" -Tag "Success"
        $afterRecovery = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
        Write-Log "After RecoveryPassword: KeyProtectorCount=$($afterRecovery.KeyProtector.Count) | Types: $(($afterRecovery.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ',')" -Tag "Debug"

        try {
            Write-Log "Calling Enable-BitLocker -MountPoint $($osVolume.MountPoint) -Pin (length $($pinValue.Length)) -TPMandPinProtector (policy supplies encryption method and options)" -Tag "Debug"
            Enable-BitLocker -MountPoint $osVolume.MountPoint -Pin $securePin -TPMandPinProtector -ErrorAction Stop
            Write-Log "Enabled BitLocker with TPM+PIN" -Tag "Success"
        }
        catch {
            $errMsg = $_.Exception.Message
            if ($_.Exception.InnerException) { $errMsg += " | Inner: $($_.Exception.InnerException.Message)" }
            Write-Log "Enable-BitLocker failed: $errMsg" -Tag "Error"
            Write-Log "Exception: $($_.Exception.GetType().FullName) | HRESULT: $($_.Exception.HResult) | StackTrace: $($_.ScriptStackTrace)" -Tag "Debug"
            if ($_.Exception.InnerException) {
                Write-Log "InnerException: $($_.Exception.InnerException.GetType().FullName) | $($_.Exception.InnerException.Message)" -Tag "Debug"
            }
            throw
        }

        try {
            $recoveryId = (Get-BitLockerVolume -MountPoint $osVolume.MountPoint).KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -ExpandProperty KeyProtectorId -First 1
            if ($recoveryId) {
                Write-Log "BackupToAAD - RecoveryKeyProtectorId: $recoveryId" -Tag "Debug"
                BackupToAAD-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $recoveryId -ErrorAction Stop
                Write-Log "Recovery key backed up to AAD" -Tag "Success"
            }
        }
        catch {
            Write-Log "AAD backup failed (device may not be AAD joined): $_" -Tag "Info"
        }

        Write-Log "Remediation complete - BitLocker enabled with PIN. Restart required." -Tag "Success"
        Complete-Script -exitCode 0
    }

    $hasTpmPin   = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }
    $hasTpmOnly  = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'Tpm' }
    $hasRecovery = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    Write-Log "Scenario TPM-only: hasTpmPin=$($null -ne $hasTpmPin) | hasTpmOnly=$($null -ne $hasTpmOnly) | hasRecovery=$($null -ne $hasRecovery)" -Tag "Debug"

    if ($hasTpmPin) {
        Write-Log "Already compliant - TPM+PIN protector present" -Tag "Success"
        Complete-Script -exitCode 0
    }

    if (-not $hasTpmOnly) {
        # No TPM or TpmPin - could be RecoveryPassword only, ExternalKey, Password, etc.
        # We can still add TpmPin if the volume is encrypted
        Write-Log "No TPM or TpmPin protector found - attempting to add TpmPin to encrypted volume" -Tag "Info"
        Write-Log "Current protectors: $(($osVolume.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ',')" -Tag "Debug"
        
        try {
            Add-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -TpmAndPinProtector -Pin $securePin -ErrorAction Stop
            Write-Log "Added TPM+PIN protector" -Tag "Success"
            
            # Ensure RecoveryPassword exists
            $osVolume = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
            $hasRecovery = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
            if (-not $hasRecovery) {
                Add-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
                Write-Log "Added RecoveryPassword protector" -Tag "Success"
            }
            
            # Backup to AAD
            try {
                $recoveryId = (Get-BitLockerVolume -MountPoint $osVolume.MountPoint).KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -ExpandProperty KeyProtectorId -First 1
                if ($recoveryId) {
                    BackupToAAD-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $recoveryId -ErrorAction Stop
                    Write-Log "Recovery key backed up to AAD" -Tag "Success"
                }
            }
            catch {
                Write-Log "AAD backup failed: $_" -Tag "Info"
            }
            
            Write-Log "Remediation complete - TPM+PIN added to encrypted volume" -Tag "Success"
            Complete-Script -exitCode 0
        }
        catch {
            Write-Log "Failed to add TpmPin to encrypted volume: $_" -Tag "Error"
            Write-Log "This may require TPM initialization or manual intervention" -Tag "Info"
            Complete-Script -exitCode 1
        }
    }

    Write-Log "Encrypted with TPM-only - adding TPM+PIN protector" -Tag "Run"
    Write-Log "Calling Add-BitLockerKeyProtector -MountPoint $($osVolume.MountPoint) -TpmAndPinProtector -Pin (length $($pinValue.Length))" -Tag "Debug"

    Add-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -TpmAndPinProtector -Pin $securePin -ErrorAction Stop
    Write-Log "Added TPM+PIN protector" -Tag "Success"

    $blv = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
    $tpmProtector = $blv.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'Tpm' }
    Write-Log "Current protectors after TPM+PIN add: $(($blv.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ',')" -Tag "Debug"
    if ($tpmProtector) {
        Write-Log "Removing TPM-only protector KeyProtectorId: $($tpmProtector.KeyProtectorId)" -Tag "Debug"
        Remove-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $tpmProtector.KeyProtectorId -ErrorAction Stop
        Write-Log "Removed TPM-only protector - PIN now required at boot" -Tag "Success"
    }

    $osVolume   = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
    $hasRecovery = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    if (-not $hasRecovery) {
        Add-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
        Write-Log "Added RecoveryPassword protector" -Tag "Success"
    }

    try {
        $recoveryId = (Get-BitLockerVolume -MountPoint $osVolume.MountPoint).KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -ExpandProperty KeyProtectorId
        Write-Log "BackupToAAD (scenario 2) - RecoveryKeyProtectorId: $recoveryId" -Tag "Debug"
        BackupToAAD-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $recoveryId -ErrorAction Stop
        Write-Log "Recovery key backed up to AAD" -Tag "Success"
    }
    catch {
        Write-Log "AAD backup failed: $_" -Tag "Info"
        Write-Log "AAD backup exception: $($_.Exception.Message) | Inner: $($_.Exception.InnerException.Message)" -Tag "Debug"
    }

    Write-Log "Remediation complete - TPM+PIN enforced. Restart required for PIN prompt." -Tag "Success"
    Complete-Script -exitCode 0
}
catch {
    Write-Log "Remediation failed: $_" -Tag "Error"
    Write-Log "Top-level exception: $($_.Exception.GetType().FullName) | Message: $($_.Exception.Message) | HRESULT: $($_.Exception.HResult)" -Tag "Debug"
    if ($_.Exception.InnerException) { Write-Log "Top-level InnerException: $($_.Exception.InnerException.Message)" -Tag "Debug" }
    Write-Log "ScriptStackTrace: $($_.ScriptStackTrace)" -Tag "Debug"
    Complete-Script -exitCode 1
}
