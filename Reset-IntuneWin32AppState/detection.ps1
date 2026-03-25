# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Reset-IntuneWin32AppState"
$logFileName = "detection.log"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Constants ]---------------------------
$script:win32AppsKeyPath              = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$script:exitCodeCompliant             = 0
$script:exitCodeNonCompliant          = 1
$script:win32EnforcementSuccess       = 0
$script:win32EnforcementPendingReboot = 3010

# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string] $Message,
        [string] $Tag = "Info"
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
    param ([int] $exitCode)

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $exitCode
}

# ---------------------------[ Support functions ]---------------------------
function Get-FailedWin32AppStates {
    if (-not (Test-Path -LiteralPath $script:win32AppsKeyPath)) {
        Write-Log "Win32Apps registry path not found: $($script:win32AppsKeyPath)" -Tag "Debug"
        return @()
    }

    $appSubKeys   = Get-ChildItem -LiteralPath $script:win32AppsKeyPath -Recurse -ErrorAction SilentlyContinue
    $failedStates = [System.Collections.Generic.List[object]]::new()

    foreach ($subKey in $appSubKeys) {
        $enforcementStateMessage = Get-ItemProperty -LiteralPath $subKey.PSPath -Name EnforcementStateMessage -ErrorAction SilentlyContinue
        if (-not $enforcementStateMessage) {
            continue
        }

        $messageText = $enforcementStateMessage.EnforcementStateMessage
        if ($messageText -match '"ErrorCode"\s*:\s*(-?\d+|null)') {
            $errorCodeToken = $Matches[1]
            if ($errorCodeToken -eq 'null') {
                continue
            }

            $parsedErrorCode = [int]$errorCodeToken
            $isSuccess       = ($parsedErrorCode -eq $script:win32EnforcementSuccess)
            $isSoftRebootOk  = ($parsedErrorCode -eq $script:win32EnforcementPendingReboot)

            if ((-not $isSuccess) -and (-not $isSoftRebootOk)) {
                $failedStates.Add([PSCustomObject]@{
                    subKeyPath = $subKey.PSPath
                    errorCode  = $parsedErrorCode
                }) | Out-Null
                Write-Log "Failed state at '$($subKey.PSPath)' with ErrorCode $parsedErrorCode" -Tag "Debug"
            }
        }
    }

    return $failedStates
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

$failedStates  = @(Get-FailedWin32AppStates)
$failureCount  = $failedStates.Count

Write-Log "Scan complete: $failureCount failed Win32 app state(s) (EnforcementStateMessage ErrorCode)." -Tag "Get"

if ($failureCount -gt 0) {
    Write-Log "Non-compliant: $failureCount failure(s) detected; remediation should run." -Tag "Info"
    Complete-Script -exitCode $script:exitCodeNonCompliant
}

Write-Log "Compliant: no failed Win32 app ErrorCode states detected." -Tag "Success"
Complete-Script -exitCode $script:exitCodeCompliant
