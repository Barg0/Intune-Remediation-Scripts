# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$scriptName = "Network Drive - Label - __DRIVE_LETTER__"
$logFileName = "remediation.log"

# ---------------------------[ Network Drive Values ]---------------------------
$networkDrivePath = "__DRIVE_PATH__"
$desiredLabel = "__DRIVE_LABEL__"

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$env:USERNAME\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start", "Get", "Run", "Info", "Success", "Error", "Debug", "End")
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
    param([int]$ExitCode)

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Set Label ]---------------------------
$shareNameEscaped = ($networkDrivePath -replace "\\", "#") -replace ":", ""
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\$shareNameEscaped"

Write-Log "Setting '_LabelFromReg' to '$desiredLabel' at $regPath" -Tag "Run"

try {
    Set-ItemProperty -Path $regPath -Name "_LabelFromReg" -Value $desiredLabel -Type String -Force
    Write-Log "Set '_LabelFromReg' to '$desiredLabel' successfully." -Tag "Success"
}
catch {
    Write-Log "Failed to set '_LabelFromReg': $_" -Tag "Error"
    Complete-Script -ExitCode 1
}

# ---------------------------[ Validate Label ]---------------------------
$currentLabel = (Get-ItemProperty -Path $regPath -Name "_LabelFromReg" -ErrorAction SilentlyContinue)._LabelFromReg

if ($currentLabel -eq $desiredLabel) {
    Write-Log "Validation successful. Label is correctly set to '$desiredLabel'." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Validation failed. Current: '$currentLabel' | Expected: '$desiredLabel'" -Tag "Error"
    Complete-Script -ExitCode 1
}
