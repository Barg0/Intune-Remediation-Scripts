#Requires -Version 5.1

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Register-PdfXChange"
$logFileName = "detection.log"

# ---------------------------[ Configuration ]---------------------------
# Update only this value when the license key changes.
$licenseKey = "<--PUT LICENSE KEY HERE-->"

$pdfXEditPath        = "$env:ProgramFiles\Tracker Software\PDF-XChange Editor\PDFXEdit.exe"
$xcVaultPath         = "$env:ProgramFiles\Tracker Software\Vault\XCVault.exe"
$vaultRegistryPath   = "HKCU:\SOFTWARE\Tracker Software\Vault\0000"
$vaultValueName      = "Value"
$licenseKeyMatchLength = 10

# Derived from $licenseKey - do not edit manually.
$licenseKeyPrefix = $licenseKey.Substring(0, [Math]::Min($licenseKeyMatchLength, $licenseKey.Length))

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
        }
    }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[ " -NoNewline -ForegroundColor White
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

# ---------------------------[ Detection Functions ]---------------------------
function Test-PdfXChangeEditorInstalled {
    Write-Log "Checking whether PDF-XChange Editor is installed" -Tag "Get"

    if (Test-Path -Path $pdfXEditPath) {
        Write-Log "PDF-XChange Editor executable found at $pdfXEditPath" -Tag "Success"
        return $true
    }

    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($uninstallRoot in $uninstallRoots) {
        $installedProduct = Get-ItemProperty -Path $uninstallRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "PDF-XChange Editor*" } |
            Select-Object -First 1

        if ($installedProduct) {
            Write-Log "PDF-XChange Editor found in Add/Remove Programs: $($installedProduct.DisplayName)" -Tag "Success"
            Write-Log "Uninstall registry key: $($installedProduct.PSPath)" -Tag "Debug"
            return $true
        }
    }

    Write-Log "PDF-XChange Editor is not installed on this device" -Tag "Error"
    return $false
}

function Test-XcVaultExecutable {
    Write-Log "Checking whether XCVault.exe is available at the expected path" -Tag "Get"

    if (Test-Path -Path $xcVaultPath) {
        Write-Log "XCVault.exe found at $xcVaultPath" -Tag "Success"
        return $true
    }

    Write-Log "XCVault.exe is missing at $xcVaultPath; license activation cannot run until PDF-XChange is installed" -Tag "Error"
    return $false
}

function Test-PdfXChangeLicenseKeyInRegistry {
    Write-Log "Checking whether the configured license key is stored in the current user vault registry (HKCU)" -Tag "Get"

    if (-not (Test-Path -Path $vaultRegistryPath)) {
        Write-Log "User vault registry path does not exist: $vaultRegistryPath" -Tag "Error"
        return $false
    }

    $vaultValue = Get-ItemProperty -Path $vaultRegistryPath -Name $vaultValueName -ErrorAction SilentlyContinue

    if ($vaultValue) {
        Write-Log "User vault registry value '$vaultValueName' is present under $vaultRegistryPath" -Tag "Success"
        return $true
    }

    Write-Log "User vault registry value '$vaultValueName' is missing under $vaultRegistryPath" -Tag "Error"
    return $false
}

function Get-XcVaultListKeysOutput {
    Write-Log "Querying installed PDF-XChange license keys for the current user via XCVault /ListKeys" -Tag "Get"

    try {
        $listKeysOutput = & $xcVaultPath /ListKeys 2>&1
        $exitCode       = $LASTEXITCODE

        Write-Log "XCVault /ListKeys exit code: $exitCode" -Tag "Debug"
        Write-Log "XCVault /ListKeys output:`n$listKeysOutput" -Tag "Debug"

        return [PSCustomObject]@{
            ExitCode = $exitCode
            Output   = ($listKeysOutput | Out-String).Trim()
        }
    }
    catch {
        Write-Log "Failed to execute XCVault /ListKeys: $($_.Exception.Message)" -Tag "Error"
        return $null
    }
}

function Get-PdfXChangeLicenseKeyLines {
    param(
        [string]$ListKeysOutput
    )

    return $ListKeysOutput -split "`r?`n" |
        Where-Object { $_ -match [regex]::Escape($licenseKeyPrefix) }
}

function Test-PdfXChangeLicenseKeyListed {
    param(
        [string]$ListKeysOutput
    )

    Write-Log "Checking whether the configured license key is listed by XCVault for the current user" -Tag "Get"

    if ([string]::IsNullOrWhiteSpace($ListKeysOutput)) {
        Write-Log "XCVault /ListKeys returned no output" -Tag "Error"
        return $false
    }

    $matchingLines = Get-PdfXChangeLicenseKeyLines -ListKeysOutput $ListKeysOutput

    if (-not $matchingLines) {
        Write-Log "Configured license key (prefix '$licenseKeyPrefix') was not found in XCVault /ListKeys output" -Tag "Error"
        return $false
    }

    $userScopedLine = $matchingLines | Where-Object { $_ -match '^\s*\d+\.\s+U\s+' } | Select-Object -First 1

    if ($userScopedLine) {
        Write-Log "Configured license key is present in the current user (HKCU) vault" -Tag "Success"
        Write-Log "Matching ListKeys line: $userScopedLine" -Tag "Debug"
        return $true
    }

    Write-Log "Configured license key prefix was found, but not in the current user (U) scope - per-user activation is required" -Tag "Error"
    Write-Log "Matching ListKeys line: $($matchingLines[0])" -Tag "Debug"
    return $false
}

function Test-PdfXChangeLicenseActivated {
    param(
        [string]$ListKeysOutput
    )

    Write-Log "Checking whether the configured license key is valid and activated for the current user" -Tag "Get"

    $matchingLines = Get-PdfXChangeLicenseKeyLines -ListKeysOutput $ListKeysOutput |
        Where-Object { $_ -match '^\s*\d+\.\s+U\s+' }

    foreach ($matchingLine in $matchingLines) {
        if ($matchingLine -match '^\s*\d+\.\s+U\s+([UMVAIX]+)\s+') {
            $keyState = $Matches[1]

            Write-Log "License key state flags for current user: $keyState" -Tag "Debug"

            $isValid     = $keyState.Contains('V')
            $isActivated = $keyState.Contains('A')
            $isExpired   = $keyState.Contains('X')
            $isInvalid   = $keyState.Contains('I')

            if ($isExpired) {
                Write-Log "Configured license key is expired according to XCVault" -Tag "Error"
                return $false
            }

            if ($isInvalid) {
                Write-Log "Configured license key is invalid or blocked according to XCVault" -Tag "Error"
                return $false
            }

            if ($isValid -and $isActivated) {
                Write-Log "Configured license key is valid and activated for the current user" -Tag "Success"
                return $true
            }

            if ($isValid -and -not $isActivated) {
                Write-Log "Configured license key is installed for the current user but not yet activated" -Tag "Error"
                return $false
            }
        }
    }

    Write-Log "Could not determine activation state for configured license key prefix '$licenseKeyPrefix'" -Tag "Error"
    return $false
}

function Test-PdfXChangeCompliance {
    $complianceChecks = [ordered]@{
        EditorInstalled        = (Test-PdfXChangeEditorInstalled)
        XcVaultAvailable       = (Test-XcVaultExecutable)
        LicenseKeyInRegistry   = $false
        LicenseKeyListed       = $false
        LicenseActivated       = $false
    }

    if (-not $complianceChecks.EditorInstalled -or -not $complianceChecks.XcVaultAvailable) {
        return $complianceChecks
    }

    $complianceChecks.LicenseKeyInRegistry = (Test-PdfXChangeLicenseKeyInRegistry)

    $listKeysResult = Get-XcVaultListKeysOutput

    if ($null -ne $listKeysResult) {
        $complianceChecks.LicenseKeyListed = (Test-PdfXChangeLicenseKeyListed -ListKeysOutput $listKeysResult.Output)
        $complianceChecks.LicenseActivated = (Test-PdfXChangeLicenseActivated -ListKeysOutput $listKeysResult.Output)
    }

    return $complianceChecks
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"
Write-Log "Evaluating per-user PDF-XChange license state for configured key prefix '$licenseKeyPrefix'" -Tag "Info"
Write-Log "Intune: run this script with logged-on user credentials" -Tag "Debug"

$complianceResult = Test-PdfXChangeCompliance
$failedChecks     = $complianceResult.GetEnumerator() | Where-Object { -not $_.Value }

if ($failedChecks.Count -eq 0) {
    Write-Log "User is compliant: PDF-XChange Editor and XCVault are present, and the configured license key is activated for $env:USERNAME" -Tag "Success"
    Complete-Script -ExitCode 0
}

foreach ($failedCheck in $failedChecks) {
    Write-Log "Compliance check failed: $($failedCheck.Key)" -Tag "Error"
}

Write-Log "User is not compliant; remediation is required" -Tag "Info"
Complete-Script -ExitCode 1
