# Script version:   2025-08-09 09:15
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Security - Adobe Reader DC"
$logFileName = "detection.log"

# ---------------------------[ Software Check ]---------------------------

$softwareNamePattern = '^(Adobe\s+Acrobat(\s+Reader)?).*'

$registryPathsSW = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# ---------------------------[ Registry Values ]---------------------------

$registryKeys = @(
    @{
        Hive        = 'HKEY_LOCAL_MACHINE'
        KeyPath     = 'SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown'
        ValueName   = 'bEnableFlash'
        ValueData   = 0
    },
    @{
        Hive        = 'HKEY_LOCAL_MACHINE'
        KeyPath     = 'SOFTWARE\Policies\Adobe\Acrobat Reader\DC\FeatureLockDown'
        ValueName   = 'bDisableJavaScript'
        ValueData   = 1
    }
)

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

# ---------------------------[ Helpers ]---------------------------

function Test-RegistryKeyValue {
    param ([string]$Hive, [string]$KeyPath, [string]$ValueName, [Parameter(Mandatory)]$ExpectedValue)
    $fullPath = Join-Path $Hive $KeyPath
    $registryPath = "Registry::$fullPath"
    try {
        $actualValue = Get-ItemProperty -Path $registryPath -Name $ValueName -ErrorAction Stop |
                       Select-Object -ExpandProperty $ValueName
        if ("$actualValue" -eq "$ExpectedValue") {
            Write-Log "Verified: $Hive\$KeyPath\$ValueName = $ExpectedValue" -Tag "Success"
            return $true
        } else {
            Write-Log "Mismatch: $Hive\$KeyPath\$ValueName is '$actualValue', expected '$ExpectedValue'" -Tag "Error"
            return $false
        }
    } catch {
        Write-Log "Could not read $Hive\$KeyPath\$ValueName - $_" -Tag "Error"
        return $false
    }
}

# ---------------------------[ Check if Adobe Reader is Installed ]---------------------------

$programFound = $false
Write-Log "Checking registry for installed software" -Tag "Check"

foreach ($regPath in $registryPathsSW) {
    if (-not (Test-Path $regPath)) { continue }
    $subkeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
    foreach ($subkey in $subkeys) {
        $displayName = (Get-ItemProperty -Path $subkey.PSPath -Name "DisplayName" -ErrorAction SilentlyContinue).DisplayName
        if ($null -ne $displayName -and $displayName -match $softwareNamePattern) {
            Write-Log "Found installed software: $displayName" -Tag "Success"
            $programFound = $true
            break
        }
    }
    if ($programFound) { break }
}

if (-not $programFound) {
    Write-Log "Adobe Reader is not installed" -Tag "Info"
    Complete-Script -ExitCode 0
}

# ---------------------------[ Detection ]---------------------------

$hadError = $false
foreach ($key in $registryKeys) {
    if (-not (Test-RegistryKeyValue -Hive $key.Hive -KeyPath $key.KeyPath -ValueName $key.ValueName -ExpectedValue $key.ValueData)) {
        $hadError = $true
    }
}

if ($hadError) {
    Complete-Script -ExitCode 1
} else {
    Complete-Script -ExitCode 0
}