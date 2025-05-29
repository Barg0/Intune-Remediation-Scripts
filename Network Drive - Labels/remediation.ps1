# Script version:   2025-05-29 14:08
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Label - Network Drive - T"
$logFileName = "remediation.log"

# ---------------------------[ Network Drive Values ]---------------------------

$networkDrivePath = "\\localhost\test"
$desiredLabel = "Test"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return } # Exit if logging is disabled

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "  # Fallback if an unrecognized tag is used
    }

    # Set tag colors
    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Check"   { "Blue" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow"}
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    # Write to file if enabled
    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

    # Write to console with color formatting
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
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Remediation Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Execution ]---------------------------

Write-Log "======== Remediation Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Set Label ]---------------------------

$shareNameEscaped = ($networkDrivePath -replace "\\", "#") -replace ":", ""
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\$shareNameEscaped"

Write-Log "Setting '_LabelFromReg' to '$desiredLabel'" -Tag "Info"

Set-ItemProperty -Path $regPath -Name "_LabelFromReg" -Value $desiredLabel -Type String -Force
Write-Log "Set '_LabelFromReg' to '$desiredLabel' successfully." -Tag "Success"

# ---------------------------[ Validate Label ]---------------------------

$currentLabel = (Get-ItemProperty -Path $regPath -Name "_LabelFromReg" -ErrorAction SilentlyContinue)._LabelFromReg

if ($currentLabel -eq $desiredLabel) {
    Write-Log "Validation successful. Label is correctly set to '$desiredLabel'." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Validation failed. Label is not correctly set. Current: '$currentLabel' | Expected: '$desiredLabel'" -Tag "Error"
    Complete-Script -ExitCode 1
}
