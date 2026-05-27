# 📄 Register-PdfXChange — Intune Proactive Remediation

PowerShell scripts for **Microsoft Intune** that automatically register and activate **PDF-XChange Editor** for the **logged-on user** — no manual license entry required.

---

## 📦 What's in this repository?

| File | Purpose |
|------|---------|
| `detection.ps1` | Checks whether the current user is already licensed and activated |
| `remediation.ps1` | Installs and activates the license when detection fails |

> ⚠️ **Prerequisite:** PDF-XChange Editor must already be deployed (e.g. via Intune Win32 app). These scripts **do not install** the application — they only handle **licensing**.

---

## 🎯 What do the scripts do?

### 🔍 Detection script (`detection.ps1`)

Runs on a schedule and verifies **compliance** for the **current user**:

1. ✅ **PDF-XChange Editor** is installed  
2. ✅ **XCVault.exe** exists at `%ProgramFiles%\Tracker Software\Vault\XCVault.exe`  
3. ✅ The **configured license key** is present in the user's registry (`HKCU`)  
4. ✅ The key is **valid and activated** (verified via `XCVault.exe /ListKeys`)

| Exit code | Meaning |
|-----------|---------|
| `0` | ✅ Compliant — no action needed |
| `1` | ❌ Not compliant — remediation will run |

---

### 🔧 Remediation script (`remediation.ps1`)

Runs when detection reports non-compliance:

1. 🚀 Adds the license key for the **current user** → `XCVault.exe /AddKeyData "<key>" /S`  
2. 🔐 Activates it for that user → `XCVault.exe /ActivateKeys /S`  
3. ✅ Verifies success via registry and `/ListKeys`

| Exit code | Meaning |
|-----------|---------|
| `0` | ✅ Remediation succeeded |
| `1` | ❌ Remediation failed (see logs) |

---

## 👤 Per-user licensing (important!)

These scripts use **per-user** licensing (Tracker's recommended approach when running as the logged-on user):

- Keys are stored in **HKCU** (not machine-wide HKLM)  
- Activation applies to the **user who is signed in**  
- Each user on a shared device gets their own license state  

**Intune requirement:** Scripts must run with **logged-on user credentials**.

---

## ⚙️ Configuration

### 🔑 License key

Update **only** `$licenseKey` in **both** scripts when your key changes:

```powershell
$licenseKey = "<--PUT LICENSE KEY HERE-->"
```

The detection prefix (first 10 characters) is derived automatically — **do not edit** `$licenseKeyPrefix` manually.

> 💡 Copy the key as a **single line** with no line breaks or extra spaces. Tracker's documentation warns that pasted keys from formatted sources can fail silently.

---

### 🐛 Debug logging

To enable verbose troubleshooting logs, set in either script:

```powershell
$logDebug = $true
```

Logs are written to:

```
%ProgramData%\IntuneLogs\Scripts\Register-PdfXChange\
├── detection.log
└── remediation.log
```

---

## 🚀 How to deploy in Intune

### 1️⃣ Prepare the scripts

1. Open `detection.ps1` and `remediation.ps1`  
2. Set `$licenseKey` to your organization's PDF-XChange license key in **both** files  
3. Save the files  

### 2️⃣ Create the Proactive Remediation

1. Sign in to [Microsoft Intune admin center](https://endpoint.microsoft.com)  
2. Go to **Reports** → **Endpoint analytics** → **Proactive remediations**  
   - *(Or: **Devices** → **Scripts and remediations** → **Platform scripts** → **Proactive remediations*)  
3. Click **+ Create script package**  
4. Upload:
   - **Detection script:** `detection.ps1`  
   - **Remediation script:** `remediation.ps1`  
5. Configure:

   | Setting | Recommended value |
   |---------|-------------------|
   | **Run this script using the logged on credentials** | ✅ **Yes** |
   | **Run script in 64-bit PowerShell** | ✅ **Yes** (on 64-bit Windows) |
   | **Enforce signature check** | As per your org policy |

6. Assign to the user or device groups that have PDF-XChange Editor installed  
7. Set a schedule (e.g. daily or weekly)  

### 3️⃣ Deploy PDF-XChange Editor separately

Deploy the Editor **before** or **alongside** this remediation — users need the app and `XCVault.exe` on disk before licensing can succeed.

---

## 📋 Compliance checks (reference)

| Check | What it validates |
|-------|-------------------|
| `EditorInstalled` | `PDFXEdit.exe` or uninstall registry entry exists |
| `XcVaultAvailable` | Licensing utility is present at the expected path |
| `LicenseKeyInRegistry` | User vault entry under `HKCU\...\Vault\0000` |
| `LicenseKeyListed` | Configured key appears in `/ListKeys` with scope **U** (user) |
| `LicenseActivated` | Key state is **VA** (valid + activated) in `/ListKeys` |

---

## 🔒 Security notes

- 🔐 The license key is stored **in plain text** inside the scripts — restrict access to this repository and Intune script packages  
- 👥 PDF-XChange licenses are **per user**, not per device — ensure your license count covers all users who receive this assignment  
- 📝 Do not commit real license keys to public GitHub repositories  

---

## ❓ Troubleshooting

| Symptom | Things to check |
|---------|-----------------|
| Remediation never runs | User must be **logged on** when using user-context scripts |
| `XcVaultAvailable` fails | PDF-XChange Editor not installed or incomplete install |
| Key listed as `M` not `U` | Old machine-wide key from a previous deployment — remediation will add the user key |
| Activation fails | Network access to Tracker activation servers; valid key; activation limit not exceeded |
| Need more detail | Set `$logDebug = $true` and review logs under `%ProgramData%\IntuneLogs\Scripts\Register-PdfXChange\` |

---

## 📚 Further reading

- [Applying keys after installation (Tracker)](https://help.pdf-xchange.com/sysadmin/applying-keys-after-product-installation.html)  
- [Silent activation (Tracker)](https://help.pdf-xchange.com/sysadmin/silent-activation.html)  
- [XCVault command line options](https://help.pdf-xchange.com/sysadmin/v9-xc-vault-command-line-options.html)  

---

## 📁 Repository scope

This repository contains **only** the Intune detection and remediation scripts. Historical deployment assets are kept locally and are **not** part of this GitHub project.

---

Made with ☕ for managed PDF-XChange Editor deployments via Microsoft Intune.
