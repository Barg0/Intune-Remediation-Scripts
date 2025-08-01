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
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$env:USERNAME\$scriptName"
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

# ---------------------------[ Check if Printer is Already Installed ]---------------------------

Write-Log "Checking if printer '$PrinterName' is already installed..." -Tag "Check"
if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
    Write-Log "Printer '$PrinterName' already installed. No action needed." -Tag "Success"
    Complete-Script -ExitCode 0
}

# ---------------------------[ Check/Create TCP/IP Port ]---------------------------

Write-Log "Checking if port '$PortName' exists..." -Tag "Check"
$portExists = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
if ($null -ne $portExists) {
    Write-Log "TCP/IP Port '$PortName' already exists. Will use existing port." -Tag "Info"
} else {
    Write-Log "Port '$PortName' does not exist. Creating TCP/IP port..." -Tag "Info"
    try {
        Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterIP
        Write-Log "Successfully created TCP/IP port '$PortName'" -Tag "Success"
    } catch {
        Write-Log "Failed to create port '$PortName': $_" -Tag "Error"
        Complete-Script -ExitCode 1
    }
}

# ---------------------------[ Install Printer ]---------------------------

Write-Log "Installing printer '$PrinterName' with driver '$DriverName' on port '$PortName'" -Tag "Info"
try {
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName
    Write-Log "Printer '$PrinterName' installed successfully." -Tag "Success"
    Complete-Script -ExitCode 0
} catch {
    Write-Log "Failed to install printer '$PrinterName': $_" -Tag "Error"
    Complete-Script -ExitCode 1
}
