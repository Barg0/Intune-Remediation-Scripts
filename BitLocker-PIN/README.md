# BitLocker with PIN – Intune Proactive Remediation

🔒 Silently enable BitLocker with pre-boot PIN on Windows devices via Intune—no user interaction required. Meets Microsoft Security and CIS compliance requirements.

---

## 📋 What This Does

| Script | Purpose |
|--------|---------|
| **detection.ps1** | 🔍 Checks if the OS drive is compliant: encrypted with TPM+PIN. Returns exit 1 if remediation is needed. |
| **remediation.ps1** | 🛠️ Enables BitLocker with TPM+PIN, sets a date-based PIN, backs up recovery key to Azure AD. |
| **remove.ps1** | 🧹 Strips BitLocker from the device (decrypts + removes protectors) for clean testing. |

---

## 🚀 Quick Start

1. **Configure Intune profiles**
   - Endpoint Security → Disk Encryption: Require TPM+PIN, block TPM-only

2. **Create Proactive Remediation** in Intune:
   - **Detection script:** `detection.ps1`
   - **Remediation script:** `remediation.ps1`
   - **Run as:** System

3. **Assign** to device groups (e.g. All Autopilot devices).

---

## 📁 Script Details

### detection.ps1

Checks the OS volume BitLocker status. Triggers remediation (exit 1) when:
- 🔓 BitLocker is **off** (volume `FullyDecrypted`)
- 🔐 BitLocker is **on** but only TPM protector (no PIN required at boot)

Returns compliant (exit 0) when encrypted with TPM+PIN protector present.

### remediation.ps1

Handles two scenarios:
- **FullyDecrypted:** Enables BitLocker from scratch with TPM+PIN + Recovery Password, backs up key to Azure AD
- **TPM-only:** Adds TPM+PIN protector, removes TPM-only, backs up recovery key to Azure AD

Clears existing protectors first if in a stale state to avoid conflicts. Restart required after completion.

### remove.ps1

Utility for test/dev. Run locally as Administrator to:
- ⏹️ Disable BitLocker and start decryption
- ⏳ Wait for decryption to finish
- 🗑️ Remove all key protectors

Leaves the device clean for a fresh remediation run. **Not for production use.**

---

## 🔢 PIN Format

Initial PIN uses date-based format **YYYYMM** (e.g. `202601` for January 2026). Users should change it after first login.

---

## 📂 Logs

Logs are written to: `C:\ProgramData\IntuneLogs\Scripts\BitLocker-PIN\`

| Script | Log File |
|--------|----------|
| Detection | `detection.log` |
| Remediation | `remediation.log` |
| Remove | `remove.log` |

Set `$logDebug = $true` in the script header for verbose debug output when troubleshooting.

---

## 📢 User Instructions

> Your device uses a pre-boot BitLocker PIN. The initial PIN is **YYYYMM** (deployment month).  
> Change it after first login: right-click **C:** in File Explorer → **Manage BitLocker** → **Change PIN**.
