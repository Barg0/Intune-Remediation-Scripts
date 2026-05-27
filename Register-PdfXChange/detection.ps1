#Requires -Version 5.1

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Register-PdfXChange"
$logFileName = "detection.log"

# ---------------------------[ Configuration ]---------------------------
# Paste your license key between the two marker lines below.
# The key can be pasted across multiple lines - all whitespace is stripped automatically.
# The closing '@ MUST start at column 0 (no leading spaces or tabs).
$licenseKey = "<--PUT LICENSE KEY HERE-->"

$pdfXEditPath          = "$env:ProgramFiles\Tracker Software\PDF-XChange Editor\PDFXEdit.exe"
$xcVaultPath           = "$env:ProgramFiles\Tracker Software\Vault\XCVault.exe"
$vaultRegistryPath     = "HKCU:\SOFTWARE\Tracker Software\Vault\0000"
$vaultValueName        = "Value"
$licenseKeyMatchLength = 10

# Derived from $licenseKey - do not edit manually.
$licenseKeyPrefix = $licenseKey.Substring(0, [Math]::Min($licenseKeyMatchLength, $licenseKey.Length))

# ---------------------------[ Logging Setup ]---------------------------
$log           = $true
$logDebug      = $false
$logGet        = $true
$logRun        = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$($env:USERNAME)\$scriptName"
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

# ---------------------------[ Detection Functions ]---------------------------
function Test-LicenseKeyFormat {
    Write-Log "Validating the configured license key format" -Tag "Get"

    if ([string]::IsNullOrWhiteSpace($licenseKey)) {
        Write-Log "License key is empty - set licenseKey at the top of the script" -Tag "Error"
        return $false
    }

    if ($licenseKey -eq "<--PUT LICENSE KEY HERE-->") {
        Write-Log "License key is still the placeholder - replace it with your actual key from the Tracker portal" -Tag "Error"
        return $false
    }

    if ($licenseKey -match '[\r\n\t\s]') {
        Write-Log "License key contains whitespace or line breaks - it must be a single unbroken string" -Tag "Error"
        return $false
    }

    Write-Log "License key format is valid (prefix: $licenseKeyPrefix, length: $($licenseKey.Length) characters)" -Tag "Success"
    return $true
}

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
            return $true
        }
    }

    Write-Log "PDF-XChange Editor is not installed on this device" -Tag "Error"
    return $false
}

function Test-XcVaultExecutable {
    Write-Log "Checking whether XCVault.exe is present" -Tag "Get"

    if (Test-Path -Path $xcVaultPath) {
        Write-Log "XCVault.exe found at $xcVaultPath" -Tag "Success"
        return $true
    }

    Write-Log "XCVault.exe is missing at $xcVaultPath - license cannot be managed until PDF-XChange is installed" -Tag "Error"
    return $false
}

function Test-PdfXChangeLicenseKeyInRegistry {
    # XCVault writes an encrypted binary entry to HKCU when /AddKeyData succeeds
    # and updates it when /ActivateKeys succeeds. This registry value is the reliable
    # ground truth for whether the key has been installed for this user.
    # Note: the value is encrypted binary - the specific key cannot be decoded from it.
    Write-Log "Checking whether a license key entry exists in the current user vault (HKCU)" -Tag "Get"

    if (-not (Test-Path -Path $vaultRegistryPath)) {
        Write-Log "User vault registry path does not exist: $vaultRegistryPath" -Tag "Error"
        return $false
    }

    $vaultValue = Get-ItemProperty -Path $vaultRegistryPath -Name $vaultValueName -ErrorAction SilentlyContinue

    if ($vaultValue) {
        Write-Log "License key entry is present in the user vault at $vaultRegistryPath" -Tag "Success"
        return $true
    }

    Write-Log "License key entry is missing from the user vault at $vaultRegistryPath" -Tag "Error"
    return $false
}

function Test-PdfXChangeCompliance {
    $complianceChecks = [ordered]@{
        LicenseKeyFormat   = (Test-LicenseKeyFormat)
        EditorInstalled    = $false
        XcVaultAvailable   = $false
        LicenseInRegistry  = $false
    }

    if (-not $complianceChecks.LicenseKeyFormat) {
        return $complianceChecks
    }

    $complianceChecks.EditorInstalled  = (Test-PdfXChangeEditorInstalled)
    $complianceChecks.XcVaultAvailable = (Test-XcVaultExecutable)

    if (-not $complianceChecks.EditorInstalled -or -not $complianceChecks.XcVaultAvailable) {
        return $complianceChecks
    }

    $complianceChecks.LicenseInRegistry = (Test-PdfXChangeLicenseKeyInRegistry)

    return $complianceChecks
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"
Write-Log "Evaluating per-user PDF-XChange license state for key prefix '$licenseKeyPrefix'" -Tag "Info"

$complianceResult = Test-PdfXChangeCompliance
$failedChecks     = $complianceResult.GetEnumerator() | Where-Object { -not $_.Value }

if ($failedChecks.Count -eq 0) {
    Write-Log "Compliant: PDF-XChange Editor is installed with a license key registered for $env:USERNAME" -Tag "Success"
    Complete-Script -ExitCode 0
}

foreach ($failedCheck in $failedChecks) {
    Write-Log "Compliance check failed: $($failedCheck.Key)" -Tag "Error"
}

Write-Log "Not compliant - remediation is required" -Tag "Info"
Complete-Script -ExitCode 1
