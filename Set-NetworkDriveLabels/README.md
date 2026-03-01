# 🏷️ Set-NetworkDriveLabels

Sets friendly labels on network drives mapped through the [Intune Drive Mapping ADMX](https://call4cloud.nl/intune-drive-mappings-admx-drive-letters/), using Intune Proactive Remediations.

Microsoft Intune does not have a built-in mechanism for naming network drives. When drives are mounted via the ADMX policy, Windows shows the raw UNC path in File Explorer 😬. This project generates detection and remediation script pairs that set a `_LabelFromReg` registry value under `MountPoints2`, giving each drive a clean display name ✨.

## 📁 Project Structure

```
Set-NetworkDriveLabels/
├── 📄 network-drive-labels.csv      # Drive mappings to package
├── 📦 package.ps1                   # Packaging script
├── 📂 templates/
│   ├── 🔍 detection.ps1             # Detection template
│   ├── 🔧 remediation.ps1           # Remediation template
│   └── 📖 README.md                 # Manual usage guide
├── 📂 label-scripts/                # Generated output (after running package.ps1)
│   └── 📂 <DriveLetter>/
│       ├── 🔍 detection.ps1
│       └── 🔧 remediation.ps1
└── 📂 log/
    └── 📝 package.log               # Packaging log output
```

## 🚀 Quick Start

### 1️⃣ Define your drive mappings

Edit `network-drive-labels.csv` with one row per drive:

```csv
DriveLetter,DrivePath,Label
M,\\files.domain.local\Marketing$,Marketing
H,\\files.domain.local\HR,Human Resources
S,\\files.domain.local\Shared,Shared Drive
```

| Column | Description |
|---|---|
| `DriveLetter` | The drive letter assigned by the ADMX policy (without `:`) |
| `DrivePath` | The full UNC path to the network share |
| `Label` | The friendly name to display in File Explorer |

### 2️⃣ Run the packaging script

```powershell
.\package.ps1
```

This reads the CSV, substitutes the placeholders in both templates, and writes the final scripts to `label-scripts/<DriveLetter>/`.

For the example CSV above, the output would be:

```
label-scripts/
├── M/
│   ├── detection.ps1
│   └── remediation.ps1
├── H/
│   ├── detection.ps1
│   └── remediation.ps1
└── S/
    ├── detection.ps1
    └── remediation.ps1
```

### 3️⃣ Upload to Intune

For each drive letter folder:

1. 🌐 Go to **Devices > Remediations** in the Intune portal.
2. ➕ Click **Create script package**.
3. 🔍 Upload `detection.ps1` as the detection script.
4. 🔧 Upload `remediation.ps1` as the remediation script.
5. ⚙️ Configure the script package:
   - **Run this script using the logged-on credentials**: Yes
   - **Run script in 64-bit PowerShell**: Yes
6. 👥 Assign to the appropriate user or device group.
7. 🕐 Set a schedule (e.g. once every hour, or once daily).

## ⚙️ How It Works

The ADMX policy creates registry entries under `HKCU:\Network\<DriveLetter>` to mount the drive. Windows uses `HKCU:\...\MountPoints2\##server#share` to track drive metadata.

- 🔍 **Detection** checks whether `_LabelFromReg` exists at the correct `MountPoints2` key and matches the desired label. If the registry path doesn't exist yet (drive hasn't been mounted), it retries up to 10 times with a 2-minute interval before reporting non-compliant.
- 🔧 **Remediation** only runs when detection exits with code `1`. It sets `_LabelFromReg` to the desired value and validates the write.

## 📝 Logging

📦 **package.ps1** logs to `log/package.log` in the project root.

💻 **Detection and remediation scripts** (on target devices) log to:

```
%ProgramData%\IntuneLogs\Scripts\%USERNAME%\Network Drive - Label - <DriveLetter>\
```

## 📋 Prerequisites

- 🗺️ Network drives must already be mapped via the [Drive Mapping ADMX](https://call4cloud.nl/intune-drive-mappings-admx-drive-letters/) or an equivalent method.
- 🌐 Devices must have line-of-sight to the file server (on-prem network or VPN).
- 🔑 For SSO to the file server, [Entra Connect](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/whatis-azure-ad-connect-v2) (formerly Azure AD Connect) should be configured to sync password hashes.

## 🛠️ Manual Usage

If you only need scripts for a single drive and don't want to use the CSV workflow, see the [📖 templates README](templates/README.md) for manual placeholder replacement instructions.
