# Script version:   2025-04-26 10:00
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Shared Printers ]---------------------------

$sharedPrinters = @(
    "\\server.local\printerName",
    "\\server.local\printerName"
)

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = 1                         # 1 = Enable logging, 0 = Disable logging
$EnableLogFile = $true           # Set to $false to disable file output

# Application name used for folder/log naming
$scriptName = "Printer - PRINTERNAME"

# Define the log output location
$LogFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$LogFile = "$LogFileDirectory\remediation.log"

# Ensure the log directory exists
if (-not (Test-Path $LogFileDirectory)) {
    New-Item -ItemType Directory -Path $LogFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if ($log -ne 1) { return } # Exit if logging is disabled

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "End")
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
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    # Write to file if enabled
    if ($EnableLogFile) {
        "$logMessage" | Out-File -FilePath $LogFile -Append
    }

    # Write to console with color formatting
    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

# ---------------------------[ Script Execution ]---------------------------

Write-Log "======== Remediation Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

foreach ($printerPath in $sharedPrinters) {
    try {
        $exists = Get-Printer | Where-Object { $_.Name -eq $printerPath -or $_.ShareName -eq $printerPath }
        if (-not $exists) {
            Write-Log "Adding printer '$printerPath'..." "Info"
            Add-Printer -ConnectionName $printerPath
        } else {
            Write-Log "Printer '$printerPath' is already installed." "Info"
        }
    } catch {
        Write-Log "Failed to add printer '$printerPath': $_" "Error"
    }
}

# ---------------------------[ Verification Check ]---------------------------

Write-Log "Verifying installed printers..." "Info"

$missingPrinters = @()

foreach ($printerPath in $sharedPrinters) {
    $exists = Get-Printer | Where-Object { $_.Name -eq $printerPath -or $_.ShareName -eq $printerPath }
    if ($exists) {
        Write-Log "Printer '$printerPath' is installed." "Success"
    } else {
        Write-Log "Printer '$printerPath' is missing!" "Error"
        $missingPrinters += $printerPath
    }
}

if ($missingPrinters.Count -eq 0) {
    Write-Log "All printers are installed correctly." "Success"
    $exitCode = 0
} else {
    Write-Log "$($missingPrinters.Count) printer(s) are still missing." "Error"
    $exitCode = 1
}

# ---------------------------[ Script End ]---------------------------

# Measure and log total execution time
$scriptEndTime = Get-Date
$duration = $scriptEndTime - $scriptStartTime
Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
Write-Log "Exit Code: $($exitCode)" -Tag "Info"
Write-Log "======== Remediation Script Completed ========" -Tag "End"
exit $exitCode