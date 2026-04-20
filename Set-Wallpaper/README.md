# Wallpaper remediation (Intune)

This folder contains an **Intune Proactive Remediation** pair that enforces the **desktop wallpaper** for enrolled **Windows 10** and **Windows 11** devices. Both scripts run as **SYSTEM** (not the logged-on user).

## Overview

| File | Role |
| --- | --- |
| `detection.ps1` | Read-only check: verifies **HKLM** `PersonalizationCSP` values match the configured wallpaper path. |
| `remediation.ps1` | Writes **DesktopImagePath**, **DesktopImageUrl**, and **DesktopImageStatus** under **HKLM\...\PersonalizationCSP** so the wallpaper is enforced and **cannot be changed** in Windows Settings. |

Together they keep the device desktop background aligned with your chosen default or custom image path using the **PersonalizationCSP** registry pattern (same idea as Intune’s CSP-based wallpaper policy).

## How Intune remediations work

1. **Detection** runs on a schedule (or at check-in). It exits with a process **exit code**:
   - **`0`** — Compliant (`PersonalizationCSP` already matches). Intune **does not** run remediation.
   - **`1`** — Not compliant (file missing, CSP values wrong or missing, or unsupported OS). Intune **runs** remediation next (for that cycle).
2. **Remediation** runs **only** when detection reported non-compliance. It writes the CSP keys and exits **`0`** on success or **`1`** on failure.

Both scripts must be assigned as a **pair** (detection script + remediation script) and should run as **SYSTEM** so **HKLM** can be read and written reliably.

## `detection.ps1`

- Resolves the desired wallpaper path from **`$configWallpaper`** (see [Configuration](#configuration)).
- Verifies the image file exists on disk.
- Reads **`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP`** (if the key is absent, all values are treated as missing).
- Requires **all** of the following to match:
  - **DesktopImagePath** (REG_SZ) = resolved wallpaper path  
  - **DesktopImageUrl** (REG_SZ) = same path  
  - **DesktopImageStatus** (REG_DWORD) = **1**

If anything is wrong, it logs a separate **Info** line for each mismatch, then exits **1**.

**Exit codes**

| Code | Meaning |
| --- | --- |
| **`0`** | `PersonalizationCSP` is correctly configured for the target path — **no remediation**. |
| **`1`** | Wallpaper file missing, any CSP value missing/wrong, or unsupported OS — **remediation will run** (when assigned). |

No registry writes — detection is **read-only**.

## `remediation.ps1`

- Resolves the same wallpaper path and validates the file exists.
- Calls **`Set-PersonalizationCSP`**, which creates the CSP key if needed and sets **DesktopImagePath**, **DesktopImageUrl**, and **DesktopImageStatus** = **1**. This **locks** the wallpaper in Settings (user cannot pick a different picture).

**Exit codes**

| Code | Meaning |
| --- | --- |
| **`0`** | CSP configured successfully. |
| **`1`** | Wallpaper file not found, CSP write failure, or unsupported OS. |

## Configuration

The variable **`$configWallpaper`** appears at the top of **both** `detection.ps1` and `remediation.ps1` and must be **kept in sync manually** when you change policy.

- **`"default"`** — Uses the stock Windows image: **`img19.jpg`** on Windows 11, **`img0.jpg`** on Windows 10 (under `C:\Windows\Web\Wallpaper\Windows\`).
- **Custom path** — Example: `"C:\Windows\Web\Wallpaper\Company\banner.jpg"`.

**Edition support:** The **PersonalizationCSP** registry approach works on all Windows editions **including Pro**, Enterprise, and Education. The native Intune **Settings Catalog** PersonalizationCSP policy (without PowerShell) requires **Enterprise or Education** only.

**Important:** These scripts **do not copy or download** wallpaper files. The image must **already exist** on the device at the configured path (e.g. deployed by another app, image in your gold master, or a path on a share that is available to the device).

## How to deploy in Intune

1. In **Microsoft Intune admin center**, go to **Devices** → **Scripts and remediations** → **Create** (proactive remediation).
2. Upload **`detection.ps1`** as the detection script and **`remediation.ps1`** as the remediation script.
3. Recommended settings:

   | Setting | Value |
   | --- | --- |
   | Run script in 64-bit PowerShell | **Yes** |
   | Run this script using the logged on credentials | **No** (SYSTEM context) |
   | Enforce script signature check | **No** (unless you sign the scripts and require it) |

4. Assign to a user or device group and choose a schedule (e.g. **daily** or at **check-in**).

## Logging

Logs are written under:

```text
%ProgramData%\IntuneLogs\Scripts\<username>\
```

When scripts run as **SYSTEM**, `<username>` is typically **`SYSTEM`**.

| Script | Log file |
| --- | --- |
| Detection | `detection.log` |
| Remediation | `remediation.log` |

Logs append across runs and can be collected with **Intune diagnostics** or by retrieving files from that path on a device.

## Requirements

- **Windows 10** or **Windows 11**
- **Windows PowerShell 5.1** or later (no extra modules)
- Device **enrolled in Intune**
- Scripts run as **SYSTEM** with permission to modify **HKLM**
- Wallpaper **file present on disk** at the resolved path before detection/remediation runs
