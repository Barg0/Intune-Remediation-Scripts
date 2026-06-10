<#
.SYNOPSIS
    Detects whether the RDP redirection warning dialog is reverted to the legacy version.

.DESCRIPTION
    Checks if the registry value RedirectionWarningDialogVersion is present and set to 1 under
    HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services\Client.
    This value reverts the new RDP file security dialog introduced with the
    April 2026 security update to the previous behavior.

    Exit codes:
    0 = Value is present and correct, no remediation required
    1 = Value is missing or incorrect, remediation required

.NOTES
    Runs in SYSTEM context as a Microsoft Intune remediation detection script.
    Warning: Microsoft states a future Windows update might remove support for this setting.

.LINK
    https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/understanding-security-warnings
#>

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Set-RdpWarningDialog"
$logFileName = "detection.log"

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
    Write-Host "[ " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

# ---------------------------[ Exit Function ]---------------------------
function Complete-Script {
    param([int]$ExitCode)

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Runtime $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit $ExitCode" -Tag "Info"
    Write-Log "==================== End ====================" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Registry Configuration ]---------------------------
$registryPath      = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client"
$registryValueName = "RedirectionWarningDialogVersion"
$registryValueData = 1

# ---------------------------[ Registry Function ]---------------------------
function Get-RegistryValueData {
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Log "Registry key '$Path' does not exist" -Tag "Debug"
        return $null
    }

    $itemProperty = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue

    if ($null -eq $itemProperty) {
        Write-Log "Registry value '$Name' does not exist under '$Path'" -Tag "Debug"
        return $null
    }

    return $itemProperty.$Name
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "==================== Start ====================" -Tag "Start"
Write-Log "$env:COMPUTERNAME | $env:USERNAME | $scriptName" -Tag "Info"
Write-Log "PowerShell $($PSVersionTable.PSVersion) | 64-bit process: $([Environment]::Is64BitProcess)" -Tag "Debug"

# ---------------------------[ Detection ]---------------------------
try {
    Write-Log "Reading registry value '$registryValueName' from '$registryPath'" -Tag "Get"
    $currentValueData = Get-RegistryValueData -Path $registryPath -Name $registryValueName

    if ($null -eq $currentValueData) {
        Write-Log "Registry value '$registryValueName' is not present, remediation is required" -Tag "Info"
        Complete-Script -ExitCode 1
    }

    if ($currentValueData -eq $registryValueData) {
        Write-Log "Registry value '$registryValueName' is set to '$currentValueData' as expected, no remediation required" -Tag "Success"
        Complete-Script -ExitCode 0
    }

    Write-Log "Registry value '$registryValueName' is set to '$currentValueData' but expected '$registryValueData', remediation is required" -Tag "Info"
    Complete-Script -ExitCode 1
}
catch {
    Write-Log "Detection failed: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}
