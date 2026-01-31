# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "BitLocker-StaleKeyCleanup"
$logFileName = "remediation.log"

# ---------------------------[ Config ]---------------------------
# API uses manage/common/bitlocker/{deviceId} - no tenant config needed (per Patch My PC)

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $true    # Set to $true for verbose DEBUG logging
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
$ErrorActionPreference = 'Stop'
$batchSize = 16   # API limit per DELETE request - do not exceed

Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

try {
    # ---------------------------[ Get MS-Organization-Access Certificate ]---------------------------
    Write-Log "Searching for MS-Organization-Access certificate in LocalMachine\My..." -Tag "Get"
    $deviceCert = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction SilentlyContinue |
        Where-Object { $_.Issuer -match 'MS-Organization-Access' } | Select-Object -First 1

    if (-not $deviceCert) {
        Write-Log "MS-Organization-Access certificate not found" -Tag "Error"
        Complete-Script -ExitCode 1
    }

    Write-Log "Certificate found - Thumbprint: $($deviceCert.Thumbprint) | Subject: $($deviceCert.Subject)" -Tag "Debug"

    # ---------------------------[ Get Device ID ]---------------------------
    Write-Log "Resolving device ID from certificate..." -Tag "Get"
    $deviceId = ($deviceCert.Subject -replace 'CN=', '').Trim()
    Write-Log "Device ID: $deviceId" -Tag "Debug"

    # ---------------------------[ Get Current Recovery Protectors from ALL Volumes ]---------------------------
    # If device has no BitLocker or no recovery protectors, currentKids stays empty = ALL keys in Entra are orphaned and should be deleted
    Write-Log "Getting all BitLocker volumes..." -Tag "Get"
    $bitLockerVolumes = Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.ProtectionStatus -eq 'On' }

    $currentKids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($bitLockerVolumes) {
        Write-Log "Found $($bitLockerVolumes.Count) protected volume(s)" -Tag "Debug"
        foreach ($volume in $bitLockerVolumes) {
            $recoveryProtectors = $volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
            foreach ($protector in $recoveryProtectors) {
                $kid = $protector.KeyProtectorId -replace '[{}]', ''
                $null = $currentKids.Add($kid)
                Write-Log "Volume $($volume.MountPoint): keeping KID $kid" -Tag "Debug"
            }
        }
    }
    else {
        Write-Log "No BitLocker-protected volumes - all keys in Entra are orphaned" -Tag "Debug"
    }

    Write-Log "Current KIDs to keep ($($currentKids.Count)): $(if ($currentKids.Count -gt 0) { $currentKids -join ', ' } else { '(none - delete all)' })" -Tag "Debug"

    # ---------------------------[ Retrieve Recovery Keys from Entra ]---------------------------
    # Per Patch My PC: manage/common/bitlocker/{deviceId} with BitLocker headers + MS-Organization-Access cert
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $clientRequestId = [Guid]::NewGuid().ToString()
    $bitLockerGetUrl = "https://enterpriseregistration.windows.net/manage/common/bitlocker/$deviceId`?api-version=1.2&client-request-id=$clientRequestId"

    $headers = @{
        "User-Agent"             = "BitLocker/10.0 (Windows)"
        "Accept"                 = "application/json"
        "ocp-adrs-client-name"   = "windows"
        "ocp-adrs-client-version" = "10.0"
    }

    Write-Log "Invoking GET: $bitLockerGetUrl" -Tag "Run"
    $response = $null
    try {
        $response = Invoke-RestMethod -Uri $bitLockerGetUrl -Method Get -Headers $headers -Certificate $deviceCert -UseBasicParsing -ErrorAction Stop
        Write-Log "GET succeeded" -Tag "Debug"
    }
    catch {
        Write-Log "GET failed: $($_.Exception.Message)" -Tag "Error"
        Complete-Script -ExitCode 1
    }

    $bitLockerBaseUrl = "https://enterpriseregistration.windows.net/manage/common/bitlocker/$deviceId"

    # ---------------------------[ Parse API Response and Identify Stale Keys ]---------------------------
    # Response format: { keys: [ { kid: "..." }, ... ] }
    Write-Log "Parsing API response - Type: $($response.GetType().Name)" -Tag "Debug"
    $keys = @()
    if ($response.keys) {
        $keys = @($response.keys)
        Write-Log "Response.keys - Count: $($keys.Count)" -Tag "Debug"
    }
    elseif ($response -is [array]) {
        $keys = $response
    }
    elseif ($response.value) {
        $keys = $response.value
    }
    elseif ($response.recoveryPasswords) {
        $keys = $response.recoveryPasswords
    }
    elseif ($response -is [pscustomobject]) {
        $keys = @($response)
    }

    # Only orphaned OS volume keys are deleted; data drive keys are left alone
    $volumeTypeOs = 1
    $volumeTypeMap = @{ '1' = 'OS'; '2' = 'FixedData'; '3' = 'Removable'; '4' = 'Unknown' }
    $staleKids = @()
    foreach ($keyItem in $keys) {
        $kid = if ($keyItem.kid) { $keyItem.kid } elseif ($keyItem.keyIdentifier) { $keyItem.keyIdentifier } elseif ($keyItem.id) { $keyItem.id } else { $keyItem.KeyProtectorId }
        if ($kid) {
            $normalizedKid = $kid -replace '[{}]', ''
            $volType = if ($keyItem.volumeType) { $keyItem.volumeType } elseif ($keyItem.vol) { $keyItem.vol } else { $null }
            $volLabel = "Unknown"
            if ($volType) {
                if ($volumeTypeMap["$volType"]) { $volLabel = $volumeTypeMap["$volType"] } else { $volLabel = "Type$volType" }
            }

            $isOrphaned = -not $currentKids.Contains($normalizedKid)
            $isOsVolume = ($volType -ne $null) -and ([string]$volType -eq [string]$volumeTypeOs)
            if ($isOrphaned -and $isOsVolume) {
                $staleKids += $normalizedKid
                Write-Log "Stale OS key $normalizedKid - Drive type: $volLabel" -Tag "Debug"
            }
            elseif ($isOrphaned -and -not $isOsVolume) {
                Write-Log "Skipping orphaned key $normalizedKid - not OS volume (type $volLabel), leaving in Entra" -Tag "Debug"
            }
        }
    }

    Write-Log "Total keys in Entra: $($keys.Count) | Orphaned OS keys to remove: $($staleKids.Count)" -Tag "Debug"

    if ($staleKids.Count -eq 0) {
        Write-Log "No stale keys to remove" -Tag "Success"
        Complete-Script -ExitCode 0
    }

    Write-Log "Found $($staleKids.Count) orphaned OS key(s) to remove" -Tag "Info"

    # ---------------------------[ Remove Stale Keys in Batches ]---------------------------
    $totalDeleted = 0
    $batchCount   = [Math]::Ceiling($staleKids.Count / $batchSize)

    Write-Log "Deleting in $batchCount batch(es) of max $batchSize keys each" -Tag "Debug"

    for ($batchIndex = 0; $batchIndex -lt $staleKids.Count; $batchIndex += $batchSize) {
        $endIndex = [Math]::Min($batchIndex + $batchSize - 1, $staleKids.Count - 1)
        $batchKids = $staleKids[$batchIndex..$endIndex]

        $clientRequestId = [Guid]::NewGuid().ToString()
        $deleteUri = "$bitLockerBaseUrl`?api-version=1.2&client-request-id=$clientRequestId"
        $body      = @{ kids = @($batchKids) } | ConvertTo-Json

        Write-Log "Batch $([Math]::Floor($batchIndex / $batchSize) + 1)/$batchCount - Deleting $($batchKids.Count) key(s)" -Tag "Run"
        Write-Log "DELETE URI: $deleteUri | Body: $body" -Tag "Debug"

        try {
            $null = Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $headers -Certificate $deviceCert -UseBasicParsing `
                -ContentType 'application/json' -Body $body -ErrorAction Stop
            $totalDeleted += $batchKids.Count
            Write-Log "Batch delete succeeded - removed $($batchKids.Count) key(s)" -Tag "Success"
        }
        catch {
            Write-Log "DELETE failed: $($_.Exception.Message) | Response: $($_.ErrorDetails.Message)" -Tag "Error"
            Write-Log "Continuing with next batch - partial success acceptable" -Tag "Debug"
        }

        if ($batchCount -gt 1 -and ($batchIndex + $batchSize) -lt $staleKids.Count) {
            Write-Log "Pausing 2 seconds before next batch to avoid throttling" -Tag "Debug"
            Start-Sleep -Seconds 2
        }
    }

    Write-Log "Cleanup complete. Removed $totalDeleted stale key(s)" -Tag "Success"
    Complete-Script -ExitCode 0

}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)" -Tag "Error"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Tag "Debug"
    Complete-Script -ExitCode 1
}
