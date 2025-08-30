# =========================[ Configuration ]=========================
# Array with Letter, OldShare, NewShare, optional DesiredLabel
$networkDrive = @(
    [pscustomobject]@{ Letter='M'; OldShare='\\fs01.test.local\Marketing'; NewShare='\\test.local\Files\Marketing'; DesiredLabel='Marketing' }
    # ,[pscustomobject]@{ Letter='T'; OldShare='\\old\Team'; NewShare='\\new\Team' }
)

# =========================[ Logging Block ]=========================
# Script version:   2025-05-29 11:10
# Script author:    Barg0

# ---------------------------[ Script Start Timestamp ]---------------------------
$scriptStartTime = Get-Date

# ---------------------------[ Script name ]---------------------------
$scriptName   = "Network Drive - Switch - M"
$logFileName  = "remediation.log"

# ---------------------------[ Logging Setup ]---------------------------
$log         = $true
$enableLogFile = $true

$logFileDirectory = "$env:ProgramData\IntuneLogs\Scripts\$env:USERNAME\$scriptName"
$logFile          = "$logFileDirectory\$logFileName"

if ($enableLogFile -and -not (Test-Path $logFileDirectory)) {
    New-Item -ItemType Directory -Path $logFileDirectory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message, [string]$Tag = "Info")

    if (-not $log) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tagList = @("Start","Check","Info","Success","Error","Debug","End")
    $rawTag = $Tag.Trim()
    if ($tagList -contains $rawTag) { $rawTag = $rawTag.PadRight(7) } else { $rawTag = "Error  " }

    $color = switch ($rawTag.Trim()) {
        "Start"{"Cyan"}; "Check"{"Blue"}; "Info"{"Yellow"}; "Success"{"Green"}; "Error"{"Red"}; "Debug"{"DarkYellow"}; "End"{"Cyan"}; default{"White"}
    }

    $logMessage = "$timestamp [  $rawTag ] $Message"

    if ($enableLogFile) { "$logMessage" | Out-File -FilePath $logFile -Append }

    Write-Host "$timestamp " -NoNewline
    Write-Host "[  " -NoNewline -ForegroundColor White
    Write-Host "$rawTag" -NoNewline -ForegroundColor $color
    Write-Host " ] " -NoNewline -ForegroundColor White
    Write-Host "$Message"
}

function Complete-Script {
    param([int]$ExitCode)
    $scriptEndTime = Get-Date
    $duration = $scriptEndTime - $scriptStartTime
    Write-Log "Script execution time: $($duration.ToString('hh\:mm\:ss\.ff'))" -Tag "Info"
    Write-Log "Exit Code: $ExitCode" -Tag "Info"
    Write-Log "======== Script Completed ========" -Tag "End"
    exit $ExitCode
}

# =========================[ Helpers ]=========================

function Convert-PathString {
    param([string]$Path)
    if ($null -eq $Path) { return $null }
    $t = $Path.Trim()
    if ($t.EndsWith("\")) { $t = $t.TrimEnd("\") }
    return $t.ToLowerInvariant()
}

function Get-DefaultLabelFromUNC {
    param([string]$UNC)
    if ($null -eq $UNC) { return $null }
    $parts = $UNC.TrimEnd("\") -split "\\"
    if ($parts.Count -gt 0) { return $parts[-1] }
    return $UNC
}

# Robust mapping lookup: COM -> CIM -> Registry
function Get-CurrentMapping {
    param([char]$Letter)

    # 1) COM: WScript.Network
    try {
        $nw = New-Object -ComObject WScript.Network
        $list = $nw.EnumNetworkDrives()
        for ($i = 0; $i -lt $list.Count; $i += 2) {
            $drv = $list.Item($i)     # e.g., "P:"
            $unc = $list.Item($i + 1) # e.g., "\\server\share"
            if ($drv.TrimEnd(':').ToUpper() -eq $Letter.ToString().ToUpper()) {
                if (-not [string]::IsNullOrWhiteSpace($unc)) { return $unc }
            }
        }
    } catch {}

    # 2) CIM: Win32_LogicalDisk
    try {
        $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Letter):'"
        if ($ld -and $ld.DriveType -eq 4 -and -not [string]::IsNullOrWhiteSpace($ld.ProviderName)) {
            return $ld.ProviderName
        }
    } catch {}

    # 3) Registry: HKCU:\Network\<Letter>\RemotePath
    try {
        $reg = "HKCU:\Network\$Letter"
        if (Test-Path $reg) {
            $rp = (Get-ItemProperty -Path $reg -Name RemotePath -ErrorAction SilentlyContinue).RemotePath
            if (-not [string]::IsNullOrWhiteSpace($rp)) { return $rp }
        }
    } catch {}

    return $null
}

# Approved verbs
function Remove-NetworkDriveMapping {
    param([char]$Letter)
    try {
        $out = net use "${Letter}:" /delete /y 2>&1
        if ($LASTEXITCODE -eq 0 -or $out -match "The network connection could not be found|The system cannot find the file specified") {
            Start-Sleep -Milliseconds 500
            $check = Get-CurrentMapping -Letter $Letter
            if ($null -eq $check) {
                Write-Log "Drive $($Letter): successfully unmapped." -Tag "Success"
                return $true
            }
        }
        Write-Log "Drive $($Letter): unmap reported error: $out" -Tag "Error"
        return $false
    } catch {
        Write-Log "Drive $($Letter): unmap exception: $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

function Add-NetworkDriveMapping {
    param([char]$Letter, [string]$UNC)
    Write-Log "Mapping $($Letter): to '$UNC' via 'net use' (persistent)" -Tag "Info"
    $attempts = 0; $max = 3
    while ($attempts -lt $max) {
        $attempts++
        try {
            $out = net use "${Letter}:" "$UNC" /persistent:yes 2>&1
            if ($LASTEXITCODE -eq 0) {
                Start-Sleep -Seconds 1
                $cur = Get-CurrentMapping -Letter $Letter
                if ($null -ne $cur -and (Convert-PathString $cur) -eq (Convert-PathString $UNC)) {
                    Write-Log "Drive $($Letter): mapped and verified to '$cur'." -Tag "Success"
                    return $true
                } else {
                    Write-Log "Drive $($Letter): verification failed. Now '$cur' (attempt $attempts/$max)." -Tag "Error"
                }
            } else {
                Write-Log "net use failed (attempt $attempts/$max): $out" -Tag "Error"
            }
        } catch {
            Write-Log "Exception during mapping (attempt $attempts/$max): $($_.Exception.Message)" -Tag "Error"
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

# --- Label helpers (HKCU\...\MountPoints2) ---
function Get-MountPoints2KeyFromUNC {
    param([string]$UNC)
    if ([string]::IsNullOrWhiteSpace($UNC)) { return $null }
    $escaped = ($UNC -replace "\\", "#") -replace ":", ""
    return "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\$escaped"
}

function Remove-LabelForUNCUser {
    param([string]$UNC)
    $key = Get-MountPoints2KeyFromUNC -UNC $UNC
    if ($null -eq $key) { return }
    if (Test-Path $key) {
        try {
            if (Get-ItemProperty -Path $key -Name "_LabelFromReg" -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $key -Name "_LabelFromReg" -ErrorAction SilentlyContinue
                Write-Log "Removed old label for '$UNC'." -Tag "Success"
            }
        } catch {
            Write-Log "Failed removing label for '$UNC': $($_.Exception.Message)" -Tag "Error"
        }
    }
}

function Set-LabelForUNCUser {
    param([string]$UNC, [string]$Label)
    $key = Get-MountPoints2KeyFromUNC -UNC $UNC
    if ($null -eq $key) { return $false }
    try {
        if (-not (Test-Path $key)) { New-Item -ItemType Directory -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name "_LabelFromReg" -PropertyType String -Value $Label -Force | Out-Null
        $verify = (Get-ItemProperty -Path $key -Name "_LabelFromReg" -ErrorAction SilentlyContinue)._LabelFromReg
        if ($verify -eq $Label) {
            Write-Log "Label set for '$UNC' -> '$Label'." -Tag "Success"
            return $true
        } else {
            Write-Log "Label verification failed for '$UNC'. Current '$verify' != '$Label'." -Tag "Error"
            return $false
        }
    } catch {
        Write-Log "Error setting label for '$UNC': $($_.Exception.Message)" -Tag "Error"
        return $false
    }
}

# =========================[ Script Start ]=========================
Write-Log "======== Script Started ========" -Tag "Start"
Write-Log "ComputerName: $env:COMPUTERNAME | User: $env:USERNAME | Script: $scriptName" -Tag "Info"

$overallSuccess = $true

foreach ($item in $networkDrive) {
    $letter = [char]$item.Letter
    $oldRaw = $item.OldShare
    $newRaw = $item.NewShare
    $old    = Convert-PathString $oldRaw
    $new    = Convert-PathString $newRaw
    $desiredLabel = if ($null -ne $item.PSObject.Properties['DesiredLabel']) { $item.DesiredLabel } else { Get-DefaultLabelFromUNC -UNC $newRaw }

    Write-Log "Evaluating drive $($letter): old '$oldRaw' -> new '$newRaw' | Label: '$desiredLabel'" -Tag "Check"

    $current = Get-CurrentMapping -Letter $letter
    $currentNorm = if ($null -ne $current) { Convert-PathString $current } else { $null }

    # If detection was ambiguous (e.g., Get-PSDrive showed P:\), trust registry if it matches OLD
    if ($null -eq $current -or $current -eq "${letter}:\") {
        $regPath = (Get-ItemProperty -Path "HKCU:\Network\$letter" -Name RemotePath -ErrorAction SilentlyContinue).RemotePath
        if ($regPath -and (Convert-PathString $regPath) -eq $old) {
            Write-Log "Registry indicates OLD path despite current '$current'. Treating as OLD." -Tag "Debug"
            $currentNorm = $old
        }
    }

    if ($null -eq $currentNorm) {
        Write-Log "Drive $($letter): not mapped. Per spec, no action. Cleaning old label only." -Tag "Info"
        Remove-LabelForUNCUser -UNC $oldRaw
        continue
    }

    Write-Log "Drive $($letter): currently mapped to '$current'." -Tag "Info"

    if ($currentNorm -eq $new) {
        Write-Log "Drive $($letter): already on NEW path. Skipping remap." -Tag "Success"
        Remove-LabelForUNCUser -UNC $oldRaw
        if (-not (Set-LabelForUNCUser -UNC $newRaw -Label $desiredLabel)) { $overallSuccess = $false }
        continue
    }

    if ($currentNorm -eq $old) {
        Write-Log "Drive $($letter): on OLD path. Switching to NEW via 'net use'..." -Tag "Info"

        if (-not (Remove-NetworkDriveMapping -Letter $letter)) {
            $overallSuccess = $false
            Write-Log "Drive $($letter): failed to unmap old path." -Tag "Error"
            continue
        }

        $mapped = Add-NetworkDriveMapping -Letter $letter -UNC $newRaw
        if (-not $mapped) {
            $overallSuccess = $false
            Write-Log "Drive $($letter): failed to map to new path '$newRaw'." -Tag "Error"
            continue
        }

        Remove-LabelForUNCUser -UNC $oldRaw
        if (-not (Set-LabelForUNCUser -UNC $newRaw -Label $desiredLabel)) { $overallSuccess = $false }

        Write-Log "Drive $($letter): successfully switched to new path and label updated." -Tag "Success"
        continue
    }

    # Unexpected mapping -> no remap per spec; still tidy old label
    Write-Log "Drive $($letter): mapped to unexpected path '$current'. No remap per spec. Cleaning old label only." -Tag "Info"
    Remove-LabelForUNCUser -UNC $oldRaw
}

if ($overallSuccess) { Complete-Script -ExitCode 0 } else { Complete-Script -ExitCode 1 }
