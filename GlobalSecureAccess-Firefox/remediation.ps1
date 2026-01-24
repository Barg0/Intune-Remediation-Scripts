# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Firefox-GlobalSecureAccess"
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------
# Logging configuration
$log           = $true
$logDebug      = $false   # Set to $true for verbose DEBUG logging
$logGet        = $true    # enable/disable all [Get] logs
$logRun        = $true    # enable/disable all [Run] logs
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
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

    # Per-tag switches
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

# ---------------------------[ Main Script ]---------------------------
# Define paths
$distributionDir = "C:\Program Files\Mozilla Firefox\distribution"
$destination     = Join-Path -Path $distributionDir -ChildPath "policies.json"
$backup          = "$destination.bak"

Write-Log "Starting Firefox policies.json remediation" -Tag "Info"
Write-Log "Distribution directory: $distributionDir" -Tag "Get"
Write-Log "Destination file: $destination" -Tag "Get"
Write-Log "Backup file: $backup" -Tag "Get"

# Initialize variable for existing JSON
$existingJson = $null

# Try to read and parse existing policies.json
if (Test-Path -Path $destination) {
    Write-Log "Existing policies.json found, attempting to read" -Tag "Get"
    
    try {
        $fileContent = Get-Content -Path $destination -Raw -ErrorAction Stop
        
        if ($fileContent -and $fileContent.Trim().Length -gt 0) {
            Write-Log "File content read, attempting to parse JSON" -Tag "Run"
            $existingJson = $fileContent | ConvertFrom-Json
            Write-Log "Existing JSON parsed successfully" -Tag "Success"
        }
        else {
            Write-Log "File exists but is empty" -Tag "Info"
        }
    }
    catch {
        Write-Log "Existing policies.json is malformed. Starting fresh. Error: $_" -Tag "Error"
        $existingJson = $null
    }
}
else {
    Write-Log "policies.json does not exist, will create new" -Tag "Info"
}

# Create a new JSON structure if none exists
if (-not $existingJson) {
    Write-Log "Creating new JSON structure" -Tag "Run"
    $existingJson = [PSCustomObject]@{
        policies = [PSCustomObject]@{
            Preferences = @{}
        }
    }
    Write-Log "New JSON structure created" -Tag "Success"
}

# Ensure policies and Preferences nodes exist
if (-not $existingJson.policies) {
    Write-Log "Adding policies node" -Tag "Run"
    $existingJson | Add-Member -MemberType NoteProperty -Name policies -Value ([PSCustomObject]@{}) -Force
    Write-Log "Policies node added" -Tag "Success"
}

if (-not $existingJson.policies.Preferences) {
    Write-Log "Adding Preferences node" -Tag "Run"
    $existingJson.policies | Add-Member -MemberType NoteProperty -Name Preferences -Value @{} -Force
    Write-Log "Preferences node added" -Tag "Success"
}

# Convert Preferences to hashtable if needed
if ($existingJson.policies.Preferences -isnot [hashtable]) {
    Write-Log "Converting Preferences to hashtable" -Tag "Run"
    $prefs = @{}
    $existingJson.policies.Preferences.psobject.Properties | ForEach-Object {
        $prefs[$_.Name] = $_.Value
    }
    $existingJson.policies.Preferences = $prefs
    Write-Log "Preferences converted to hashtable" -Tag "Success"
}

$prefObj = $existingJson.policies.Preferences
$updated = $false

Write-Log "Checking and updating QUIC (HTTP/3) setting" -Tag "Get"
# Ensure QUIC is disabled and locked
if (-not $prefObj.ContainsKey("network.http.http3.enable") -or 
    $prefObj["network.http.http3.enable"].Value -ne $false -or 
    $prefObj["network.http.http3.enable"].Status -ne "locked") {
    
    Write-Log "QUIC setting needs update or creation" -Tag "Run"
    $prefObj["network.http.http3.enable"] = @{
        Value  = $false
        Status = "locked"
    }
    $updated = $true
    Write-Log "QUIC setting updated: disabled and locked" -Tag "Success"
}
else {
    Write-Log "QUIC setting is already compliant" -Tag "Info"
}

Write-Log "Checking and updating DNS over HTTPS (DoH) setting" -Tag "Get"
# Ensure DNS over HTTPS is disabled and locked
if (-not $prefObj.ContainsKey("network.trr.mode") -or 
    $prefObj["network.trr.mode"].Value -ne 0 -or 
    $prefObj["network.trr.mode"].Status -ne "locked") {
    
    Write-Log "DoH setting needs update or creation" -Tag "Run"
    $prefObj["network.trr.mode"] = @{
        Value  = 0
        Status = "locked"
    }
    $updated = $true
    Write-Log "DoH setting updated: disabled and locked" -Tag "Success"
}
else {
    Write-Log "DoH setting is already compliant" -Tag "Info"
}

# If any updates were made, back up and write the new JSON
if ($updated) {
    Write-Log "Changes detected, backing up existing file and writing new configuration" -Tag "Run"
    
    try {
        # Create distribution directory if it doesn't exist
        if (-not (Test-Path -Path $distributionDir)) {
            Write-Log "Creating distribution directory: $distributionDir" -Tag "Run"
            New-Item -ItemType Directory -Path $distributionDir -Force | Out-Null
            Write-Log "Distribution directory created" -Tag "Success"
        }
        
        # Backup existing file if it exists
        if (Test-Path -Path $destination) {
            Write-Log "Creating backup: $backup" -Tag "Run"
            Copy-Item -Path $destination -Destination $backup -Force -ErrorAction Stop
            Write-Log "Backup created successfully" -Tag "Success"
        }
        
        # Convert to JSON and write
        Write-Log "Converting to JSON format" -Tag "Run"
        $jsonOut = $existingJson | ConvertTo-Json -Depth 10 -Compress
        Write-Log "JSON conversion completed" -Tag "Success"
        
        Write-Log "Writing policies.json file" -Tag "Run"
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($destination, $jsonOut, $utf8NoBomEncoding)
        Write-Log "policies.json written successfully" -Tag "Success"
        Write-Log "Remediation completed successfully" -Tag "Success"
        
        Complete-Script -ExitCode 0
    }
    catch {
        Write-Log "Error during file write operation: $_" -Tag "Error"
        Write-Log "Error details: $($_.Exception.Message)" -Tag "Error"
        Complete-Script -ExitCode 1
    }
}
else {
    Write-Log "No changes required - configuration is already compliant" -Tag "Success"
    Complete-Script -ExitCode 0
}
