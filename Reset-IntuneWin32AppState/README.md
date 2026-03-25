# 🔄 Reset-IntuneWin32AppState

PowerShell **proactive remediation** pair for **Microsoft Intune**: detect failed **Win32 app** enforcement states locally, clear the right **registry** + **GRS** (Global Re-evaluation Schedule) data, and **restart the Intune Management Extension (IME)** so installs can be **evaluated again**—without waiting on the default retry schedule.

---

## ✨ What it does (in plain language)

| Piece | Role |
|--------|------|
| 📋 **`detection.ps1`** | Scans `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps` for `EnforcementStateMessage`, reads the JSON-style `ErrorCode`, and decides if something is in a **failed** state (not success `0`, not soft-reboot `3010`). **Exit `0`** = compliant (no action). **Exit `1`** = non-compliant → run remediation. |
| 🛠️ **`remediation.ps1`** | For each failed scope, finds **user** + **app** from the registry path, reads **`LastHashValue`** from **Reporting** when present, removes the **app**, **Reporting**, and the matching **GRS hash** subkey (only when a hash exists—safer than wiping a whole GRS branch), then **restarts** `IntuneManagementExtension`. |

Together they implement the same **idea** as the Call4cloud GRS / Win32 retry articles: reset local IME state so Intune can **retry** instead of sitting behind GRS timing.

---

## 🙏 Credits & references

This repo is **inspired by and aligned with** the excellent walkthrough on **Call4cloud**:

- 🔗 **[Trigger IME to retry failed Win32App Installation \| Intune](https://call4cloud.nl/retry-failed-win32app-installation/)** — by **Rudy Ooms** on **Call4cloud**

**Huge thanks** 🎉 to Rudy and Call4cloud for documenting the registry behavior, GRS nuances, and the original **detection / remediation** pattern.

---

## 🚀 Intune deployment

1. Create a **Proactive remediation** in Intune.
2. Upload **`detection.ps1`** as the detection script and **`remediation.ps1`** as the remediation script.
3. Assign to the right groups and schedule (or run on demand).
4. **Remediation** must run with sufficient rights (typically **SYSTEM** as deployed by Intune) because it touches **HKLM** and restarts a service.

> 💡 Intune does **not** pass parameters to these scripts—they are written for **upload-and-run** only.

---

## 📝 Logging

Logs use the shared folder name **`Reset-IntuneWin32AppState`**:

- 📂 `%ProgramData%\IntuneLogs\Scripts\Reset-IntuneWin32AppState\`
- 📄 `detection.log` — detection run
- 📄 `remediation.log` — remediation run

Toggle **`$logDebug = $true`** inside either script when you want extra **Debug**-tag detail for troubleshooting.

---

## ⚠️ Heads-up

- 🧪 **Test on a non-production device** first. Registry cleanup affects **local IME Win32 state** for failed apps.
- 📚 Microsoft may change IME registry layout; after major IME updates, re-verify behavior against logs and the Call4cloud article.
- 🏥 This is a **support / recovery** tool, not a substitute for fixing root causes (bad installer, detection rules, dependencies, etc.).

---

## 📁 Repo layout

| Path | Purpose |
|------|--------|
| `detection.ps1` | Intune detection script |
| `remediation.ps1` | Intune remediation script |
---
