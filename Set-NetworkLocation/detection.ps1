# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Set-NetworkLocation"
$logFileName = "detection.log"

# ---------------------------[ Configuration ]---------------------------
# Set the display name and network target for the desired Network Location.
# Target accepts UNC paths (\\server\share), WebDAV URLs, or FTP addresses.
$networkLocationName   = "My Network Share"
$networkLocationTarget = "\\server.domain.tld\share"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

# User context: logs written to LOCALAPPDATA (no elevation required)
$logFileDirectory = "$env:LOCALAPPDATA\IntuneLogs\Scripts\$($env:USERNAME)\$scriptName"
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
    Write-Log "==================== End ====================" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "==================== Start ====================" -Tag "Start"
Write-Log "$env:COMPUTERNAME | $env:USERNAME | $scriptName" -Tag "Info"

# ---------------------------[ Derived Paths ]---------------------------
$networkShortcutsPath = "$env:APPDATA\Microsoft\Windows\Network Shortcuts"
$locationFolderPath   = Join-Path -Path $networkShortcutsPath -ChildPath $networkLocationName
$shortcutFilePath     = Join-Path -Path $locationFolderPath   -ChildPath "target.lnk"

# ---------------------------[ Functions ]---------------------------
function Test-NetworkLocationFolder {
    param([string]$FolderPath)

    $exists = Test-Path -Path $FolderPath -PathType Container
    $status = if ($exists) { "found" } else { "not found" }
    Write-Log "Location folder: $status" -Tag "Get"
    return $exists
}

function Test-ShortcutFile {
    param([string]$ShortcutPath)

    $exists = Test-Path -Path $ShortcutPath -PathType Leaf
    $status = if ($exists) { "found" } else { "not found" }
    Write-Log "Shortcut file: $status" -Tag "Get"
    return $exists
}

function Get-ShortcutTarget {
    param([string]$ShortcutPath)

    try {
        $shell        = New-Object -ComObject WScript.Shell
        $shortcut     = $shell.CreateShortcut($ShortcutPath)
        $resolvedPath = $shortcut.TargetPath
        Write-Log "Shortcut target: $resolvedPath" -Tag "Debug"
        return $resolvedPath
    }
    catch {
        Write-Log "Failed to read shortcut: $($_.Exception.Message)" -Tag "Error"
        return $null
    }
}

function Test-NetworkLocationCompliant {
    param(
        [string]$FolderPath,
        [string]$ShortcutPath,
        [string]$ExpectedTarget
    )

    if (-not (Test-NetworkLocationFolder -FolderPath $FolderPath)) {
        return $false
    }

    if (-not (Test-ShortcutFile -ShortcutPath $ShortcutPath)) {
        return $false
    }

    $actualTarget = Get-ShortcutTarget -ShortcutPath $ShortcutPath

    if ($actualTarget -ne $ExpectedTarget) {
        Write-Log "Target mismatch. Expected: $ExpectedTarget | Actual: $actualTarget" -Tag "Info"
        return $false
    }

    return $true
}

# ---------------------------[ Detection ]---------------------------
Write-Log "Checking: $networkLocationName -> $networkLocationTarget" -Tag "Info"

$isCompliant = Test-NetworkLocationCompliant `
    -FolderPath      $locationFolderPath `
    -ShortcutPath    $shortcutFilePath `
    -ExpectedTarget  $networkLocationTarget

if ($isCompliant) {
    Write-Log "Compliant" -Tag "Success"
    Complete-Script -ExitCode 0
}
else {
    Write-Log "Non-compliant" -Tag "Error"
    Complete-Script -ExitCode 1
}
