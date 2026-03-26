# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Reset-Win32AppState"
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
$script:enforcementStateFailures      = @(5000, 5003, 5006, 5999)

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

        $parsedErrorCode = $null
        if ($messageText -match '"ErrorCode"\s*:\s*(-?\d+|null)') {
            $token = $Matches[1]
            if ($token -ne 'null') {
                $parsedErrorCode = [int]$token
            }
        }

        $parsedEnforcementState = $null
        if ($messageText -match '"EnforcementState"\s*:\s*(\d+)') {
            $parsedEnforcementState = [int]$Matches[1]
        }

        $hasErrorCode = ($null -ne $parsedErrorCode) -and
                        ($parsedErrorCode -ne 0) -and
                        ($parsedErrorCode -ne 3010)

        $hasFailedState = ($null -ne $parsedEnforcementState) -and
                          ($script:enforcementStateFailures -contains $parsedEnforcementState)

        if ($hasErrorCode -or $hasFailedState) {
            $failedStates.Add([PSCustomObject]@{
                subKeyPath       = $subKey.PSPath
                errorCode        = if ($null -ne $parsedErrorCode) { $parsedErrorCode } else { 0 }
                enforcementState = if ($null -ne $parsedEnforcementState) { $parsedEnforcementState } else { 0 }
            }) | Out-Null
            Write-Log "Failed state at '$($subKey.PSPath)' - ErrorCode $parsedErrorCode, EnforcementState $parsedEnforcementState" -Tag "Debug"
        }
    }

    return $failedStates
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

$failedStates  = @(Get-FailedWin32AppStates)
$failureCount  = $failedStates.Count

Write-Log "Scan complete: $failureCount failed Win32 app state(s) (ErrorCode and/or EnforcementState)." -Tag "Get"

if ($failureCount -gt 0) {
    Write-Log "Non-compliant: $failureCount failure(s) detected; remediation should run." -Tag "Info"
    Complete-Script -exitCode 1
}

Write-Log "Compliant: no failed Win32 app states detected." -Tag "Success"
Complete-Script -exitCode 0
