# Script version:   2025-05-29 14:08
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Label - Network Drive - T"
$logFileName = "detection.log"

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
    Write-Log "======== Detection Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Execution ]---------------------------

Write-Log "======== Detection Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"


# ---------------------------[ Label Verification ]---------------------------

$MaxRetries = 10
$RetryCount = 0

$shareNameEscaped = ($networkDrivePath -replace "\\", "#") -replace ":", ""
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\$shareNameEscaped"

Write-Log "Checking if registry path exists: $regPath" -Tag "Check"

while (-not (Test-Path $regPath) -and $RetryCount -lt $MaxRetries) {
    Write-Log "$regPath does not exist. Waiting 2 min (Attempt $($RetryCount + 1)/$MaxRetries)" -Tag "Info"
    Start-Sleep -Seconds 120
    $RetryCount++
}

if (-not (Test-Path $regPath)) {
    Write-Log "Registry path $regPath does not exist after $MaxRetries retries." -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "Registry path $regPath exists." -Tag "Success"

$currentLabel = (Get-ItemProperty -Path $regPath -Name "_LabelFromReg" -ErrorAction SilentlyContinue)._LabelFromReg

if ($null -eq $currentLabel) {
    Write-Log "_LabelFromReg value is missing." -Tag "Error"
    Complete-Script -ExitCode 1
} else {
    Write-Log "Found _LabelFromReg value: '$currentLabel'" -Tag "Info"
}

if ($currentLabel -eq $desiredLabel) {
    Write-Log "Label is correctly set to '$desiredLabel'." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Label mismatch. Current: '$currentLabel' | Expected: '$desiredLabel'" -Tag "Error"
    Complete-Script -ExitCode 1
}

