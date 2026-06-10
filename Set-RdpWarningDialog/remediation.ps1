<#
.SYNOPSIS
    Reverts the RDP redirection warning dialog to the legacy version.

.DESCRIPTION
    Checks the current state first and only writes to the registry when required.
    Sets the registry value RedirectionWarningDialogVersion to 1 (REG_DWORD) under
    HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services\Client.
    This value reverts the new RDP file security dialog introduced with the
    April 2026 security update to the previous behavior.

    Exit codes:
    0 = Value is correct (already compliant or successfully remediated)
    1 = Remediation failed

.NOTES
    Runs in SYSTEM context as a Microsoft Intune remediation script.
    Warning: Microsoft states a future Windows update might remove support for this setting.

.LINK
    https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/understanding-security-warnings
#>

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Set-RdpWarningDialog"
$logFileName = "remediation.log"

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

# ---------------------------[ Registry Functions ]---------------------------
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

function Set-RegistryValueData {
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$Name,
        [int]$Data
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Log "Registry key '$Path' does not exist, creating it" -Tag "Run"
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    Write-Log "Writing registry value '$Name' with data '$Data' as REG_DWORD" -Tag "Run"
    New-ItemProperty -Path $Path -Name $Name -Value $Data -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "==================== Start ====================" -Tag "Start"
Write-Log "$env:COMPUTERNAME | $env:USERNAME | $scriptName" -Tag "Info"
Write-Log "PowerShell $($PSVersionTable.PSVersion) | 64-bit process: $([Environment]::Is64BitProcess)" -Tag "Debug"

# ---------------------------[ Remediation ]---------------------------
try {
    Write-Log "Reading registry value '$registryValueName' from '$registryPath'" -Tag "Get"
    $currentValueData = Get-RegistryValueData -Path $registryPath -Name $registryValueName

    if ($currentValueData -eq $registryValueData) {
        Write-Log "Registry value '$registryValueName' is already set to '$currentValueData', no change required" -Tag "Success"
        Complete-Script -ExitCode 0
    }

    if ($null -eq $currentValueData) {
        Write-Log "Registry value '$registryValueName' is not present, it will be created" -Tag "Info"
    }
    else {
        Write-Log "Registry value '$registryValueName' is set to '$currentValueData' but expected '$registryValueData', it will be updated" -Tag "Info"
    }

    Set-RegistryValueData -Path $registryPath -Name $registryValueName -Data $registryValueData

    Write-Log "Verifying registry value '$registryValueName' after remediation" -Tag "Get"
    $verifiedValueData = Get-RegistryValueData -Path $registryPath -Name $registryValueName

    if ($verifiedValueData -eq $registryValueData) {
        Write-Log "Registry value '$registryValueName' is now set to '$verifiedValueData', remediation completed" -Tag "Success"
        Complete-Script -ExitCode 0
    }

    Write-Log "Verification failed, registry value '$registryValueName' is '$verifiedValueData' but expected '$registryValueData'" -Tag "Error"
    Complete-Script -ExitCode 1
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}
