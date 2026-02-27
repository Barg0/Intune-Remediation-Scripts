# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Printer - PRINTERNAME"
$logFileName = "detection.log"

# ---------------------------[ Shared Printers ]---------------------------
$sharedPrinters = @(
    "\\server.local\printerName",
    "\\server.local\printerName"
)

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logRun        = $false
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$env:USERNAME\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Write-Log Function ]---------------------------
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }
    if (($Tag -eq "Run") -and (-not $logRun)) { return }

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
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Detection Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Printer Check ]---------------------------
Write-Log "Retrieving installed printers..." -Tag "Get"
$installedPrinters = Get-Printer
$missingPrinters   = @()

foreach ($printerPath in $sharedPrinters) {
    $exists = $installedPrinters | Where-Object { $_.Name -eq $printerPath -or $_.ShareName -eq $printerPath }
    if ($exists) {
        Write-Log "Printer '$printerPath' is installed." -Tag "Info"
    }
    else {
        Write-Log "Printer '$printerPath' is missing." -Tag "Error"
        $missingPrinters += $printerPath
    }
}

if ($missingPrinters.Count -eq 0) {
    Write-Log "All printers are installed." -Tag "Success"
    Complete-Script -ExitCode 0
}
else {
    Write-Log "$($missingPrinters.Count) printer(s) are missing." -Tag "Error"
    Complete-Script -ExitCode 1
}
