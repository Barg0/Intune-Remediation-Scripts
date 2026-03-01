# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$scriptName = "Deploy - Shared Printers"
$logFileName = "deploy.log"

# ---------------------------[ Intune Remediation Config ]---------------------------

# Display name prefix -- each remediation will be named: "{prefix} - {ScriptName}"
$intuneNamePrefix = "🖨️ Printer"

# Publisher / author shown in Intune
$intunePublisher = "Barg0"

# ---------------------------[ Schedule Config ]---------------------------

# "Hourly" or "Daily"
$scheduleType     = "Hourly"

# Interval: every X hours (1-23) for Hourly, every X days (1-23) for Daily
$scheduleInterval = 1

# Only used when $scheduleType = "Daily"
$scheduleDailyTime = "08:00"
$scheduleUseUtc    = $false

# ---------------------------[ Device Filter Config ]---------------------------

# Leave $deviceFilterId empty to skip device filter
$deviceFilterId   = "19d6856c-7fc9-41fb-aa6b-aff4427d3113"
$deviceFilterType = "include"    # "include" or "exclude"

# ---------------------------[ Paths ]---------------------------
$csvPath    = "$PSScriptRoot\printers.csv"
$scriptsDir = "$PSScriptRoot\printers"

# ---------------------------[ Logging Setup ]---------------------------
$log = $true
$enableLogFile = $true

$logFileDirectory = "$PSScriptRoot\log"
$logFile = "$logFileDirectory\$logFileName"

if (-not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

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
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $ExitCode
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

# ---------------------------[ Validate Inputs ]---------------------------
if (-not (Test-Path $csvPath)) {
    Write-Log "CSV file not found: $csvPath" -Tag "Error"
    Complete-Script -ExitCode 1
}

if (-not (Test-Path $scriptsDir)) {
    Write-Log "printers/ directory not found. Run package.ps1 first." -Tag "Error"
    Complete-Script -ExitCode 1
}

# ---------------------------[ Check Module ]---------------------------
Write-Log "Checking for Microsoft.Graph.Authentication module..." -Tag "Get"

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Log "Microsoft.Graph.Authentication module is not installed." -Tag "Error"
    Write-Log "Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser" -Tag "Info"
    Complete-Script -ExitCode 1
}

Write-Log "Microsoft.Graph.Authentication module found." -Tag "Success"

# ---------------------------[ Connect to Graph ]---------------------------
Write-Log "Connecting to Microsoft Graph (interactive login)..." -Tag "Run"

try {
    Connect-MgGraph -Scopes "DeviceManagementScripts.ReadWrite.All", "Group.Read.All" -NoWelcome
    $context = Get-MgContext
    Write-Log "Connected as: $($context.Account) | Tenant: $($context.TenantId)" -Tag "Success"
}
catch {
    Write-Log "Failed to connect to Microsoft Graph: $_" -Tag "Error"
    Complete-Script -ExitCode 1
}

$graphBaseUrl = "https://graph.microsoft.com/beta"

# ---------------------------[ Read CSV ]---------------------------
$printerEntries = Import-Csv -Path $csvPath

if ($printerEntries.Count -eq 0) {
    Write-Log "CSV file is empty or has no valid rows." -Tag "Error"
    Complete-Script -ExitCode 1
}

Write-Log "Found $($printerEntries.Count) printer group(s) in CSV." -Tag "Info"

# ---------------------------[ Build Schedule Object ]---------------------------
$runSchedule = switch ($scheduleType) {
    "Hourly" {
        @{
            "@odata.type" = "#microsoft.graph.deviceHealthScriptHourlySchedule"
            interval      = $scheduleInterval
        }
    }
    "Daily" {
        @{
            "@odata.type" = "#microsoft.graph.deviceHealthScriptDailySchedule"
            interval      = $scheduleInterval
            time          = $scheduleDailyTime
            useUtc        = $scheduleUseUtc
        }
    }
    default {
        Write-Log "Invalid scheduleType '$scheduleType'. Use 'Hourly' or 'Daily'." -Tag "Error"
        Complete-Script -ExitCode 1
    }
}

Write-Log "Schedule: $scheduleType every $scheduleInterval interval(s)" -Tag "Info"

# ---------------------------[ Deploy Each Printer Group ]---------------------------
$deployed = 0
$failed   = 0

foreach ($entry in $printerEntries) {
    $scriptEntryName = $entry.ScriptName.Trim()
    $printServer     = $entry.PrintServer.Trim()
    $printerNames    = $entry.Printers.Trim()
    $entraGroup      = $entry.EntraGroup.Trim()

    if ([string]::IsNullOrWhiteSpace($scriptEntryName) -or
        [string]::IsNullOrWhiteSpace($entraGroup)) {
        Write-Log "Skipping incomplete row: ScriptName='$scriptEntryName' EntraGroup='$entraGroup'" -Tag "Error"
        $failed++
        continue
    }

    $intuneName = "$intuneNamePrefix - $scriptEntryName"

    $printerList = ($printerNames -split ";" | ForEach-Object { "- $($_.Trim())" }) -join "`n"
    $intuneDescription = "Detects and installs the following shared printers:`n$printerList`n`nPrint server: $printServer"

    Write-Log "--- Processing printer group $scriptEntryName -> Entra Group '$entraGroup' ---" -Tag "Run"

    # ---------------------------[ Read Packaged Scripts ]---------------------------
    $detectionPath   = "$scriptsDir\$scriptEntryName\detection.ps1"
    $remediationPath = "$scriptsDir\$scriptEntryName\remediation.ps1"

    if (-not (Test-Path $detectionPath) -or -not (Test-Path $remediationPath)) {
        Write-Log "Scripts not found in $scriptsDir\$scriptEntryName\. Run package.ps1 first." -Tag "Error"
        $failed++
        continue
    }

    $detectionContent   = Get-Content -Path $detectionPath -Raw
    $remediationContent = Get-Content -Path $remediationPath -Raw

    $detectionBase64   = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($detectionContent))
    $remediationBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remediationContent))

    Write-Log "Scripts loaded and encoded for $scriptEntryName`." -Tag "Get"

    # ---------------------------[ Check for Existing Remediation ]---------------------------
    $filterName = [System.Web.HttpUtility]::UrlEncode($intuneName)
    $searchUrl  = "$graphBaseUrl/deviceManagement/deviceHealthScripts?`$filter=displayName eq '$intuneName'"

    try {
        $existing = Invoke-MgGraphRequest -Uri $searchUrl -Method GET
    }
    catch {
        Write-Log "Failed to query existing remediations: $_" -Tag "Error"
        $failed++
        continue
    }

    $healthScriptId = $null

    if ($existing.value.Count -gt 0) {
        $healthScriptId = $existing.value[0].id
        Write-Log "Found existing remediation '$intuneName' (ID: $healthScriptId). Updating..." -Tag "Info"

        $updateBody = @{
            displayName              = $intuneName
            description              = $intuneDescription
            publisher                = $intunePublisher
            detectionScriptContent   = $detectionBase64
            remediationScriptContent = $remediationBase64
            runAsAccount             = "user"
            runAs32Bit               = $false
            enforceSignatureCheck    = $false
        }

        try {
            Invoke-MgGraphRequest -Uri "$graphBaseUrl/deviceManagement/deviceHealthScripts/$healthScriptId" -Method PATCH -Body ($updateBody | ConvertTo-Json -Depth 10) -ContentType "application/json" | Out-Null
            Write-Log "Updated remediation '$intuneName' successfully." -Tag "Success"
        }
        catch {
            Write-Log "Failed to update remediation '$intuneName': $_" -Tag "Error"
            $failed++
            continue
        }
    }
    else {
        Write-Log "Creating new remediation '$intuneName'..." -Tag "Run"

        $createBody = @{
            displayName              = $intuneName
            description              = $intuneDescription
            publisher                = $intunePublisher
            detectionScriptContent   = $detectionBase64
            remediationScriptContent = $remediationBase64
            runAsAccount             = "user"
            runAs32Bit               = $false
            enforceSignatureCheck    = $false
            roleScopeTagIds          = @("0")
        }

        try {
            $result = Invoke-MgGraphRequest -Uri "$graphBaseUrl/deviceManagement/deviceHealthScripts" -Method POST -Body ($createBody | ConvertTo-Json -Depth 10) -ContentType "application/json"
            $healthScriptId = $result.id
            Write-Log "Created remediation '$intuneName' (ID: $healthScriptId)." -Tag "Success"
        }
        catch {
            Write-Log "Failed to create remediation '$intuneName': $_" -Tag "Error"
            $failed++
            continue
        }
    }

    # ---------------------------[ Resolve Entra Group ]---------------------------
    Write-Log "Resolving Entra group '$entraGroup'..." -Tag "Get"

    try {
        $groupSearchUrl = "$graphBaseUrl/groups?`$filter=displayName eq '$entraGroup'&`$select=id,displayName"
        $groupResult = Invoke-MgGraphRequest -Uri $groupSearchUrl -Method GET
    }
    catch {
        Write-Log "Failed to query Entra group '$entraGroup': $_" -Tag "Error"
        $failed++
        continue
    }

    if ($groupResult.value.Count -eq 0) {
        Write-Log "Entra group '$entraGroup' not found. Skipping assignment." -Tag "Error"
        $failed++
        continue
    }

    $groupId = $groupResult.value[0].id
    Write-Log "Resolved '$entraGroup' -> $groupId" -Tag "Success"

    # ---------------------------[ Build Assignment Target ]---------------------------
    $assignmentTarget = @{
        "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
        groupId       = $groupId
    }

    if (-not [string]::IsNullOrWhiteSpace($deviceFilterId)) {
        $assignmentTarget["deviceAndAppManagementAssignmentFilterId"]   = $deviceFilterId
        $assignmentTarget["deviceAndAppManagementAssignmentFilterType"] = $deviceFilterType
        Write-Log "Device filter applied: $deviceFilterType ($deviceFilterId)" -Tag "Info"
    }

    # ---------------------------[ Assign to Group ]---------------------------
    Write-Log "Assigning '$intuneName' to group '$entraGroup'..." -Tag "Run"

    $assignBody = @{
        deviceHealthScriptAssignments = @(
            @{
                target               = $assignmentTarget
                runRemediationScript = $true
                runSchedule          = $runSchedule
            }
        )
    }

    try {
        Invoke-MgGraphRequest -Uri "$graphBaseUrl/deviceManagement/deviceHealthScripts/$healthScriptId/assign" -Method POST -Body ($assignBody | ConvertTo-Json -Depth 10) -ContentType "application/json" | Out-Null
        Write-Log "Assigned '$intuneName' to '$entraGroup' successfully." -Tag "Success"
    }
    catch {
        Write-Log "Failed to assign '$intuneName' to '$entraGroup': $_" -Tag "Error"
        $failed++
        continue
    }

    $deployed++
}

# ---------------------------[ Summary ]---------------------------
Write-Log "Deployed: $deployed | Failed: $failed | Total: $($printerEntries.Count)" -Tag "Info"

if ($failed -eq 0) {
    Write-Log "All printer remediations deployed successfully." -Tag "Success"
    Complete-Script -ExitCode 0
} else {
    Write-Log "Some printer remediations failed. Check the log above for details." -Tag "Error"
    Complete-Script -ExitCode 1
}
