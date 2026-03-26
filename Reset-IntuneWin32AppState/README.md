# Reset Win32 app retry state (Intune Proactive Remediation)

This repository contains a **Microsoft Intune Proactive Remediation** pair written in PowerShell. Together, the scripts detect **failed Win32 app** enforcement state stored by the **Intune Management Extension (IME)** on a Windows device, clear the relevant **local registry and cache** data so IME is not blocked by stale state (including **GRS**—Global Re-evaluation Schedule), and **restart** the IME service so assignments can be evaluated again without waiting for the default backoff schedule.

---

## What the scripts do

### `detection.ps1`

- Reads subkeys under  
  `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps`  
  and looks for the **`EnforcementStateMessage`** value (JSON-like text).
- Treats the device as **non-compliant** (exit code **1**) when either:
  - **`ErrorCode`** is present and is neither success (**0**) nor the common pending-reboot success (**3010**), or  
  - **`EnforcementState`** matches known failure states used by IME (for example download or service communication failures that may appear even when `ErrorCode` is zero or misleading).
- Otherwise exits **0** (compliant)—no remediation run.

### `remediation.ps1`

Runs when detection reports failure. For each distinct **user scope** (Entra user object ID or device scope) and **app id** inferred from the registry path, it:

1. Removes the **app** state key and the **Reporting** subtree for that app (under `Win32Apps` and `Win32Apps\Reporting`).
2. Finds and removes **all matching subkeys** under  
   `...\Win32Apps\<scope>\GRS\`  
   by aligning with current IME behavior: the app identifier may appear in the **GRS subkey name** and/or in **value names** on that key (see references below). If nothing matches, it may fall back to **`LastHashValue`** from reporting when that data still exists.
3. Optionally clears **content cache** for resolved content hashes (encrypted package under IME `Content\Incoming` and extracted files under `%WINDIR%\IMECache`) so the next attempt can fetch fresh content.
4. **Restarts** the **`IntuneManagementExtension`** Windows service.

Remediation is **reactive**: it addresses **locally recorded** failure state. It does not fix root causes such as network outages, TLS or proxy issues, expired device management certificates, bad installers, or detection rules that still report the app as installed. After major IME updates, validate behavior on a test device.

---

## Logging

Scripts log under:

`%ProgramData%\IntuneLogs\Scripts\Reset-Win32AppState\`

- `detection.log` — detection runs  
- `remediation.log` — remediation runs  

Enable verbose **`Debug`** lines by setting `$logDebug = $true` inside the script you are troubleshooting.

---

## Deploying in Intune

1. In **Microsoft Intune**, create a **Proactive remediation** policy.
2. Upload **`detection.ps1`** as the detection script and **`remediation.ps1`** as the remediation script.
3. Assign to the appropriate groups and schedule (or use on-demand remediation where available).
4. Ensure the remediation runs in a context that can modify **HKLM** and restart services (**SYSTEM** is typical).

---

## Credits and references

This project builds on community documentation and troubleshooting patterns for IME Win32 apps. Thank you to the authors and sites below.

| Topic | Reference |
|--------|-----------|
| Original idea of clearing Win32 app registry state and GRS-related data to force IME to retry failed installs | **Rudy Ooms**, [Trigger IME to retry failed Win32App Installation](https://call4cloud.nl/retry-failed-win32app-installation/) — **Call4cloud** |
| Registry layout, deleting app keys under `Win32Apps`, and locating **GRS** subkeys (including updated 2026 notes on app id and GRS key names) | **Johan Arwidmark**, [Force Application Reinstall in Microsoft Intune (Win32 Apps)](https://www.deploymentresearch.com/force-application-reinstall-in-microsoft-intune-win32-apps/) — **Deployment Research** |
| Practical approach to matching GRS registry entries to an app without relying on log parsing | **David Bolding**, [Force Intune apps to redeploy](https://therandomadmin.com/2025/01/01/force-intune-apps-to-redeploy/) — **The Random Admin** (also credited from Deployment Research) |
| **`EnforcementState`**, **`ComplianceState`**, and related numeric codes as stored in registry JSON | **Ben Whitmore**, [Win32 app State Messages Demystified](https://msendpointmgr.com/2023/08/28/win32-app-state-messages-demystified/) — **MSEndpointMgr** |

Additional context on Intune app deployment and troubleshooting appears in Microsoft’s own documentation (for example [Intune Win32 app management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management)) and in the broader MEM community.

---

## Repository contents

| File | Purpose |
|------|---------|
| `detection.ps1` | Proactive remediation detection script |
| `remediation.ps1` | Proactive remediation remediation script |

---