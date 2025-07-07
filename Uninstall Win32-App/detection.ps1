# ---------------------------[ Script Metadata ]---------------------------

# Script version:   2025-07-07
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Software Values ]---------------------------

$softwareName = "TeamViewer Host"

# ---------------------------[ Registry Paths ]---------------------------

$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ Script Start Timestamp ]---------------------------

$scriptStartTime = Get-Date

# ---------------------------[ Log Controll ]---------------------------

$log = $true
$enableLogFile = $true

# ---------------------------[ Log File/Folder ]---------------------------

$scriptName = "Uninstall - $softwareName"
$logFileName = "detection.log"

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Log Function ]---------------------------

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "
    }

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

    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

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

# ---------------------------[ Detection Logic ]---------------------------

# Flag to indicate if the program is found
$programFound = $false

Write-Log "Checking registry for software: $softwareName" "Check"

# Iterate over each registry path
foreach ($registryPath in $registryPaths) {
    if (-not (Test-Path $registryPath)) {
        Write-Log "Registry path $registryPath does not exist, skipping." "Info"
        continue
    }

    $subkeys = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue

    foreach ($subkey in $subkeys) {
        $displayName = (Get-ItemProperty -Path $subkey.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName

        if ($displayName -eq $softwareName) {
            Write-Log "Found installed software: $displayName" "Success"
            $programFound = $true
            break
        }
    }

    if ($programFound) { break }
}

# ---------------------------[ Script End ]---------------------------

if ($programFound) {
    Write-Log "$softwareName is installed." "Error"
    Complete-Script -ExitCode 1
} else {
    Write-Log "$softwareName is not installed." "Success"
    Complete-Script -ExitCode 0
}