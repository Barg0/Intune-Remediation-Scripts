# ---------------------------[ Global Secure Access Settings ]---------------------------
# Global Secure Access client registry values
# Path: HKLM:\SOFTWARE\Microsoft\Global Secure Access Client
$gsaRegistryPath = "HKLM:\SOFTWARE\Microsoft\Global Secure Access Client"

# HideSignOutButton (REG_DWORD) - 0x0 shown / 0x1 hidden (default: hidden)
# Show/hide the "Sign out" action (used when a user needs to sign in to the client with a different Entra user than Windows; must be same tenant; can reauthenticate).
$hideSignOutButton = 1 # Sign out: 0 shown / 1 hidden

# HideDisablePrivateAccessButton (REG_DWORD) - 0x0 shown / 0x1 hidden (default: hidden)
# Show/hide the "Disable Private Access" action (scenario: device on corporate network and user prefers direct access to private apps rather than tunneling).
$hideDisablePrivateAccessButton = 1 # Disable Private Access: 0 shown / 1 hidden

# HideDisableButton (REG_DWORD) - 0x0 shown / 0x1 hidden (default: shown)
# Show/hide the "Disable" action. If hidden, a nonprivileged user can't disable the client via the UI.
$hideDisableButton = 1 # Disable: 0 shown / 1 hidden

# RestrictNonPrivilegedUsers (REG_DWORD) - 0x0 / 0x1 (default: 0x0)
# 0x0: Nonprivileged users can disable/enable the client. 0x1: Disabling/enabling requires admin permissions (UAC); admin may also hide the Disable button.
$restrictNonPrivilegedUsers = 1 # 0 allowed / 1 restricted (admin required)


# ---------------------------[ Logging Config ]---------------------------
$enableLog = 1
$enableLogDebug = 0
$enableLogGet = 1
$enableLogRun = 1
$enableLogFile = 1
$logFileName = "remediation.log"

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date


# ---------------------------[ Script Name ]---------------------------
$scriptName = "GlobalSecureAccess-Settings"

# ---------------------------[ Logging Setup ]---------------------------
$log = [bool]$enableLog
$logDebug = [bool]$enableLogDebug     # Set to 1 for verbose DEBUG logging
$logGet = [bool]$enableLogGet         # enable/disable all [Get] logs
$logRun = [bool]$enableLogRun         # enable/disable all [Run] logs
$enableLogFile = [bool]$enableLogFile

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}


# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )

    if (-not $log) { return }

    # Per-tag switches
    if (($tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($tag -eq "Get") -and (-not $logGet)) { return }
    if (($tag -eq "Run") -and (-not $logRun)) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Get", "Run", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    }
    else {
        $rawTag = "Error  "
    }

    $color = switch ($rawTag.Trim()) {
        "Start" { "Cyan" }
        "Get" { "Blue" }
        "Run" { "Magenta" }
        "Info" { "Yellow" }
        "Success" { "Green" }
        "Error" { "Red" }
        "Debug" { "DarkYellow" }
        "End" { "Cyan" }
        default { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $message"

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
    Write-Host "$message"
}


# ---------------------------[ Exit Function ]---------------------------
function Complete-Script {
    param([int]$exitCode)

    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $exitCode
}


# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"


# ---------------------------[ Remediation ]---------------------------
try {
    $gsaSettings = @{
        "HideSignOutButton" = $hideSignOutButton
        "HideDisablePrivateAccessButton" = $hideDisablePrivateAccessButton
        "HideDisableButton" = $hideDisableButton
        "RestrictNonPrivilegedUsers" = $restrictNonPrivilegedUsers
    }

    if (-not (Test-Path -Path $gsaRegistryPath)) {
        Write-Log "Registry path missing; creating: $gsaRegistryPath" -Tag "Run"
        New-Item -Path $gsaRegistryPath -Force | Out-Null
    }
    else {
        Write-Log "Registry path exists: $gsaRegistryPath" -Tag "Get"
    }

    foreach ($setting in $gsaSettings.GetEnumerator()) {
        $settingName = $setting.Key
        $desiredValue = $setting.Value

        Write-Log "Setting $settingName to $desiredValue" -Tag "Run"
        Set-ItemProperty -Path $gsaRegistryPath -Name $settingName -Value $desiredValue -Type DWord -Force | Out-Null

        $currentValue = (Get-ItemProperty -Path $gsaRegistryPath -Name $settingName -ErrorAction SilentlyContinue).$settingName
        if ($currentValue -eq $desiredValue) {
            Write-Log "Verified $settingName = $currentValue" -Tag "Success"
        }
        else {
            Write-Log "Failed to verify $settingName. Current: $currentValue | Expected: $desiredValue" -Tag "Error"
            Complete-Script -ExitCode 1
        }
    }

    Write-Log "Remediation completed successfully." -Tag "Success"
    Complete-Script -ExitCode 0
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}