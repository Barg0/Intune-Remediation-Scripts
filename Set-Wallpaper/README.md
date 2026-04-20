# Wallpaper remediation (Intune)

This folder contains an **Intune Proactive Remediation** pair that enforces the **desktop wallpaper** for enrolled **Windows 10** and **Windows 11** devices. Both scripts run in **user context** (logged-on credentials), not as SYSTEM.

## Overview

| File | Role |
| --- | --- |
| `detection.ps1` | Read-only check: compares the current wallpaper (registry) to the configured target path. |
| `remediation.ps1` | Applies the wallpaper via `user32.dll` **SystemParametersInfo** (same approach as `Set-PersonalizationDefaults.ps1`). |

Together they keep the user’s desktop background aligned with your chosen default or custom image path.

## How Intune remediations work

1. **Detection** runs on a schedule (or at check-in). It exits with a process **exit code**:
   - **`0`** — Compliant (wallpaper already matches). Intune **does not** run remediation.
   - **`1`** — Not compliant (file missing, wrong wallpaper, or unsupported OS). Intune **runs** remediation next (for that cycle).
2. **Remediation** runs **only** when detection reported non-compliance. It sets the wallpaper and exits **`0`** on success or **`1`** on failure.

Both scripts must be assigned as a **pair** (detection script + remediation script) and must run **as the logged-on user** so `HKCU` and per-user wallpaper APIs behave correctly.

## `detection.ps1`

- Resolves the desired wallpaper path from **`$configWallpaper`** (see [Configuration](#configuration)).
- Verifies the image file exists on disk.
- Reads **`HKCU:\Control Panel\Desktop`** → **`Wallpaper`**.
- Compares that value to the resolved path (string equality).

**Exit codes**

| Code | Meaning |
| --- | --- |
| **`0`** | Wallpaper is already set to the desired path — **no remediation**. |
| **`1`** | Wallpaper file missing, path mismatch, or unsupported OS — **remediation will run** (when assigned). |

No registry writes and no `Set-DesktopWallpaper` calls — detection is **read-only**.

## `remediation.ps1`

- Resolves the same wallpaper path and validates the file exists.
- Calls **`Set-DesktopWallpaper`** (P/Invoke `SystemParametersInfo`) to apply it.

**Exit codes**

| Code | Meaning |
| --- | --- |
| **`0`** | Wallpaper applied successfully. |
| **`1`** | Wallpaper file not found, API failure, or unsupported OS. |

## Configuration

The variable **`$configWallpaper`** appears at the top of **both** `detection.ps1` and `remediation.ps1` and must be **kept in sync manually** when you change policy.

- **`"default"`** — Uses the stock Windows image: **`img19.jpg`** on Windows 11, **`img0.jpg`** on Windows 10 (under `C:\Windows\Web\Wallpaper\Windows\`).
- **Custom path** — Example: `"C:\Windows\Web\Wallpaper\Company\banner.jpg"`.

**Important:** These scripts **do not copy or download** wallpaper files. The image must **already exist** on the device at the configured path (e.g. deployed by another app, image in your gold master, or a path on a share that is available and allowed for the user).

## How to deploy in Intune

1. In **Microsoft Intune admin center**, go to **Devices** → **Scripts and remediations** → **Create** (proactive remediation).
2. Upload **`detection.ps1`** as the detection script and **`remediation.ps1`** as the remediation script.
3. Recommended settings:

   | Setting | Value |
   | --- | --- |
   | Run script in 64-bit PowerShell | **Yes** |
   | Run this script using the logged on credentials | **Yes** |
   | Enforce script signature check | **No** (unless you sign the scripts and require it) |

4. Assign to a user or device group and choose a schedule (e.g. **daily** or at **check-in**).

## Logging

Logs are written per user to:

```text
%ProgramData%\IntuneLogs\Scripts\<username>\
```

| Script | Log file |
| --- | --- |
| Detection | `WallpaperDetection.log` |
| Remediation | `WallpaperRemediation.log` |

Logs append across runs and can be collected with **Intune diagnostics** or by retrieving files from that path on a device.

## Requirements

- **Windows 10** or **Windows 11**
- **Windows PowerShell 5.1** or later (no extra modules)
- Device **enrolled in Intune**
- Scripts run in **user context**
- Wallpaper **file present on disk** at the resolved path before detection/remediation runs
