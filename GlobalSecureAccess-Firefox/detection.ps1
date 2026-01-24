# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Firefox-GlobalSecureAccess"
$logFileName = "detection.log"

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
# Define the path to the Firefox policies.json file
$destination = "C:\Program Files\Mozilla Firefox\distribution\policies.json"
$compliant   = $false

Write-Log "Checking Firefox policies.json compliance" -Tag "Info"
Write-Log "Target file: $destination" -Tag "Get"

# Check if the file exists
if (Test-Path -Path $destination) {
    Write-Log "File exists, reading content" -Tag "Get"
    
    try {
        # Read the file content
        $fileContent = Get-Content -Path $destination -Raw -ErrorAction Stop
        Write-Log "File content read successfully" -Tag "Success"
        
        if ($fileContent -and $fileContent.Trim().Length -gt 0) {
            Write-Log "Parsing JSON content" -Tag "Run"
            
            # Parse JSON content
            $json = $fileContent | ConvertFrom-Json
            Write-Log "JSON parsed successfully" -Tag "Success"

            # Check if Preferences exist under policies
            if ($json.policies -and $json.policies.Preferences) {
                Write-Log "Preferences node found in policies" -Tag "Get"
                $prefs = $json.policies.Preferences

                # Convert Preferences to hashtable if needed
                if ($prefs -isnot [hashtable]) {
                    Write-Log "Converting Preferences to hashtable" -Tag "Run"
                    $temp = @{}
                    $prefs.psobject.Properties | ForEach-Object {
                        $temp[$_.Name] = $_.Value
                    }
                    $prefs = $temp
                    Write-Log "Preferences converted to hashtable" -Tag "Success"
                }

                # Initialize compliance flags
                $quicCompliant = $false
                $dohCompliant  = $false

                Write-Log "Checking QUIC (HTTP/3) setting" -Tag "Get"
                # Check if QUIC is disabled and locked
                if ($prefs.ContainsKey("network.http.http3.enable")) {
                    $quicValue = $prefs["network.http.http3.enable"]
                    Write-Log "QUIC setting found: Value=$($quicValue.Value), Status=$($quicValue.Status)" -Tag "Debug"
                    
                    if ($quicValue.Value -eq $false -and $quicValue.Status -eq "locked") {
                        $quicCompliant = $true
                        Write-Log "QUIC is compliant (disabled and locked)" -Tag "Success"
                    }
                    else {
                        Write-Log "QUIC is non-compliant" -Tag "Error"
                    }
                }
                else {
                    Write-Log "QUIC setting not found" -Tag "Error"
                }

                Write-Log "Checking DNS over HTTPS (DoH) setting" -Tag "Get"
                # Check if DNS over HTTPS is disabled and locked
                if ($prefs.ContainsKey("network.trr.mode")) {
                    $dohValue = $prefs["network.trr.mode"]
                    Write-Log "DoH setting found: Value=$($dohValue.Value), Status=$($dohValue.Status)" -Tag "Debug"
                    
                    if ($dohValue.Value -eq 0 -and $dohValue.Status -eq "locked") {
                        $dohCompliant = $true
                        Write-Log "DoH is compliant (disabled and locked)" -Tag "Success"
                    }
                    else {
                        Write-Log "DoH is non-compliant" -Tag "Error"
                    }
                }
                else {
                    Write-Log "DoH setting not found" -Tag "Error"
                }

                # Set overall compliance if both settings are correct
                if ($quicCompliant -and $dohCompliant) {
                    $compliant = $true
                    Write-Log "Overall compliance: COMPLIANT (both QUIC and DoH are properly configured)" -Tag "Success"
                }
                else {
                    Write-Log "Overall compliance: NON-COMPLIANT (QUIC: $quicCompliant, DoH: $dohCompliant)" -Tag "Error"
                }
            }
            else {
                Write-Log "Preferences node not found in policies" -Tag "Error"
            }
        }
        else {
            Write-Log "File is empty or contains only whitespace" -Tag "Error"
        }
    }
    catch {
        Write-Log "Failed to parse policies.json: $_" -Tag "Error"
        Write-Log "Error details: $($_.Exception.Message)" -Tag "Error"
    }
}
else {
    Write-Log "File does not exist at: $destination" -Tag "Error"
}

# Output compliance result
if ($compliant) {
    Write-Log "Final result: COMPLIANT" -Tag "Success"
    Write-Output "Compliant"
    Complete-Script -ExitCode 0
}
else {
    Write-Log "Final result: NON-COMPLIANT" -Tag "Error"
    Write-Output "Non-compliant"
    Complete-Script -ExitCode 1
}
