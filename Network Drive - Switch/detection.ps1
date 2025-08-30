# =========================[ Configuration ]=========================

# Define your mappings here (add as many as you need)
$networkDrive = @(
    [pscustomobject]@{ Letter = 'M'; OldShare = '\\test.local\Marketing'; NewShare = '\\test.local\Files\Marketing' }
    # ,[pscustomobject]@{ Letter = 'Q'; OldShare = '\\old\dept'; NewShare = '\\new\dept' }
)

# =========================[ Logging Block ]=========================

# Script version:   2025-05-29 11:10
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$scriptName = "Network Drive - Switch - M"
$logFileName = "detection.log"

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$env:USERNAME\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "
    }

    $color = switch ($rawTag.Trim()) {
        "Start"   { "Cyan" }
        "Check"   { "Blue" }
        "Info"    { "Yellow" }
        "Success" { "Green" }
        "Error"   { "Red" }
        "Debug"   { "DarkYellow" }
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

function Complete-Script {
    param([int]$ExitCode)
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}

# ---------------------------[ Helpers ]---------------------------

function Convert-Path {
    param([string]$Path)
    if ($null -eq $Path) { return $null }
    $trimmed = $Path.Trim()
    if ($trimmed.EndsWith("\")) { $trimmed = $trimmed.TrimEnd("\") }
    return $trimmed.ToLowerInvariant()
}

function Get-MappedDriveTarget {
    param([char]$Letter)

    # Prefer HKCU\Network\<Letter> (reliable in user context)
    $regPath = "HKCU:\Network\$Letter"
    try {
        if (Test-Path $regPath) {
            $remotePath = (Get-ItemProperty -Path $regPath -ErrorAction Stop).RemotePath
            if ($null -ne $remotePath) { return $remotePath }
        }
    } catch { }

    # Fallback to PSDrive
    try {
        $psd = Get-PSDrive -Name $Letter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($null -ne $psd) { return $psd.Root }
    } catch { }

    return $null
}

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

$needsRemediation = $false

foreach ($item in $networkDrive) {
    $letter = [char]$item.Letter
    $old    = Convert-Path $item.OldShare
    $new    = Convert-Path $item.NewShare

    Write-Log "Checking drive $($letter): for old '$($item.OldShare)' vs new '$($item.NewShare)'" -Tag "Check"

    $current = Get-MappedDriveTarget -Letter $letter
    if ($null -eq $current) {
        Write-Log "Drive $($letter): is not mapped. Considered compliant." -Tag "Info"
        continue
    }

    $currentNorm = Convert-Path $current
    Write-Log "Drive $($letter): currently mapped to '$current'" -Tag "Info"

    if ($currentNorm -eq $old) {
        Write-Log "Drive $($letter): mapped to OLD path -> remediation required." -Tag "Error"
        $needsRemediation = $true
    } elseif ($currentNorm -eq $new) {
        Write-Log "Drive $($letter): mapped to NEW path -> compliant." -Tag "Success"
    } else {
        Write-Log "Drive $($letter): mapped to an unexpected path '$current'. Treated as compliant for this check." -Tag "Info"
    }
}

if ($needsRemediation) {
    Complete-Script -ExitCode 1  # Signal remediation required
} else {
    Complete-Script -ExitCode 0  # Compliant
}
