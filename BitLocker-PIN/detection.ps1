# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "BitLocker-PIN"
$logFileName = "detection.log"

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
    $osVolume = Get-BitLockerVolume | Where-Object { $_.VolumeType -eq 'OperatingSystem' }
    Write-Log "Retrieved OS volume: $($osVolume.MountPoint)" -Tag "Get"
    if ($osVolume) {
        Write-Log "OS volume: MountPoint=$($osVolume.MountPoint) | VolumeStatus=$($osVolume.VolumeStatus) | EncryptionPercentage=$($osVolume.EncryptionPercentage) | KeyProtectorCount=$($osVolume.KeyProtector.Count)" -Tag "Debug"
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

    if ($osVolume.VolumeStatus -eq 'FullyDecrypted') {
        Write-Log "BitLocker not active (FullyDecrypted) - remediation needed" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=FullyDecrypted" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    if ($osVolume.VolumeStatus -eq 'EncryptionInProgress') {
        Write-Log "Encryption in progress - skip remediation" -Tag "Info"
        Write-Log "Exit reason: VolumeStatus=EncryptionInProgress" -Tag "Debug"
        Complete-Script -exitCode 0
    }

    $hasTpmPin = $osVolume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'TpmPin' }
    Write-Log "hasTpmPin=$($null -ne $hasTpmPin)" -Tag "Debug"

    if (-not $hasTpmPin) {
        Write-Log "Encrypted but no TPM+PIN protector - remediation needed" -Tag "Info"
        Write-Log "Exit reason: no TpmPin protector" -Tag "Debug"
        Complete-Script -exitCode 1
    }

    Write-Log "BitLocker with PIN compliant" -Tag "Success"
    Write-Log "Exit reason: compliant (TpmPin present)" -Tag "Debug"
    Complete-Script -exitCode 0
}
catch {
    Write-Log "Detection error: $_" -Tag "Error"
    Write-Log "Detection exception: $($_.Exception.GetType().FullName) | Message: $($_.Exception.Message) | StackTrace: $($_.ScriptStackTrace)" -Tag "Debug"
    Complete-Script -exitCode 1
}
