# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Package-PrinterScripts"
$logFileName = "package.log"

# ---------------------------[ Configuration ]---------------------------
$csvPath            = Join-Path $PSScriptRoot "printers.csv"
$templateDirectory  = Join-Path $PSScriptRoot "template"
$outputDirectory    = Join-Path $PSScriptRoot "printers"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

$logFileDirectory = "$PSScriptRoot\log"
$logFile          = Join-Path $logFileDirectory $logFileName

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

# ---------------------------[ Functions ]---------------------------
function ConvertTo-PrinterArrayString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$PrintServer,

        [Parameter(Mandatory)]
        [string]$PrinterList
    )

    $printerNames     = ($PrinterList -split ";") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $formattedEntries = $printerNames | ForEach-Object { "    `"\\$PrintServer\$_`"" }

    return ($formattedEntries -join ",`n")
}

function New-PrinterScriptFromTemplate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [string]$PrinterArrayString
    )

    $templateContent  = Get-Content -Path $TemplatePath -Raw
    $generatedContent = $templateContent.Replace("__SCRIPTNAME__", $ScriptName).Replace("__PRINTERS__", $PrinterArrayString)

    $outputFolder = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path -Path $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    }

    Set-Content -Path $OutputPath -Value $generatedContent -Encoding UTF8
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Deploy Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Validate Prerequisites ]---------------------------
if (-not (Test-Path -Path $csvPath)) {
    Write-Log "CSV file not found: $csvPath" -Tag "Error"
    Complete-Script -ExitCode 1
}

$detectionTemplatePath  = Join-Path $templateDirectory "detection.ps1"
$remediationTemplatePath = Join-Path $templateDirectory "remediation.ps1"

if (-not (Test-Path -Path $detectionTemplatePath)) {
    Write-Log "Detection template not found: $detectionTemplatePath" -Tag "Error"
    Complete-Script -ExitCode 1
}

if (-not (Test-Path -Path $remediationTemplatePath)) {
    Write-Log "Remediation template not found: $remediationTemplatePath" -Tag "Error"
    Complete-Script -ExitCode 1
}

# ---------------------------[ Generate Scripts ]---------------------------
Write-Log "Reading printer definitions from: $csvPath" -Tag "Get"
$printerDefinitions = Import-Csv -Path $csvPath
Write-Log "Found $($printerDefinitions.Count) printer definition(s)" -Tag "Info"

$successCount = 0
$errorCount   = 0

foreach ($definition in $printerDefinitions) {
    $entryName   = $definition.ScriptName
    $printServer = $definition.PrintServer
    $printerList = $definition.Printers

    if (-not $entryName -or -not $printServer -or -not $printerList) {
        Write-Log "Skipping invalid row: ScriptName='$entryName', PrintServer='$printServer', Printers='$printerList'" -Tag "Error"
        $errorCount++
        continue
    }

    Write-Log "Processing '$entryName' (Server: $printServer)" -Tag "Run"
    Write-Log "Raw printer list: $printerList" -Tag "Debug"

    try {
        $printerArrayString = ConvertTo-PrinterArrayString -PrintServer $printServer -PrinterList $printerList
        Write-Log "Printer array for '$entryName':`n$printerArrayString" -Tag "Debug"

        $detectionOutputPath  = Join-Path $outputDirectory "$entryName\detection.ps1"
        $remediationOutputPath = Join-Path $outputDirectory "$entryName\remediation.ps1"

        New-PrinterScriptFromTemplate `
            -TemplatePath      $detectionTemplatePath `
            -OutputPath        $detectionOutputPath `
            -ScriptName        $entryName `
            -PrinterArrayString $printerArrayString
        Write-Log "Created detection script:  $detectionOutputPath" -Tag "Success"

        New-PrinterScriptFromTemplate `
            -TemplatePath      $remediationTemplatePath `
            -OutputPath        $remediationOutputPath `
            -ScriptName        $entryName `
            -PrinterArrayString $printerArrayString
        Write-Log "Created remediation script: $remediationOutputPath" -Tag "Success"

        $successCount++
    }
    catch {
        Write-Log "Failed to generate scripts for '$entryName': $_" -Tag "Error"
        $errorCount++
    }
}

# ---------------------------[ Summary ]---------------------------
$totalCount = $successCount + $errorCount
Write-Log "Generation complete: $successCount/$totalCount succeeded, $errorCount failed" -Tag "Info"

if ($errorCount -gt 0) {
    Complete-Script -ExitCode 1
}
else {
    Write-Log "All printer scripts generated successfully." -Tag "Success"
    Complete-Script -ExitCode 0
}

