# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Reset-IntuneWin32AppState"
$logFileName = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path -Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

# ---------------------------[ Constants ]---------------------------
$script:win32AppsKeyPath              = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
$script:intuneManagementExtensionServiceName = 'IntuneManagementExtension'
$script:systemObjectId                = '00000000-0000-0000-0000-000000000000'
$script:officeIdentityMajorVersion    = '16.0'
$script:exitCodeSuccess               = 0
$script:exitCodeFailure               = 1
$script:win32EnforcementSuccess       = 0
$script:win32EnforcementPendingReboot = 3010
$script:enforcementStateFailures      = @(5000, 5003, 5006, 5999)
$script:contentIncomingPath           = "${env:ProgramFiles(x86)}\Microsoft Intune Management Extension\Content\Incoming"
$script:imeCachePath                  = "$env:SystemRoot\IMECache"

# ---------------------------[ Logging Function ]---------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [string] $Message,
        [string] $Tag = "Info"
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
    param ([int] $exitCode)

    $scriptEndTime = Get-Date
    $duration      = $scriptEndTime - $scriptStartTime

    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $exitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"

    exit $exitCode
}

# ---------------------------[ Support functions ]---------------------------
function Get-FailedWin32AppStates {
    if (-not (Test-Path -LiteralPath $script:win32AppsKeyPath)) {
        Write-Log "Win32Apps registry path not found: $($script:win32AppsKeyPath)" -Tag "Debug"
        return @()
    }

    $appSubKeys = Get-ChildItem -LiteralPath $script:win32AppsKeyPath -Recurse -ErrorAction SilentlyContinue
    $failedStates = [System.Collections.Generic.List[object]]::new()

    foreach ($subKey in $appSubKeys) {
        $enforcementStateMessage = Get-ItemProperty -LiteralPath $subKey.PSPath -Name EnforcementStateMessage -ErrorAction SilentlyContinue
        if (-not $enforcementStateMessage) {
            continue
        }

        $messageText = $enforcementStateMessage.EnforcementStateMessage

        $parsedErrorCode = $null
        if ($messageText -match '"ErrorCode"\s*:\s*(-?\d+|null)') {
            $token = $Matches[1]
            if ($token -ne 'null') {
                $parsedErrorCode = [int]$token
            }
        }

        $parsedEnforcementState = $null
        if ($messageText -match '"EnforcementState"\s*:\s*(\d+)') {
            $parsedEnforcementState = [int]$Matches[1]
        }

        $hasErrorCode = ($null -ne $parsedErrorCode) -and
                        ($parsedErrorCode -ne $script:win32EnforcementSuccess) -and
                        ($parsedErrorCode -ne $script:win32EnforcementPendingReboot)

        $hasFailedState = ($null -ne $parsedEnforcementState) -and
                          ($script:enforcementStateFailures -contains $parsedEnforcementState)

        if ($hasErrorCode -or $hasFailedState) {
            $failedStates.Add([PSCustomObject]@{
                subKeyPath       = $subKey.PSPath
                errorCode        = if ($null -ne $parsedErrorCode) { $parsedErrorCode } else { 0 }
                enforcementState = if ($null -ne $parsedEnforcementState) { $parsedEnforcementState } else { 0 }
            }) | Out-Null
        }
    }

    return $failedStates
}

function Get-Win32AppUserAndAppIdFromSubKeyPath {
    param (
        [Parameter(Mandatory = $true)]
        [string] $subKeyPath
    )

    $normalized = $subKeyPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $parts = $normalized -split '\\' | Where-Object { $_ -ne '' }
    $win32Index = (0..($parts.Length - 1) | Where-Object { $parts[$_] -eq 'Win32Apps' } | Select-Object -First 1)

    if ($null -eq $win32Index -or $win32Index -lt 0) {
        return $null
    }

    $next = $win32Index + 1
    if ($next -ge $parts.Length) {
        return $null
    }

    if ($parts[$next] -eq 'Reporting') {
        if ($next + 2 -ge $parts.Length) {
            return $null
        }

        return [PSCustomObject]@{
            userObjectId = $parts[$next + 1]
            appId        = $parts[$next + 2]
        }
    }

    if ($parts[$next] -eq 'GRS') {
        return $null
    }

    if ($next + 1 -ge $parts.Length) {
        return $null
    }

    $userObjectId = $parts[$next]
    $appId        = $parts[$next + 1]
    if ($appId -eq 'GRS') {
        return $null
    }

    return [PSCustomObject]@{
        userObjectId = $userObjectId
        appId        = $appId
    }
}

function Get-LastHashValue {
    param (
        [Parameter(Mandatory = $true)]
        [string] $userObjectId,

        [Parameter(Mandatory = $true)]
        [string] $appId
    )

    $reportingKeyPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\Reporting\$userObjectId\$appId\ReportCache\$userObjectId"
    if (-not (Test-Path -LiteralPath $reportingKeyPath)) {
        return $null
    }

    $reportingKey = Get-ItemProperty -LiteralPath $reportingKeyPath -Name LastHashValue -ErrorAction SilentlyContinue
    return $reportingKey.LastHashValue
}

function Find-GRSEntryForApp {
    param (
        [Parameter(Mandatory = $true)]
        [string] $userObjectId,

        [Parameter(Mandatory = $true)]
        [string] $appId
    )

    $baseAppId = $appId -replace '_\d+$', ''
    $grsBasePath = "$($script:win32AppsKeyPath)\$userObjectId\GRS"

    if (-not (Test-Path -LiteralPath $grsBasePath)) {
        Write-Log "GRS path does not exist for user $userObjectId; nothing to match." -Tag "Debug"
        return $null
    }

    $grsEntries = Get-ChildItem -LiteralPath $grsBasePath -ErrorAction SilentlyContinue
    if (-not $grsEntries) {
        return $null
    }

    foreach ($entry in $grsEntries) {
        $props = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        $customPropNames = $props.PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' }
        $matchingProp    = $customPropNames | Where-Object { $_ -like "*$baseAppId*" }

        if ($matchingProp) {
            return [PSCustomObject]@{
                path = $entry.PSPath
                hash = $entry.PSChildName
            }
        }
    }

    return $null
}

function Remove-ContentCacheForHash {
    param (
        [Parameter(Mandatory = $true)]
        [string] $contentHash
    )

    $binPath   = Join-Path -Path $script:contentIncomingPath -ChildPath "$contentHash.bin"
    $cachePath = Join-Path -Path $script:imeCachePath -ChildPath $contentHash

    if (Test-Path -LiteralPath $binPath) {
        try {
            Remove-Item -LiteralPath $binPath -Force -ErrorAction Stop
            Write-Log "Removed cached content package: $binPath" -Tag "Success"
        }
        catch {
            Write-Log "Failed to remove cached package '$binPath': $($_.Exception.Message)" -Tag "Error"
        }
    }

    if (Test-Path -LiteralPath $cachePath) {
        try {
            Remove-Item -LiteralPath $cachePath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed extracted content cache: $cachePath" -Tag "Success"
        }
        catch {
            Write-Log "Failed to remove cache folder '$cachePath': $($_.Exception.Message)" -Tag "Error"
        }
    }
}

function Remove-FailedAppRegistryKeys {
    param (
        [Parameter(Mandatory = $true)]
        [string] $userObjectId,

        [Parameter(Mandatory = $true)]
        [string] $appId
    )

    $pathsToRemove = @(
        "$($script:win32AppsKeyPath)\$userObjectId\$appId",
        "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\Reporting\$userObjectId\$appId"
    )

    foreach ($path in $pathsToRemove) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Log "Registry key not found (skipped): $path" -Tag "Debug"
            continue
        }

        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed registry key: $path" -Tag "Success"
        }
        catch {
            Write-Log "Failed to remove registry key '$path': $($_.Exception.Message)" -Tag "Error"
            throw
        }
    }
}

function Get-UserNameFromObjectId {
    param (
        [Parameter(Mandatory = $true)]
        [string] $objectId
    )

    if ($objectId -eq $script:systemObjectId) {
        return 'SYSTEM'
    }

    $userSids = Get-ChildItem -Path 'Registry::HKEY_USERS\' -ErrorAction SilentlyContinue

    foreach ($userSid in $userSids) {
        $identityKeyPath = "Registry::HKEY_USERS\$($userSid.PSChildName)\Software\Microsoft\Office\$($script:officeIdentityMajorVersion)\Common\Identity"
        if (-not (Test-Path -LiteralPath $identityKeyPath)) {
            continue
        }

        $identityKey = Get-ItemProperty -LiteralPath $identityKeyPath -ErrorAction SilentlyContinue
        if ($identityKey.ConnectedAccountWamAad -eq $objectId) {
            return $identityKey.ADUserName
        }
    }

    return $null
}

function Get-ErrorDescription {
    param (
        [Parameter(Mandatory = $true)]
        [int] $msiErrorCode
    )

    $errorCodes = @{
        [uint32]0x00000000 = "The action completed successfully."
        [uint32]0x0000000D = "The data is invalid."
        [uint32]0x00000057 = "One of the parameters was invalid."
        [uint32]0x00000078 = "This value is returned when a custom action attempts to call a function that can't be called from custom actions. The function returns the value ERROR_CALL_NOT_IMPLEMENTED."
        [uint32]0x000004EB = "If Windows Installer determines a product might be incompatible with the current operating system, it displays a dialog box informing the user and asking whether to try to install anyway. This error code is returned if the user chooses not to try the installation."
        [uint32]0x80070641 = "The Windows Installer service couldn't be accessed. Contact your support personnel to verify that the Windows Installer service is properly registered."
        [uint32]0x80070642 = "The user canceled installation."
        [uint32]0x80070643 = "A fatal error occurred during installation."
        [uint32]0x80070644 = "Installation suspended, incomplete."
        [uint32]0x80070645 = "This action is only valid for products that are currently installed."
        [uint32]0x80070646 = "The feature identifier isn't registered."
        [uint32]0x80070647 = "The component identifier isn't registered."
        [uint32]0x80070648 = "This is an unknown property."
        [uint32]0x80070649 = "The handle is in an invalid state."
        [uint32]0x8007064A = "The configuration data for this product is corrupt. Contact your support personnel."
        [uint32]0x8007064B = "The component qualifier not present."
        [uint32]0x8007064C = "The installation source for this product isn't available. Verify that the source exists and that you can access it."
        [uint32]0x8007064D = "This installation package can't be installed by the Windows Installer service. You must install a Windows service pack that contains a newer version of the Windows Installer service."
        [uint32]0x8007064E = "The product is uninstalled."
        [uint32]0x8007064F = "The SQL query syntax is invalid or unsupported."
        [uint32]0x80070650 = "The record field does not exist."
        [uint32]0x80070652 = "Another installation is already in progress. Complete that installation before proceeding with this install. For information about the mutex, see _MSIExecute Mutex."
        [uint32]0x80070653 = "This installation package couldn't be opened. Verify that the package exists and is accessible, or contact the application vendor to verify that this is a valid Windows Installer package."
        [uint32]0x80070654 = "This installation package couldn't be opened. Contact the application vendor to verify that this is a valid Windows Installer package."
        [uint32]0x80070655 = "There was an error starting the Windows Installer service user interface. Contact your support personnel."
        [uint32]0x80070656 = "There was an error opening installation log file. Verify that the specified log file location exists and is writable."
        [uint32]0x80070657 = "This language of this installation package isn't supported by your system."
        [uint32]0x80070658 = "There was an error applying transforms. Verify that the specified transform paths are valid."
        [uint32]0x80070659 = "This installation is forbidden by system policy. Contact your system administrator."
        [uint32]0x8007065A = "The function couldn't be executed."
        [uint32]0x8007065B = "The function failed during execution."
        [uint32]0x8007065C = "An invalid or unknown table was specified."
        [uint32]0x8007065D = "The data supplied is the wrong type."
        [uint32]0x8007065E = "Data of this type isn't supported."
        [uint32]0x8007065F = "The Windows Installer service failed to start. Contact your support personnel."
        [uint32]0x80070660 = "The Temp folder is either full or inaccessible. Verify that the Temp folder exists and that you can write to it."
        [uint32]0x80070661 = "This installation package isn't supported on this platform. Contact your application vendor."
        [uint32]0x80070662 = "Component isn't used on this machine."
        [uint32]0x80070663 = "This patch package couldn't be opened. Verify that the patch package exists and is accessible, or contact the application vendor to verify that this is a valid Windows Installer patch package."
        [uint32]0x80070664 = "This patch package couldn't be opened. Contact the application vendor to verify that this is a valid Windows Installer patch package."
        [uint32]0x80070665 = "This patch package can't be processed by the Windows Installer service. You must install a Windows service pack that contains a newer version of the Windows Installer service."
        [uint32]0x80070666 = "Another version of this product is already installed. Installation of this version can't continue. To configure or remove the existing version of this product, use Add/Remove Programs in Control Panel."
        [uint32]0x80070667 = "Invalid command line argument. Consult the Windows Installer SDK for detailed command-line help."
        [uint32]0x80070668 = "The current user isn't permitted to perform installations from a client session of a server running the Terminal Server role service."
        [uint32]0x80070669 = "The installer has initiated a restart. This message indicates success."
        [uint32]0x8007066A = "The installer can't install the upgrade patch because the program being upgraded may be missing or the upgrade patch updates a different version of the program. Verify that the program to be upgraded exists on your computer and that you have the correct upgrade patch."
        [uint32]0x8007066B = "The patch package isn't permitted by system policy."
        [uint32]0x8007066C = "One or more customizations aren't permitted by system policy."
        [uint32]0x8007066D = "Windows Installer doesn't permit installation from a Remote Desktop Connection."
        [uint32]0x8007066E = "The patch package isn't a removable patch package."
        [uint32]0x8007066F = "The patch isn't applied to this product."
        [uint32]0x80070670 = "No valid sequence could be found for the set of patches."
        [uint32]0x80070671 = "Patch removal was disallowed by policy."
        [uint32]0x80070672 = "The XML patch data is invalid."
        [uint32]0x80070673 = "Administrative user failed to apply patch for a per-user managed or a per-machine application that's in advertised state."
        [uint32]0x80070674 = "Windows Installer isn't accessible when the computer is in Safe Mode. Exit Safe Mode and try again or try using system restore to return your computer to a previous state. Available beginning with Windows Installer version 4.0."
        [uint32]0x80070675 = "Couldn't perform a multiple-package transaction because rollback has been disabled. Multiple-package installations can't run if rollback is disabled. Available beginning with Windows Installer version 4.5."
        [uint32]0x80070676 = "The app that you're trying to run isn't supported on this version of Windows. A Windows Installer package, patch, or transform that has not been signed by Microsoft can't be installed on an ARM computer."
        [uint32]0x80070BB8 = "A restart is required to complete the install. This message indicates success. This does not include installs where the ForceReboot action is run."
    }

    $lookup = [uint32]$msiErrorCode
    if ($errorCodes.ContainsKey($lookup)) {
        return $errorCodes[$lookup]
    }

    return "Unknown error code."
}

function Restart-IntuneManagementExtensionService {
    try {
        Write-Log "Restarting service '$script:intuneManagementExtensionServiceName' after registry cleanup." -Tag "Run"
        Restart-Service -Name $script:intuneManagementExtensionServiceName -Force -ErrorAction Stop
        Write-Log "Service '$script:intuneManagementExtensionServiceName' restarted." -Tag "Success"
    }
    catch {
        Write-Log "Failed to restart service '$script:intuneManagementExtensionServiceName': $($_.Exception.Message)" -Tag "Error"
        throw
    }
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

$failedStates = @(Get-FailedWin32AppStates)
$failureCount = $failedStates.Count

if ($failureCount -eq 0) {
    Write-Log "No failures detected; nothing to remediate." -Tag "Success"
    Complete-Script -exitCode $script:exitCodeSuccess
}

Write-Log "Detected $failureCount failed Win32 app registry state(s); resolving user scope and AppId for cleanup." -Tag "Get"

$uniqueTargets = @{}
foreach ($state in $failedStates) {
    $scope = Get-Win32AppUserAndAppIdFromSubKeyPath -subKeyPath $state.subKeyPath
    if (-not $scope) {
        Write-Log "Could not parse user/AppId from path: $($state.subKeyPath)" -Tag "Debug"
        continue
    }

    $dedupeKey = "$($scope.userObjectId)|$($scope.appId)"
    if (-not $uniqueTargets.ContainsKey($dedupeKey)) {
        $uniqueTargets[$dedupeKey] = [PSCustomObject]@{
            userObjectId     = $scope.userObjectId
            appId            = $scope.appId
            errorCode        = $state.errorCode
            enforcementState = $state.enforcementState
        }
    }
}

if ($uniqueTargets.Count -eq 0) {
    Write-Log "Failures were found but no registry paths could be mapped to user/AppId; no keys removed." -Tag "Error"
    Complete-Script -exitCode $script:exitCodeFailure
}

$remediationError = $false

foreach ($target in $uniqueTargets.Values) {
    $userName = Get-UserNameFromObjectId -objectId $target.userObjectId
    $displayUser = if ($userName) { $userName } else { $target.userObjectId }
    $errorDescription = Get-ErrorDescription -msiErrorCode $target.errorCode

    Write-Log "AppId $($target.appId) failed for $displayUser — ErrorCode $($target.errorCode) ($errorDescription), EnforcementState $($target.enforcementState)" -Tag "Info"

    try {
        Remove-FailedAppRegistryKeys -userObjectId $target.userObjectId -appId $target.appId
    }
    catch {
        $remediationError = $true
        continue
    }

    $contentHash = $null
    $grsEntry = Find-GRSEntryForApp -userObjectId $target.userObjectId -appId $target.appId
    if ($grsEntry) {
        $contentHash = $grsEntry.hash
        try {
            Remove-Item -LiteralPath $grsEntry.path -Recurse -Force -ErrorAction Stop
            Write-Log "Removed GRS entry '$($grsEntry.hash)' matched to AppId $($target.appId)" -Tag "Success"
        }
        catch {
            Write-Log "Failed to remove GRS entry '$($grsEntry.path)': $($_.Exception.Message)" -Tag "Error"
            $remediationError = $true
        }
    }
    else {
        Write-Log "No GRS entry found via property match for AppId $($target.appId); trying LastHashValue fallback." -Tag "Debug"
        $contentHash = Get-LastHashValue -userObjectId $target.userObjectId -appId $target.appId
        if ($contentHash) {
            $grsHashPath = "$($script:win32AppsKeyPath)\$($target.userObjectId)\GRS\$contentHash"
            if (Test-Path -LiteralPath $grsHashPath) {
                try {
                    Remove-Item -LiteralPath $grsHashPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed GRS entry via LastHashValue fallback: $contentHash" -Tag "Success"
                }
                catch {
                    Write-Log "Failed to remove GRS entry '$grsHashPath': $($_.Exception.Message)" -Tag "Error"
                    $remediationError = $true
                }
            }
        }
        else {
            Write-Log "No GRS hash could be determined for AppId $($target.appId); GRS entry may persist." -Tag "Debug"
        }
    }

    if ($contentHash) {
        Remove-ContentCacheForHash -contentHash $contentHash
    }
}

if ($remediationError) {
    Write-Log "One or more cleanup operations failed; not restarting IME." -Tag "Error"
    Complete-Script -exitCode $script:exitCodeFailure
}

try {
    Restart-IntuneManagementExtensionService
}
catch {
    Complete-Script -exitCode $script:exitCodeFailure
}

Write-Log "Remediation finished for $($uniqueTargets.Count) app scope(s). Allow time for IME sync and retry." -Tag "Success"
Complete-Script -exitCode $script:exitCodeSuccess
