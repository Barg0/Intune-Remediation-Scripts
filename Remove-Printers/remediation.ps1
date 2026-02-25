# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Remove-Printer"
$logFileName = "remediation.log"

# ---------------------------[ Configuration ]---------------------------
# Define printers to remove (must match detection script). Supports wildcards (* and ?).
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
Write-Log "Printers to remove: $($printersToRemove -join ', ')" -Tag "Debug"

# ---------------------------[ Remediation Logic ]---------------------------
$removalSuccess = $true

try {
    Write-Log "Retrieving installed printers..." -Tag "Get"
    $installedPrinters = Get-Printer -ErrorAction Stop
    Write-Log "Found $($installedPrinters.Count) installed printer(s)" -Tag "Debug"

    # Resolve patterns (including wildcards) to actual printer names
    $printersToRemoveActual = @()
    foreach ($pattern in $printersToRemove) {
        $matchedPrinters = $installedPrinters | Where-Object { $_.Name -like $pattern }
        foreach ($printer in $matchedPrinters) {
            if ($printer.Name -notin $printersToRemoveActual) {
                $printersToRemoveActual += $printer.Name
            }
        }
    }
    Write-Log "Resolved to $($printersToRemoveActual.Count) printer(s) to remove" -Tag "Debug"

    foreach ($printerName in $printersToRemoveActual) {
        Write-Log "Removing printer: $printerName" -Tag "Run"
        try {
            Remove-Printer -Name $printerName -ErrorAction Stop
            Write-Log "Successfully removed printer: $printerName" -Tag "Success"
        }
        catch {
            Write-Log "Failed to remove printer '$printerName': $($_.Exception.Message)" -Tag "Error"
            Write-Log "Stack: $($_.ScriptStackTrace)" -Tag "Debug"
            $removalSuccess = $false
        }
    }

    if ($removalSuccess) {
        Write-Log "Remediation completed successfully." -Tag "Success"
        Complete-Script -ExitCode 0
    }
    else {
        Write-Log "Remediation completed with errors. Intune may retry." -Tag "Error"
        Complete-Script -ExitCode 1
    }
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Stack: $($_.ScriptStackTrace)" -Tag "Debug"
    Complete-Script -ExitCode 1
}
