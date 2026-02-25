# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Remove-Printer"
$logFileName = "detection.log"

# ---------------------------[ Configuration ]---------------------------
# Define printers to remove. Supports exact names and wildcards (* and ?).
# Works for shared (UNC), TCP/IP, USB - any printer type. Match by display name.
# Examples:
#   "\\PrintServer01\HR-Printer"      - exact match
#   "\\printserver\PRT-HR-*"          - all printers starting with PRT-HR-
#   "\\printserver\*"                 - all printers from that print server
#   "HR"                              - local TCP/IP printer named "HR"
$printersToRemove = @(
    "\\PrintServer01\HR-Printer"
    "\\PrintServer01\Accounting-Printer"
    # "\\printserver\PRT-HR-*"        - wildcard: all PRT-HR-* from server
    # "\\printserver\*"               - wildcard: all printers from server
)

# ---------------------------[ Logging Setup ]---------------------------
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

    if (($Tag -eq "Debug") -and (-not $logDebug)) { return }
    if (($Tag -eq "Get")   -and (-not $logGet))   { return }
    if (($Tag -eq "Run")   -and (-not $logRun))   { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList   = @("Start", "Get", "Run", "Info", "Success", "Error", "Debug", "End")
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
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"
Write-Log "Target printers to detect: $($printersToRemove -join ', ')" -Tag "Debug"

# ---------------------------[ Detection Logic ]---------------------------
try {
    Write-Log "Retrieving installed printers..." -Tag "Get"
    $installedPrinters = Get-Printer -ErrorAction Stop
    Write-Log "Found $($installedPrinters.Count) installed printer(s)" -Tag "Debug"

    $foundPrinters = @()
    foreach ($pattern in $printersToRemove) {
        $matchedPrinters = $installedPrinters | Where-Object { $_.Name -like $pattern }
        foreach ($printer in $matchedPrinters) {
            if ($printer.Name -notin $foundPrinters) {
                $foundPrinters += $printer.Name
                Write-Log "Target printer found (pattern '$pattern'): $($printer.Name)" -Tag "Get"
            }
        }
        if ($matchedPrinters.Count -eq 0) {
            Write-Log "No match for pattern: $pattern" -Tag "Debug"
        }
    }

    if ($foundPrinters.Count -gt 0) {
        Write-Log "Remediation required. Found $($foundPrinters.Count) printer(s) to remove: $($foundPrinters -join ', ')" -Tag "Info"
        Complete-Script -ExitCode 1
    }
    else {
        Write-Log "Compliant. No target printers found on device." -Tag "Success"
        Complete-Script -ExitCode 0
    }
}
catch {
    Write-Log "Detection failed: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Stack: $($_.ScriptStackTrace)" -Tag "Debug"
    Complete-Script -ExitCode 1
}
