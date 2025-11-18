# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Set-DefaultOutlookFont"
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output
$logDebug = $false               # Set to $true to allow debug logs

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$($env:USERNAME)\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    [CmdletBinding()]
    param (
        [string]$message,
        [string]$tag = "Info"
    )

    if (-not $log) { return } # Exit if all logging disabled

    # Handle debug suppression
    if ($tag -eq "Debug" -and -not $logDebug) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $tag.Trim()

    if ($tagList -contains $rawTag) {
        $rawTag = $rawTag.PadRight(7)
    } else {
        $rawTag = "Error  "  # Fallback if an unrecognized tag is used
    }

    # Set tag colors
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

    $logMessage = "$timestamp [  $rawTag ] $message"

    # Write to file if enabled
    if ($enableLogFile) {
        $logMessage | Out-File -FilePath $logFile -Append
    }

    # Write to console with color formatting
    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$message"
}

# ---------------------------[ Exit Function ]---------------------------

function Stop-Script {
    param(
        [int]$exitCode
    )

    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $exitCode
}

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Remediation Logic ]---------------------------

# Replace ... with your actual hex sequences
$valueSimple = "3C,00,00,00,1F,00,00,F8,00,00,00,40,DC,00,00,00,00,00,00,00,00,00,00,00,00,22,43,61,6C,69,62,72,69,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00" 
$valueComposeComplex = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,73,70,61,6E,2E,50,65,72,73,6F,6E,61,6C,43,6F,6D,70,6F,73,65,53,74,79,6C,65,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,61,6D,65,3A,22,50,65,72,73,6F,6E,61,6C,20,43,6F,6D,70,6F,73,65,20,53,74,79,6C,65,22,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,74,79,70,65,3A,70,65,72,73,6F,6E,61,6C,2D,63,6F,6D,70,6F,73,65,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,75,6E,68,69,64,65,3A,6E,6F,3B,0D,0A,09,6D,73,6F,2D,61,6E,73,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,31,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,32,2E,30,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,43,61,6C,69,62,72,69,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,61,73,63,69,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,43,61,6C,69,62,72,69,3B,0D,0A,09,6D,73,6F,2D,68,61,6E,73,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,43,61,6C,69,62,72,69,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,63,6F,6C,6F,72,3A,77,69,6E,64,6F,77,74,65,78,74,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A" 
$valueReplyComplex = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,73,70,61,6E,2E,50,65,72,73,6F,6E,61,6C,52,65,70,6C,79,53,74,79,6C,65,31,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,61,6D,65,3A,22,50,65,72,73,6F,6E,61,6C,20,52,65,70,6C,79,20,53,74,79,6C,65,31,22,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,74,79,70,65,3A,70,65,72,73,6F,6E,61,6C,2D,72,65,70,6C,79,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,75,6E,68,69,64,65,3A,6E,6F,3B,0D,0A,09,6D,73,6F,2D,61,6E,73,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,31,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,32,2E,30,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,43,61,6C,69,62,72,69,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,61,73,63,69,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,43,61,6C,69,62,72,69,3B,0D,0A,09,6D,73,6F,2D,68,61,6E,73,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,43,61,6C,69,62,72,69,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,63,6F,6C,6F,72,3A,77,69,6E,64,6F,77,74,65,78,74,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"
$valueTextComplex = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,70,2E,4D,73,6F,50,6C,61,69,6E,54,65,78,74,2C,20,6C,69,2E,4D,73,6F,50,6C,61,69,6E,54,65,78,74,2C,20,64,69,76,2E,4D,73,6F,50,6C,61,69,6E,54,65,78,74,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,70,72,69,6F,72,69,74,79,3A,39,39,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6C,69,6E,6B,3A,22,50,6C,61,69,6E,20,54,65,78,74,20,43,68,61,72,22,3B,0D,0A,09,6D,61,72,67,69,6E,3A,30,63,6D,3B,0D,0A,09,6D,73,6F,2D,70,61,67,69,6E,61,74,69,6F,6E,3A,77,69,64,6F,77,2D,6F,72,70,68,61,6E,3B,0D,0A,09,66,6F,6E,74,2D,73,69,7A,65,3A,31,31,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,35,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,43,61,6C,69,62,72,69,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,66,61,72,65,61,73,74,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,6D,73,6F,2D,66,6F,6E,74,2D,6B,65,72,6E,69,6E,67,3A,31,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,6C,69,67,61,74,75,72,65,73,3A,73,74,61,6E,64,61,72,64,63,6F,6E,74,65,78,74,75,61,6C,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"

$registryPath = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\mailsettings'

$nameComposeSimple = "ComposeFontSimple"
$nameComposeComplex = "ComposeFontComplex"
$nameReplySimple = "ReplyFontSimple"
$nameReplyComplex = "ReplyFontComplex"
$nameTextSimple = "TextFontSimple"
$nameTextComplex = "TextFontComplex"

Write-Log "Preparing hex byte arrays from provided font values." -Tag "Debug"

$hexSimple = $valueSimple.Split(',') | ForEach-Object { "0x$_" }
$hexComposeComplex = $valueComposeComplex.Split(',') | ForEach-Object { "0x$_" }
$hexReplyComplex = $valueReplyComplex.Split(',') | ForEach-Object { "0x$_" }
$hexTextComplex = $valueTextComplex.Split(',') | ForEach-Object { "0x$_" }

try {
    if (-not (Test-Path -Path $registryPath)) {
        Write-Log "Registry path '$registryPath' does not exist. Creating it and required properties." -Tag "Info"

        New-Item -Path $registryPath -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name NewTheme -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name $nameComposeSimple -Value ([byte[]]$hexSimple) -PropertyType Binary -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name $nameReplySimple -Value ([byte[]]$hexSimple) -PropertyType Binary -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name $nameTextSimple -Value ([byte[]]$hexSimple) -PropertyType Binary -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name $nameComposeComplex -Value ([byte[]]$hexComposeComplex) -PropertyType Binary -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name $nameReplyComplex -Value ([byte[]]$hexReplyComplex) -PropertyType Binary -Force | Out-Null
        New-ItemProperty -Path $registryPath -Name $nameTextComplex -Value ([byte[]]$hexTextComplex) -PropertyType Binary -Force | Out-Null
    }
    else {
        Write-Log "Registry path '$registryPath' exists. Updating font settings." -Tag "Info"

        Set-ItemProperty -Path $registryPath -Name NewTheme -Value $null -Force
        Set-ItemProperty -Path $registryPath -Name ThemeFont -Value 2 -Force
        Set-ItemProperty -Path $registryPath -Name $nameComposeSimple -Value ([byte[]]$hexSimple) -Force
        Set-ItemProperty -Path $registryPath -Name $nameReplySimple -Value ([byte[]]$hexSimple) -Force
        Set-ItemProperty -Path $registryPath -Name $nameTextSimple -Value ([byte[]]$hexSimple) -Force
        Set-ItemProperty -Path $registryPath -Name $nameComposeComplex -Value ([byte[]]$hexComposeComplex) -Force
        Set-ItemProperty -Path $registryPath -Name $nameReplyComplex -Value ([byte[]]$hexReplyComplex) -Force
        Set-ItemProperty -Path $registryPath -Name $nameTextComplex -Value ([byte[]]$hexTextComplex) -Force
    }

    Write-Log "Mail font remediation completed successfully." -Tag "Success"
    Stop-Script -ExitCode 0
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)" -Tag "Error"
    Stop-Script -ExitCode 1
}
