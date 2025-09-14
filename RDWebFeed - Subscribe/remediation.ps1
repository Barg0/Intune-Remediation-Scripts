# ---------------------------[ Script Start Timestamp ]---------------------------
# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Config ]---------------------------
# Customize these values:
$FeedUrl       = "https://rds01.test.loca/rdweb/feed/webfeed.aspx"
$WorkspaceName = "Company - Remote Desktop Services"

# ---------------------------[ Script name ]---------------------------
# Script name used for folder/log naming
$scriptName = "RDWebFeed - ts01"
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------
# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$($env:USERNAME)\$scriptName"
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

function Test-FeedPresent {
    param([string]$Url)
    $feedsPath = 'HKCU:\Software\Microsoft\Workspaces\Feeds'
    if (-not (Test-Path $feedsPath)) { return $false }
    $found = Get-ChildItem $feedsPath -ErrorAction SilentlyContinue | ForEach-Object {
        try { (Get-ItemProperty -Path $_.PSPath -ErrorAction Stop).URL } catch { $null }
    } | Where-Object { $_ -eq $Url }
    return ($null -ne $found -and $found.Count -ge 1)
}

try {
    if (Test-FeedPresent -Url $FeedUrl) {
        Write-Log "Feed already present — refreshing it." -Tag "Info"
    } else {
        Write-Log "Feed not present — registering now." -Tag "Check"
    }

    $wcxDir  = Join-Path $env:LocalAppData "RDWebFeed"
    $wcxPath = Join-Path $wcxDir "webfeed.wcx"
    if (-not (Test-Path $wcxDir)) { New-Item -ItemType Directory -Path $wcxDir -Force | Out-Null }

$XML = @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<workspace name="$WorkspaceName" xmlns="http://schemas.microsoft.com/ts/2008/09/tswcx">
  <defaultFeed url="$FeedUrl" />
</workspace>
"@
    $XML | Out-File -FilePath $wcxPath -Encoding utf8 -Force | Out-Null
    Write-Log "WCX written to $wcxPath" -Tag "Info"

    $rdArgs = @('tsworkspace,WorkspaceSilentSetup', (Split-Path -Leaf $wcxPath))
    Write-Log "Invoking: rundll32.exe $($rdArgs -join ' ')" -Tag "Debug"

    Push-Location $wcxDir
    try {
        $proc = Start-Process -FilePath rundll32.exe -ArgumentList $rdArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Write-Log "rundll32 exit code: $($proc.ExitCode)" -Tag "Debug"
    } finally {
        Pop-Location
    }

    Start-Sleep -Seconds 3

    if (Test-FeedPresent -Url $FeedUrl) {
        Write-Log "RD Web feed successfully registered." -Tag "Success"
        Complete-Script -ExitCode 0
    } else {
        Write-Log "Feed not detected after registration." -Tag "Error"
        Complete-Script -ExitCode 1
    }
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}