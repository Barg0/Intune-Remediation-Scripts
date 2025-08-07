# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "FortiClient - Disable iPv6"
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
    Write-Log "======== Detection Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Detection Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Detection ]---------------------------

# Retry logic
$retryCount = 0
$maxRetries = 10
$delaySeconds = 120
$adapter = $null

do {
    Write-Log "Checking for Fortinet adapter (Attempt $($retryCount + 1)/$maxRetries)" -Tag "Check"
    $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "Fortinet Virtual Ethernet Adapter*" }

    if ($null -eq $adapter) {
        Write-Log "Fortinet adapter not found, waiting $delaySeconds seconds before retry..." -Tag "Info"
        Start-Sleep -Seconds $delaySeconds
        $retryCount++
    }
} while ($null -eq $adapter -and $retryCount -lt $maxRetries)

# Adapter still not found after max retries
if ($null -eq $adapter) {
    Write-Log "Fortinet adapter not found after $maxRetries attempts. Skipping remediation." -Tag "Info"
    Complete-Script -ExitCode 0  # No remediation needed if adapter isn't even present
}

Write-Log "Fortinet adapter detected: $($adapter.Name)" -Tag "Success"

# Check IPv6 binding
$ipv6Binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6

if ($ipv6Binding.Enabled -eq $false) {
    Write-Log "IPv6 already disabled on adapter $($adapter.Name)" -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "IPv6 still enabled on adapter $($adapter.Name), triggering remediation" -Tag "Error"
    Complete-Script -ExitCode 1
}