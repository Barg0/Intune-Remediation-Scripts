$ErrorActionPreference = 'Stop'
# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime       = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Set-NetworkPreferIpv4"
$logFileName = "detection.log"

# ---------------------------[ Configuration ]---------------------------
$disabledComponentsPreferIpv4 = 32
$tcpip6ParametersPath         = 'SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\'
$valueName                    = 'DisabledComponents'
$fullRegistryPath             = "Registry::HKEY_LOCAL_MACHINE\$tcpip6ParametersPath"

# ---------------------------[ Logging Setup ]---------------------------
# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $true for verbose DEBUG logging
$logGet        = $true    # enable/disable all [Get] logs
$logRun        = $true    # enable/disable all [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$Message,
        [string]$Tag = "Info"
    )

    if (-not $log) { return }

    # Per-tag switches
    if (($Tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($Tag -eq "Get")   -and (-not $logGet))   { return }
    if (($Tag -eq "Run")   -and (-not $logRun))   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start","Get","Run","Info","Success","Error","Debug","End")
    $rawTag    = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    }
    else {
        $rawTag = "Error  "
    }

    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Get"     { "Blue" }
        "Run"     { "Magenta" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow" }
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    if ($enableLogFile) {
        try {
            Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
        }
        catch {
            # Logging must never block script execution
        }
    }

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
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Detection Completed ========" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Detection Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: ${scriptName}" -Tag "Info"

try {
    $actualValue = Get-ItemProperty -Path $fullRegistryPath -Name $valueName -ErrorAction Stop |
        Select-Object -ExpandProperty $valueName

    Write-Log "Current ${valueName} = $actualValue, expected $disabledComponentsPreferIpv4" -Tag "Get"

    if ("$actualValue" -eq "$disabledComponentsPreferIpv4") {
        Write-Log "Compliant: ${valueName} = $disabledComponentsPreferIpv4 (prefer IPv4 over IPv6)" -Tag "Success"
        Complete-Script -ExitCode 0
    }

    Write-Log "Non-compliant: ${valueName} is $actualValue, expected $disabledComponentsPreferIpv4" -Tag "Error"
    Complete-Script -ExitCode 1
}
catch {
    Write-Log "Non-compliant: Could not read ${valueName} - $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}
