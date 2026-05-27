#Requires -Version 5.1

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script Name ]---------------------------
$scriptName  = "Register-PdfXChange"
$logFileName = "remediation.log"

# ---------------------------[ Configuration ]---------------------------
# Update only this value when the license key changes.
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

# ---------------------------[ Remediation Functions ]---------------------------
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
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    if (Test-Path -Path $pdfXEditPath) { return $true }

    foreach ($uninstallRoot in $uninstallRoots) {
        $installedProduct = Get-ItemProperty -Path $uninstallRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "PDF-XChange Editor*" } |
            Select-Object -First 1

        if ($installedProduct) { return $true }
    }

    return $false
}

function Test-XcVaultExecutable {
    return Test-Path -Path $xcVaultPath
}

function Invoke-XcVaultCommand {
    param(
        [string[]]$ArgumentList,
        [string]$ActionDescription
    )

    Write-Log $ActionDescription -Tag "Run"
    Write-Log "Executing: $xcVaultPath $($ArgumentList -join ' ')" -Tag "Debug"

    try {
        # /S suppresses any dialogs or info messages from XCVault.
        # Exit code 0 = success, exit code 1 = failure.
        & $xcVaultPath @ArgumentList 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE

        Write-Log "XCVault exit code: $exitCode" -Tag "Debug"

        if ($exitCode -ne 0) {
            Write-Log "XCVault failed (exit code $exitCode) during: $ActionDescription" -Tag "Error"
            return $false
        }

        Write-Log "XCVault completed successfully: $ActionDescription" -Tag "Success"
        return $true
    }
    catch {
        Write-Log "XCVault threw an exception during '$ActionDescription': $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function Add-PdfXChangeLicenseKey {
    Write-Log "Adding the configured license key for the current user (HKCU) via XCVault /AddKeyData /S" -Tag "Run"

    return Invoke-XcVaultCommand -ArgumentList @("/AddKeyData", $licenseKey, "/S") `
        -ActionDescription "Add per-user license key"
}

function Invoke-PdfXChangeLicenseActivation {
    Write-Log "Activating the installed license key for the current user via XCVault /ActivateKeys /S" -Tag "Run"

    return Invoke-XcVaultCommand -ArgumentList @("/ActivateKeys", "/S") `
        -ActionDescription "Activate license key for current user"
}

function Test-PdfXChangeLicenseKeyInRegistry {
    # Confirm XCVault wrote the key entry to the user vault after activation.
    if (-not (Test-Path -Path $vaultRegistryPath)) {
        Write-Log "User vault registry path was not created: $vaultRegistryPath" -Tag "Error"
        return $false
    }

    $vaultValue = Get-ItemProperty -Path $vaultRegistryPath -Name $vaultValueName -ErrorAction SilentlyContinue

    if ($vaultValue) {
        Write-Log "License key entry confirmed in user vault at $vaultRegistryPath" -Tag "Success"
        return $true
    }

    Write-Log "License key entry is missing from user vault at $vaultRegistryPath" -Tag "Error"
    return $false
}

function Start-PdfXChangeLicenseRemediation {
    if (-not (Test-LicenseKeyFormat)) {
        return $false
    }

    if (-not (Test-PdfXChangeEditorInstalled)) {
        Write-Log "PDF-XChange Editor is not installed - deploy the Win32 app before running remediation" -Tag "Error"
        return $false
    }

    if (-not (Test-XcVaultExecutable)) {
        Write-Log "XCVault.exe is missing at $xcVaultPath - PDF-XChange installation may be incomplete" -Tag "Error"
        return $false
    }

    if (-not (Add-PdfXChangeLicenseKey)) {
        return $false
    }

    if (-not (Invoke-PdfXChangeLicenseActivation)) {
        return $false
    }

    return (Test-PdfXChangeLicenseKeyInRegistry)
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"
Write-Log "Applying per-user PDF-XChange license for key prefix '$licenseKeyPrefix'" -Tag "Info"

$remediationSucceeded = Start-PdfXChangeLicenseRemediation

if ($remediationSucceeded) {
    Write-Log "Remediation completed successfully for $env:USERNAME" -Tag "Success"
    Complete-Script -ExitCode 0
}

Write-Log "Remediation failed - review logs at $logFile" -Tag "Error"
Complete-Script -ExitCode 1
