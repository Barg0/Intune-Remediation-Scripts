# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "FortiClient - Disable iPv6"
$logFileName = "remediation.log"

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

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Remediation Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Remediation ]---------------------------

# Try to get the adapter
$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "Fortinet Virtual Ethernet Adapter*" }

if ($null -eq $adapter) {
    Write-Log "Fortinet adapter unexpectedly missing in remediation phase. Exiting." -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "Fortinet adapter found: $($adapter.Name)" -Tag "Success"

# Check binding
$binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6

if ($binding.Enabled -eq $false) {
    Write-Log "IPv6 already disabled on adapter $($adapter.Name)" -Tag "Success"
    Complete-Script -ExitCode 0
}

# Disable IPv6
Write-Log "Disabling IPv6 on adapter $($adapter.Name)..." -Tag "Info"
try {
    Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -PassThru | Out-Null
    Start-Sleep -Seconds 3
} catch {
    Write-Log "Failed to disable IPv6: $_" -Tag "Error"
    Complete-Script -ExitCode 1
}

# Re-check
$binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6
if ($binding.Enabled -eq $false) {
    Write-Log "IPv6 successfully disabled on adapter $($adapter.Name)" -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "IPv6 is still enabled after attempting to disable it." -Tag "Error"
    Complete-Script -ExitCode 1
}