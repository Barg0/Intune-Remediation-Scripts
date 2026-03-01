# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$scriptName = "Package - Network Drive Labels"
$logFileName = "package.log"

# ---------------------------[ Paths ]---------------------------
$csvPath          = "$PSScriptRoot\network-drive-labels.csv"
$templateDir      = "$PSScriptRoot\templates"
$outputDir        = "$PSScriptRoot\label-scripts"
$detectionTemplate  = "$templateDir\detection.ps1"
$remediationTemplate = "$templateDir\remediation.ps1"

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true

$logFileDirectory = "$PSScriptRoot\log"
$logFile = "$logFileDirectory\$logFileName"

if (-not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

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

# ---------------------------[ Validate Inputs ]---------------------------
if (-not (Test-Path $csvPath)) {
    Write-Log "CSV file not found: $csvPath" -Tag "Error"
    Complete-Script -ExitCode 1
}

if (-not (Test-Path $detectionTemplate)) {
    Write-Log "Detection template not found: $detectionTemplate" -Tag "Error"
    Complete-Script -ExitCode 1
}

if (-not (Test-Path $remediationTemplate)) {
    Write-Log "Remediation template not found: $remediationTemplate" -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "CSV file: $csvPath" -Tag "Get"
Write-Log "Detection template: $detectionTemplate" -Tag "Get"
Write-Log "Remediation template: $remediationTemplate" -Tag "Get"

# ---------------------------[ Read Templates ]---------------------------
$detectionContent  = Get-Content -Path $detectionTemplate -Raw
$remediationContent = Get-Content -Path $remediationTemplate -Raw

Write-Log "Templates loaded successfully." -Tag "Success"

# ---------------------------[ Read CSV ]---------------------------
$driveEntries = Import-Csv -Path $csvPath

if ($driveEntries.Count -eq 0) {
    Write-Log "CSV file is empty or has no valid rows." -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "Found $($driveEntries.Count) drive mapping(s) in CSV." -Tag "Info"

# ---------------------------[ Prepare Output Directory ]---------------------------
if (Test-Path $outputDir) {
    Write-Log "Cleaning existing output directory: $outputDir" -Tag "Run"
    Remove-Item -Path $outputDir -Recurse -Force
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Write-Log "Created output directory: $outputDir" -Tag "Success"

# ---------------------------[ Package Scripts ]---------------------------
$packaged = 0

foreach ($entry in $driveEntries) {
    $driveLetter = $entry.DriveLetter.Trim()
    $drivePath   = $entry.DrivePath.Trim()
    $driveLabel  = $entry.Label.Trim()

    if ([string]::IsNullOrWhiteSpace($driveLetter) -or
        [string]::IsNullOrWhiteSpace($drivePath) -or
        [string]::IsNullOrWhiteSpace($driveLabel)) {
        Write-Log "Skipping incomplete row: DriveLetter='$driveLetter' DrivePath='$drivePath' Label='$driveLabel'" -Tag "Error"
        continue
    }

    Write-Log "Packaging drive $driveLetter`: $drivePath -> '$driveLabel'" -Tag "Run"

    $driveDir = "$outputDir\$driveLetter"
    New-Item -ItemType Directory -Path $driveDir -Force | Out-Null

    $detection = $detectionContent.Replace("__DRIVE_LETTER__", $driveLetter).Replace("__DRIVE_PATH__", $drivePath).Replace("__DRIVE_LABEL__", $driveLabel)
    $remediation = $remediationContent.Replace("__DRIVE_LETTER__", $driveLetter).Replace("__DRIVE_PATH__", $drivePath).Replace("__DRIVE_LABEL__", $driveLabel)

    $detection | Set-Content -Path "$driveDir\detection.ps1" -Encoding UTF8
    $remediation | Set-Content -Path "$driveDir\remediation.ps1" -Encoding UTF8

    Write-Log "Created $driveDir\detection.ps1" -Tag "Success"
    Write-Log "Created $driveDir\remediation.ps1" -Tag "Success"

    $packaged++
}

# ---------------------------[ Summary ]---------------------------
Write-Log "Packaged $packaged of $($driveEntries.Count) drive mapping(s)." -Tag "Info"

if ($packaged -eq $driveEntries.Count) {
    Write-Log "All drive mappings packaged successfully." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Some drive mappings were skipped due to errors." -Tag "Error"
    Complete-Script -ExitCode 1
}
