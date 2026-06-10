# 🖥️ Set-RdpWarningDialog

Microsoft Intune remediation script pair that reverts the **RDP file security dialog** to the legacy version by configuring the `RedirectionWarningDialogVersion` registry value.

---

## 📖 Background

Starting with the [April 2026 security update (CVE-2026-26151)](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-26151), the Remote Desktop Connection app shows **new security warnings** when opening `.rdp` files:

- 🆕 A first-launch educational dialog about phishing risks
- 🔒 A connection security dialog on **every** `.rdp` file launch
- 🚫 All device redirections (drives, clipboard, smart cards, ...) are **off by default** and must be enabled manually per connection

If this causes disruptions in your environment, Microsoft documents a registry value to temporarily restore the previous dialog behavior:

📚 [Understanding security warnings when opening Remote Desktop (RDP) files](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/understanding-security-warnings)

This script pair automates exactly that via Intune remediations.

---

## 🔧 What gets configured

| Setting | Value |
|---|---|
| 🗝️ Registry key | `HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services\Client` |
| 🏷️ Value name | `RedirectionWarningDialogVersion` |
| 🔢 Type | `REG_DWORD` |
| 🎯 Data | `1` (legacy dialog behavior) |

---

## 📂 Files

| File | Purpose |
|---|---|
| `detection.ps1` | 🔍 Checks if the registry value is present and set to `1` |
| `remediation.ps1` | 🛠️ Creates/corrects the registry value, but only when actually required |

### 🔍 detection.ps1

1. Reads the registry value
2. Reports compliance via exit code:

| Exit code | Meaning |
|---|---|
| `0` | ✅ Value is present and correct - device is compliant, no remediation runs |
| `1` | ⚠️ Value is missing or incorrect - Intune triggers the remediation script |

### 🛠️ remediation.ps1

1. **Re-checks** the current state first - if the value is already correct, it exits `0` without touching the registry (prevents unnecessary writes)
2. Creates the registry key path if it does not exist
3. Writes the value as `REG_DWORD` with data `1` (also corrects a wrong value type)
4. **Verifies** the value after writing

| Exit code | Meaning |
|---|---|
| `0` | ✅ Value is correct (already compliant or successfully remediated) |
| `1` | ❌ Remediation failed (see log file for details) |

---

## 🚀 Deployment in Microsoft Intune

### ✅ Prerequisites

- Devices are Intune-managed and run Windows 10/11
- A license that includes Intune remediations (e.g. Windows E3/E5, A3/A5, or Microsoft 365 Business Premium)

### 📋 Steps

1. Open the [Microsoft Intune admin center](https://intune.microsoft.com)
2. Navigate to **Devices** > **Scripts and remediations** > **Remediations**
3. Click **➕ Create**
4. **Basics:** Enter a name, e.g. `Set-RdpWarningDialog`, and a description
5. **Settings:** Upload the scripts and configure:

| Setting | Value |
|---|---|
| Detection script file | `detection.ps1` |
| Remediation script file | `remediation.ps1` |
| Run this script using the logged-on credentials | ❌ **No** (runs as SYSTEM, required for HKLM) |
| Enforce script signature check | ❌ No |
| Run script in 64-bit PowerShell | ✅ **Yes** |

6. **Scope tags:** Assign as needed
7. **Assignments:** Select your target device group and set a schedule (e.g. 🕐 daily)
8. **Review + create** 🎉

---

## 📝 Logging

Both scripts write structured logs to:

```
C:\ProgramData\IntuneLogs\Scripts\Set-RdpWarningDialog\
├── detection.log
└── remediation.log
```

Example log output:

```
2026-06-10 09:52:01 [  Start   ] ==================== Start ====================
2026-06-10 09:52:01 [  Get     ] Reading registry value 'RedirectionWarningDialogVersion' from 'HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
2026-06-10 09:52:01 [  Info    ] Registry value 'RedirectionWarningDialogVersion' is not present, remediation is required
2026-06-10 09:52:01 [  Info    ] Exit 1
2026-06-10 09:52:01 [  End     ] ==================== End ====================
```

### 🐞 Debug logging

For verbose troubleshooting output (registry key existence checks, PowerShell version, process bitness), enable the debug switch at the top of each script:

```powershell
$logDebug = $true   # Set to $true for verbose DEBUG logging
```

---

## 🔎 Manual verification

Check the value on a device with:

```powershell
Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client" -Name "RedirectionWarningDialogVersion"
```

Or via classic command line:

```cmd
reg query "HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services\Client" /v RedirectionWarningDialogVersion
```

---

## ⚠️ Important notice

> Microsoft explicitly states that **a future Windows update might remove support for this registry value**, even on older versions of Windows.

Treat this remediation as a **temporary bridge** 🌉 - plan to transition your environment to the new security dialog, for example by **digitally signing** your organization's `.rdp` files so they show a verified publisher instead of "Unknown publisher".

---

## 📚 References

- [Understanding security warnings when opening Remote Desktop (RDP) files](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/understanding-security-warnings)
- [CVE-2026-26151 - April 2026 security update](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-26151)
- [Remediations in Microsoft Intune](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations)
