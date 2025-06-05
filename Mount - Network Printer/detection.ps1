# Script version:   2025-06-05 15:00
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Parameter ]---------------------------

$PrinterName = "HR"
$PrinterIP = "10.10.10.10"
$PortName = $PrinterIP
$DriverName = "KONICA MINOLTA Universal PCL v3.9.9"

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Printer - $PrinterName"
$logFileName = "detection.log"

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
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}
# Complete-Script -ExitCode 0

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Check for Printer Driver with Retry ]---------------------------
$retryCount = 0
$maxRetries = 10
$delaySeconds = 120  # 2 minutes wait between retries
$driverFound = $false

do {
    Write-Log "Checking for printer driver: $DriverName (Attempt $($retryCount + 1)/$maxRetries)" -Tag "Check"
    $driverFound = Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $DriverName }

    if (-not $driverFound) {
        Write-Log "Driver not found. Waiting $delaySeconds seconds before retrying..." -Tag "Info"
        Start-Sleep -Seconds $delaySeconds
        $retryCount++
    }
} while (-not $driverFound -and $retryCount -lt $maxRetries)

if ($driverFound) {
    Write-Log "Printer driver '$DriverName' was found." -Tag "Success"
} else {
    Write-Log "Printer driver '$DriverName' NOT found after $maxRetries attempts." -Tag "Error"
    Complete-Script -ExitCode 1
}

# ---------------------------[ Check for Printer Port ]---------------------------

$portExists = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if ($null -ne $portExists) {
    Write-Log "Printer port '$PortName' exists." -Tag "Success"
} else {
    Write-Log "Printer port '$PortName' is missing." -Tag "Error"
    Complete-Script -ExitCode 1
}

# ---------------------------[ Check for Printer ]---------------------------

$printerExists = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if ($null -ne $printerExists) {
    Write-Log "Printer '$PrinterName' is installed." -Tag "Success"
} else {
    Write-Log "Printer '$PrinterName' is not installed." -Tag "Error"
    Complete-Script -ExitCode 1
}

# ---------------------------[ End ]---------------------------

Write-Log "All required components (driver, port, printer) are present." -Tag "Success"
Complete-Script -ExitCode 0
