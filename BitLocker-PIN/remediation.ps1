# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "BitLocker-PIN"
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $true   # Set to $true to capture verbose Debug logs when isolating issues
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
    Write-Log "OS volume: MountPoint=$($osVolume.MountPoint) | VolumeStatus=$($osVolume.VolumeStatus) | EncryptionPercentage=$($osVolume.EncryptionPercentage) | KeyProtectorCount=$($osVolume.KeyProtector.Count)" -Tag "Debug"
    if ($osVolume.KeyProtector) {
        $protectorTypes = ($osVolume.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ','
        Write-Log "Key protectors: $protectorTypes" -Tag "Debug"
    }

    if (-not $osVolume) {
        Write-Log "OS volume not found" -Tag "Error"
        Complete-Script -exitCode 1
    }

    $pinValue = Get-Date -Format 'yyyyMM'

    $securePin = ConvertTo-SecureString $pinValue -AsPlainText -Force
    Write-Log "Using date-based PIN: $pinValue (YYYYMM)" -Tag "Info"
    Write-Log "PIN: length=$($pinValue.Length) | SecureString created" -Tag "Debug"

    if ($osVolume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Log "OS volume FullyDecrypted - enabling BitLocker with TPM+PIN" -Tag "Run"

        Write-Log "Calling Add-BitLockerKeyProtector -MountPoint $($osVolume.MountPoint) -RecoveryPasswordProtector" -Tag "Debug"
        Add-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -RecoveryPasswordProtector -ErrorAction Stop
        Write-Log "Added RecoveryPassword protector" -Tag "Success"
        $afterRecovery = Get-BitLockerVolume -MountPoint $osVolume.MountPoint
        Write-Log "After RecoveryPassword: KeyProtectorCount=$($afterRecovery.KeyProtector.Count) | Types: $(($afterRecovery.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ',')" -Tag "Debug"

        try {
            Write-Log "Calling Enable-BitLocker -MountPoint $($osVolume.MountPoint) -TPMandPinProtector -UsedSpaceOnly -EncryptionMethod XtsAes256 -SkipHardwareTest | PIN length=$($pinValue.Length)" -Tag "Debug"
            Enable-BitLocker -MountPoint $osVolume.MountPoint -Pin $securePin -TPMandPinProtector -UsedSpaceOnly -EncryptionMethod XtsAes256 -SkipHardwareTest -ErrorAction Stop
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
            $recoveryId = (Get-BitLockerVolume -MountPoint $osVolume.MountPoint).KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -ExpandProperty KeyProtectorId
            Write-Log "BackupToAAD - RecoveryKeyProtectorId: $recoveryId" -Tag "Debug"
            BackupToAAD-BitLockerKeyProtector -MountPoint $osVolume.MountPoint -KeyProtectorId $recoveryId -ErrorAction Stop
            Write-Log "Recovery key backed up to AAD" -Tag "Success"
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
        Write-Log "Unexpected state - no TPM protector found" -Tag "Error"
        Complete-Script -exitCode 1
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
