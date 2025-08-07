# Script version:   2025-08-07 11:45
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------

# Capture start time to log script duration
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------

# Script name used for folder/log naming
$scriptName = "Local Group - Network Configuration Operators"
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------

# Logging control switches
$log = $true                     # Set to $false to disable logging in shell
$enableLogFile = $true           # Set to $false to disable file output

# Define the log output location
$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile = "$logFileDirectory\$logFileName"

# Ensure the log directory exists
if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# Function to write structured logs to file and console
function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return } # Exit if logging is disabled

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start", "Check", "Info", "Success", "Error", "Debug", "End")
    $rawTag = $Tag.Trim()

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
        "Debug"   { "DarkYellow"}
        "End"     { "Cyan" }
        default   { "White" }
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    # Write to file if enabled
    if ($enableLogFile) {
        "$logMessage" | Out-File -FilePath $logFile -Append
    }

    # Write to console with color formatting
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
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString("hh\:mm\:ss\.ff"))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}
# Complete-Script -ExitCode 0

# ---------------------------[ Script Start ]---------------------------

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Remediation ]---------------------------

try {
    # 1. Get logged-on user
    $loggedOnUser = (Get-WmiObject -Class Win32_ComputerSystem).UserName
    if (-not $loggedOnUser) {
        Write-Log "No logged-on user detected." -Tag "Error"
        Complete-Script -ExitCode 1
    }

    # 2. Translate to SID
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount($loggedOnUser)
        $loggedOnUserSID = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        Write-Log "Logged-on user SID: $loggedOnUserSID" -Tag "Debug"
    } catch {
        Write-Log "Could not resolve SID for $loggedOnUser - $_" -Tag "Error"
        Complete-Script -ExitCode 1
    }

    # 3. Get group info
    $groupSID = 'S-1-5-32-556'
    $group = Get-LocalGroup -SID $groupSID
    $groupName = $group.Name

    # 4. Get current group members (by SID)
    $currentSIDs = Get-LocalGroupMember -Group $groupName | Select-Object -ExpandProperty SID
    Write-Log "Current '$groupName' members: $($currentSIDs -join ', ')" -Tag "Debug"

    if ($currentSIDs -contains $loggedOnUserSID) {
        Write-Log "User '$loggedOnUser' already in group '$groupName'. No action needed." -Tag "Success"
        Complete-Script -ExitCode 0
    }

    # 5. Add user to group (must use name)
    try {
        Add-LocalGroupMember -Group $groupName -Member $loggedOnUser -ErrorAction Stop
        Write-Log "Added '$loggedOnUser' to group '$groupName'." -Tag "Success"
    } catch {
        Write-Log "Failed to add user '$loggedOnUser' to group '$groupName': $_" -Tag "Error"
        Complete-Script -ExitCode 1
    }

    # 6. Confirm addition by SID
    $updatedSIDs = Get-LocalGroupMember -Group $groupName | Select-Object -ExpandProperty SID
    Write-Log "Updated '$groupName' members: $($updatedSIDs -join ', ')" -Tag "Debug"

    if ($updatedSIDs -contains $loggedOnUserSID) {
        Write-Log "Confirmed: '$loggedOnUser' successfully added to '$groupName'." -Tag "Success"
        Complete-Script -ExitCode 0
    } else {
        Write-Log "Post-check failed: '$loggedOnUser' not found in '$groupName'." -Tag "Error"
        Complete-Script -ExitCode 1
    }

} catch {
    Write-Log "Unexpected remediation error: $_" -Tag "Error"
    Complete-Script -ExitCode 1
}