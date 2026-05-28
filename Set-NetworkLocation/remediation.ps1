# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Set-NetworkLocation"
$logFileName = "remediation.log"

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
$desktopIniPath       = Join-Path -Path $locationFolderPath   -ChildPath "desktop.ini"
$shortcutFilePath     = Join-Path -Path $locationFolderPath   -ChildPath "target.lnk"

# ---------------------------[ Functions ]---------------------------
function New-NetworkLocationFolder {
    param([string]$FolderPath)

    Write-Log "Creating location folder" -Tag "Run"

    if (Test-Path -Path $FolderPath -PathType Container) {
        Write-Log "Location folder already exists" -Tag "Debug"
        return
    }

    New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
    Write-Log "Location folder created" -Tag "Success"
}

function Set-FolderReadOnlyAttribute {
    # The ReadOnly attribute on a folder signals Explorer to read desktop.ini
    # and treat it as a special shell namespace item.
    param([string]$FolderPath)

    Write-Log "Applying ReadOnly attribute" -Tag "Run"

    $folder = Get-Item -Path $FolderPath -Force
    $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::ReadOnly

    Write-Log "ReadOnly attribute set" -Tag "Success"
}

function New-DesktopIniFile {
    # CLSID2 {0AFACED1-...} registers the folder as a Network Location shell item.
    # Flags=2 tells Explorer the folder redirects to the target.lnk shortcut.
    param([string]$IniPath)

    Write-Log "Writing desktop.ini" -Tag "Run"

    $iniContent = "[.ShellClassInfo]`r`nCLSID2={0AFACED1-E828-11D1-9187-B532F1E9575D}`r`nFlags=2"
    Set-Content -Path $IniPath -Value $iniContent -Encoding ASCII

    $iniFile = Get-Item -Path $IniPath -Force
    $iniFile.Attributes = $iniFile.Attributes -bor [System.IO.FileAttributes]::System -bor [System.IO.FileAttributes]::Hidden

    Write-Log "desktop.ini written" -Tag "Success"
}

function New-NetworkLocationShortcut {
    param(
        [string]$ShortcutPath,
        [string]$Target,
        [string]$Description
    )

    Write-Log "Creating shortcut -> $Target" -Tag "Run"

    $shell        = New-Object -ComObject WScript.Shell
    $shortcut     = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath  = $Target
    $shortcut.Description = $Description
    $shortcut.Save()

    Write-Log "Shortcut created" -Tag "Success"
}

function Test-NetworkLocationState {
    # Returns $true only when every component is already in the desired state.
    # Any missing or mismatched element causes an early $false return so the
    # caller can decide whether remediation is actually needed.
    param(
        [string]$FolderPath,
        [string]$IniPath,
        [string]$ShortcutPath,
        [string]$Target
    )

    Write-Log "Checking current state" -Tag "Get"

    # 1 - folder must exist
    if (-not (Test-Path -Path $FolderPath -PathType Container)) {
        Write-Log "State check: location folder missing" -Tag "Get"
        return $false
    }

    # 2 - folder must carry the ReadOnly attribute
    $folder = Get-Item -Path $FolderPath -Force
    if (-not ($folder.Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
        Write-Log "State check: ReadOnly attribute missing on folder" -Tag "Get"
        return $false
    }

    # 3 - desktop.ini must exist and contain the expected CLSID line
    if (-not (Test-Path -Path $IniPath -PathType Leaf)) {
        Write-Log "State check: desktop.ini missing" -Tag "Get"
        return $false
    }
    $iniContent = Get-Content -Path $IniPath -Raw -Encoding ASCII -ErrorAction SilentlyContinue
    if ($iniContent -notmatch [regex]::Escape("CLSID2={0AFACED1-E828-11D1-9187-B532F1E9575D}")) {
        Write-Log "State check: desktop.ini content mismatch" -Tag "Get"
        return $false
    }

    # 4 - target.lnk must exist and point to the correct target
    if (-not (Test-Path -Path $ShortcutPath -PathType Leaf)) {
        Write-Log "State check: shortcut missing" -Tag "Get"
        return $false
    }
    $shell           = New-Object -ComObject WScript.Shell
    $existingTarget  = $shell.CreateShortcut($ShortcutPath).TargetPath
    if ($existingTarget -ne $Target) {
        Write-Log "State check: shortcut target mismatch (current: $existingTarget)" -Tag "Get"
        return $false
    }

    Write-Log "State check: all components are compliant" -Tag "Get"
    return $true
}

function Set-NetworkLocation {
    param(
        [string]$FolderPath,
        [string]$IniPath,
        [string]$ShortcutPath,
        [string]$Target,
        [string]$DisplayName
    )

    New-NetworkLocationFolder    -FolderPath   $FolderPath
    Set-FolderReadOnlyAttribute  -FolderPath   $FolderPath
    New-DesktopIniFile           -IniPath      $IniPath
    New-NetworkLocationShortcut  -ShortcutPath $ShortcutPath -Target $Target -Description $DisplayName
}

# ---------------------------[ Remediation ]---------------------------
Write-Log "Remediating: $networkLocationName -> $networkLocationTarget" -Tag "Info"

try {
    $alreadyCompliant = Test-NetworkLocationState `
        -FolderPath   $locationFolderPath `
        -IniPath      $desktopIniPath `
        -ShortcutPath $shortcutFilePath `
        -Target       $networkLocationTarget

    if ($alreadyCompliant) {
        Write-Log "Network location already in desired state - no changes applied" -Tag "Success"
        Complete-Script -ExitCode 0
    }

    Set-NetworkLocation `
        -FolderPath   $locationFolderPath `
        -IniPath      $desktopIniPath `
        -ShortcutPath $shortcutFilePath `
        -Target       $networkLocationTarget `
        -DisplayName  $networkLocationName

    Write-Log "Network location configured" -Tag "Success"
    Complete-Script -ExitCode 0
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)" -Tag "Error"
    Complete-Script -ExitCode 1
}
