# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Set-Wallpaper"
$logFileName = "detection.log"

# ===========================================================================
#                            CONFIGURATION
# ===========================================================================
$configWallpaper = "default"
# "default" uses the Windows default wallpaper for the detected OS version.
# Set to a full path like "C:\path\to\image.jpg" to use a custom wallpaper.
# ===========================================================================

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$env:USERNAME\$($scriptName)"
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
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ OS Detection ]---------------------------
$osVersion   = (Get-CimInstance Win32_OperatingSystem).Version
$isWindows11 = $osVersion -like "10.0.2*"
$isWindows10 = $osVersion -like "10.0.1*"

Write-Log "Detected OS version: $osVersion" -Tag "Get"

if ($isWindows11) {
    Write-Log "Operating system identified as Windows 11" -Tag "Info"
}
elseif ($isWindows10) {
    Write-Log "Operating system identified as Windows 10" -Tag "Info"
}
else {
    Write-Log "Unsupported OS version: $osVersion - script requires Windows 10 or 11" -Tag "Error"
    Complete-Script -ExitCode 1
}

$defaultWallpaperWin10 = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
$defaultWallpaperWin11 = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"

$wallpaperPath = switch ($configWallpaper) {
    "default" { if ($isWindows11) { $defaultWallpaperWin11 } else { $defaultWallpaperWin10 } }
    default   { $configWallpaper }
}

if (-not (Test-Path -Path $wallpaperPath)) {
    Write-Log "Wallpaper file not found: $wallpaperPath" -Tag "Error"
    Complete-Script -ExitCode 1
}

$cspKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

$currentPath   = $null
$currentUrl    = $null
$currentStatus = $null

if (Test-Path -Path $cspKey) {
    $props = Get-ItemProperty -Path $cspKey -ErrorAction SilentlyContinue
    if ($null -ne $props) {
        $currentPath   = $props.DesktopImagePath
        $currentUrl    = $props.DesktopImageUrl
        $currentStatus = $props.DesktopImageStatus
    }
}

$gotPath   = if ($null -eq $currentPath) { '' } else { "$currentPath" }
$gotUrl    = if ($null -eq $currentUrl) { '' } else { "$currentUrl" }
$gotStatus = if ($null -eq $currentStatus) { '' } else { "$currentStatus" }

$pathOk = ($gotPath -eq $wallpaperPath)
$urlOk  = ($gotUrl -eq $wallpaperPath)
$statusOk = ($null -ne $currentStatus) -and (([int]$currentStatus) -eq 1)

if ($pathOk -and $urlOk -and $statusOk) {
    Write-Log "PersonalizationCSP correctly configured for: $wallpaperPath" -Tag "Success"
    Complete-Script -ExitCode 0
}

if (-not $pathOk) {
    Write-Log "DesktopImagePath mismatch: expected '$wallpaperPath', got '$gotPath'" -Tag "Info"
}
if (-not $urlOk) {
    Write-Log "DesktopImageUrl mismatch: expected '$wallpaperPath', got '$gotUrl'" -Tag "Info"
}
if (-not $statusOk) {
    Write-Log "DesktopImageStatus mismatch: expected '1', got '$gotStatus'" -Tag "Info"
}

Complete-Script -ExitCode 1
