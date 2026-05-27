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
