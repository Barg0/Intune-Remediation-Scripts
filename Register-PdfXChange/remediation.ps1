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

# Derived from $licenseKey — do not edit manually.
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

# ---------------------------[ Remediation Functions ]---------------------------
function Test-PdfXChangeEditorInstalled {
    if (Test-Path -Path $pdfXEditPath) {
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
            return $true
        }
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
        $commandOutput = & $xcVaultPath @ArgumentList 2>&1
        $exitCode      = $LASTEXITCODE

        if ($commandOutput) {
            Write-Log "XCVault output:`n$($commandOutput | Out-String)" -Tag "Debug"
        }

        if ($exitCode -ne 0) {
            Write-Log "XCVault command failed with exit code $exitCode during: $ActionDescription" -Tag "Error"
            return $false
        }

        Write-Log "XCVault command completed successfully: $ActionDescription" -Tag "Success"
        return $true
    }
    catch {
        Write-Log "XCVault command threw an exception during '$ActionDescription': $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function Add-PdfXChangeLicenseKey {
    Write-Log "Installing the configured license key for the current user (HKCU) using XCVault /AddKeyData /S" -Tag "Run"

    return Invoke-XcVaultCommand -ArgumentList @(
        "/AddKeyData", $licenseKey,
        "/S"
    ) -ActionDescription "Add per-user license key"
}

function Invoke-PdfXChangeLicenseActivation {
    Write-Log "Activating installed PDF-XChange license keys for the current user using XCVault /ActivateKeys /S" -Tag "Run"

    return Invoke-XcVaultCommand -ArgumentList @(
        "/ActivateKeys",
        "/S"
    ) -ActionDescription "Activate installed license keys for current user"
}

function Get-XcVaultListKeysOutput {
    try {
        $listKeysOutput = & $xcVaultPath /ListKeys 2>&1
        return ($listKeysOutput | Out-String).Trim()
    }
    catch {
        Write-Log "Failed to read license state after remediation: $($_.Exception.Message)" -Tag "Error"
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

function Test-PdfXChangeLicenseKeyInRegistry {
    if (-not (Test-Path -Path $vaultRegistryPath)) {
        return $false
    }

    $vaultValue = Get-ItemProperty -Path $vaultRegistryPath -Name $vaultValueName -ErrorAction SilentlyContinue
    return [bool]$vaultValue
}

function Test-PdfXChangeLicenseActivated {
    param(
        [string]$ListKeysOutput
    )

    $matchingLines = Get-PdfXChangeLicenseKeyLines -ListKeysOutput $ListKeysOutput |
        Where-Object { $_ -match '^\s*\d+\.\s+U\s+' }

    foreach ($matchingLine in $matchingLines) {
        if ($matchingLine -match '^\s*\d+\.\s+U\s+([UMVAIX]+)\s+') {
            $keyState = $Matches[1]
            return $keyState.Contains('V') -and $keyState.Contains('A')
        }
    }

    return $false
}

function Test-PdfXChangeRemediationResult {
    $listKeysOutput = Get-XcVaultListKeysOutput

    if ([string]::IsNullOrWhiteSpace($listKeysOutput)) {
        Write-Log "Post-remediation verification failed because XCVault /ListKeys returned no output" -Tag "Error"
        return $false
    }

    $licenseActivated  = Test-PdfXChangeLicenseActivated -ListKeysOutput $listKeysOutput
    $licenseInRegistry = Test-PdfXChangeLicenseKeyInRegistry

    Write-Log "Post-remediation user registry key present: $licenseInRegistry" -Tag "Debug"
    Write-Log "Post-remediation license activated for current user: $licenseActivated" -Tag "Debug"

    if ($licenseActivated -and $licenseInRegistry) {
        Write-Log "Remediation verification succeeded: configured license key is present and activated for $env:USERNAME" -Tag "Success"
        return $true
    }

    Write-Log "Remediation verification failed: configured license key is not fully present and activated for the current user" -Tag "Error"
    return $false
}

function Start-PdfXChangeLicenseRemediation {
    if (-not (Test-PdfXChangeEditorInstalled)) {
        Write-Log "Remediation cannot continue because PDF-XChange Editor is not installed; deploy the Win32 app first" -Tag "Error"
        return $false
    }

    if (-not (Test-XcVaultExecutable)) {
        Write-Log "Remediation cannot continue because XCVault.exe is missing at $xcVaultPath" -Tag "Error"
        return $false
    }

    if (-not (Add-PdfXChangeLicenseKey)) {
        return $false
    }

    if (-not (Invoke-PdfXChangeLicenseActivation)) {
        return $false
    }

    return (Test-PdfXChangeRemediationResult)
}

# ---------------------------[ Script Start ]---------------------------
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"
Write-Log "Applying per-user PDF-XChange license for configured key prefix '$licenseKeyPrefix'" -Tag "Info"
Write-Log "Intune: run this script with logged-on user credentials" -Tag "Debug"

$remediationSucceeded = Start-PdfXChangeLicenseRemediation

if ($remediationSucceeded) {
    Write-Log "Remediation completed successfully for user $env:USERNAME" -Tag "Success"
    Complete-Script -ExitCode 0
}

Write-Log "Remediation failed; review Intune remediation logs on the device" -Tag "Error"
Complete-Script -ExitCode 1
