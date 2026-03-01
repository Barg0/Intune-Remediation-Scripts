# 🏷️ Set-NetworkDriveLabels

Sets friendly labels on network drives mapped through the [Intune Drive Mapping ADMX](https://call4cloud.nl/intune-drive-mappings-admx-drive-letters/), using Intune Proactive Remediations.

Microsoft Intune does not have a built-in mechanism for naming network drives. When drives are mounted via the ADMX policy, Windows shows the raw UNC path in File Explorer 😬. This project generates detection and remediation script pairs that set a `_LabelFromReg` registry value under `MountPoints2`, giving each drive a clean display name ✨.

## 📁 Project Structure

```
Set-NetworkDriveLabels/
├── 📄 network-drive-labels.csv      # Drive mappings + Entra group targeting
├── 📦 package.ps1                   # Generates scripts from templates
├── 🚀 deploy.ps1                   # Deploys to Intune via Graph API
├── 📂 templates/
│   ├── 🔍 detection.ps1             # Detection template
│   ├── 🔧 remediation.ps1           # Remediation template
│   └── 📖 README.md                 # Manual usage guide
├── 📂 label-scripts/                # Generated output (after running package.ps1)
│   └── 📂 <DriveLetter>/
│       ├── 🔍 detection.ps1
│       └── 🔧 remediation.ps1
└── 📂 log/
    ├── 📝 package.log               # Packaging log output
    └── 📝 deploy.log                # Deployment log output
```

## 🚀 Quick Start

### 1️⃣ Define your drive mappings

Edit `network-drive-labels.csv` with one row per drive:

```csv
DriveLetter,DrivePath,Label,EntraGroup
M,\\files.domain.local\Marketing$,Marketing,GRP-Marketing-Devices
H,\\files.domain.local\HR,Human Resources,GRP-HR-Devices
S,\\files.domain.local\Shared,Shared Drive,GRP-All-Devices
```

| Column | Description |
|---|---|
| `DriveLetter` | The drive letter assigned by the ADMX policy (without `:`) |
| `DrivePath` | The full UNC path to the network share |
| `Label` | The friendly name to display in File Explorer |
| `EntraGroup` | Display name of the Entra ID group to target for assignment |

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

### 3️⃣ Deploy to Intune

You have two options: **automated** via `deploy.ps1` or **manual** upload through the Intune portal.

#### Option A: Automated deployment 🤖

```powershell
.\deploy.ps1
```

This connects to Microsoft Graph (interactive login), creates the Proactive Remediations in Intune, and assigns them to the Entra groups from the CSV. See [Deploy Script Configuration](#-deploy-script-configuration) for details.

#### Option B: Manual upload 🖱️

For each drive letter folder in `label-scripts/`:

1. 🌐 Go to **Devices > Remediations** in the Intune portal.
2. ➕ Click **Create script package**.
3. 🔍 Upload `detection.ps1` as the detection script.
4. 🔧 Upload `remediation.ps1` as the remediation script.
5. ⚙️ Configure the script package:
   - **Run this script using the logged-on credentials**: Yes
   - **Run script in 64-bit PowerShell**: Yes
6. 👥 Assign to the appropriate user or device group.
7. 🕐 Set a schedule (e.g. once every hour, or once daily).

## 🚀 Deploy Script Configuration

The `deploy.ps1` script has a config section at the top with the following options:

| Variable | Default | Description |
|---|---|---|
| `$intuneNamePrefix` | `"Network Drive - Label"` | Each remediation is named `{prefix} - {DriveLetter}` |
| `$intunePublisher` | `"IT Department"` | Publisher / author shown in Intune |
| `$scheduleType` | `"Hourly"` | `"Hourly"` or `"Daily"` |
| `$scheduleInterval` | `1` | Every X hours (1-23) or every X days (1-23) |
| `$scheduleDailyTime` | `"08:00"` | Time of day to run (only used with `"Daily"`) |
| `$scheduleUseUtc` | `$false` | Use UTC for the daily time (only used with `"Daily"`) |
| `$deviceFilterId` | `""` | Intune Assignment Filter ID (GUID). Leave empty to skip |
| `$deviceFilterType` | `"include"` | `"include"` or `"exclude"` (only used when filter ID is set) |

The description for each remediation in Intune is generated dynamically:
> Sets the label 'Marketing' on drive M: mapped via ADMX.

### 🔎 Finding the Device Filter ID

If you want to scope the assignment to a device filter, you need its GUID. There are three ways to find it:

**Via the Intune Portal:**
1. Go to **Devices > Filters** (under Organize devices).
2. Click the filter you want to use.
3. The GUID is shown in the **Filter ID** field on the overview page, or in the browser URL:
   `https://intune.microsoft.com/.../assignmentFilter/<GUID>/...`

**Via PowerShell** (after connecting to Graph):

```powershell
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters" -Method GET |
    Select-Object -ExpandProperty value |
    Format-Table displayName, id, platform
```

**Via Graph Explorer:**

```
GET https://graph.microsoft.com/beta/deviceManagement/assignmentFilters
```

Copy the `id` value of the filter you want and paste it into `$deviceFilterId` in `deploy.ps1`.

### 🔄 Idempotency

Running `deploy.ps1` multiple times is safe. If a remediation with the same name already exists in Intune, the script will **update** its script content and properties instead of creating a duplicate.

## ⚙️ How It Works

The ADMX policy creates registry entries under `HKCU:\Network\<DriveLetter>` to mount the drive. Windows uses `HKCU:\...\MountPoints2\##server#share` to track drive metadata.

- 🔍 **Detection** checks whether `_LabelFromReg` exists at the correct `MountPoints2` key and matches the desired label. If the registry path doesn't exist yet (drive hasn't been mounted), it retries up to 10 times with a 2-minute interval before reporting non-compliant.
- 🔧 **Remediation** only runs when detection exits with code `1`. It sets `_LabelFromReg` to the desired value and validates the write.

## 📝 Logging

📦 **package.ps1** logs to `log/package.log` in the project root.

🚀 **deploy.ps1** logs to `log/deploy.log` in the project root.

💻 **Detection and remediation scripts** (on target devices) log to:

```
%ProgramData%\IntuneLogs\Scripts\%USERNAME%\Network Drive - Label - <DriveLetter>\
```

## 📋 Prerequisites

- 🗺️ Network drives must already be mapped via the [Drive Mapping ADMX](https://call4cloud.nl/intune-drive-mappings-admx-drive-letters/) or an equivalent method.
- 🌐 Devices must have line-of-sight to the file server (on-prem network or VPN).
- 🔑 For SSO to the file server, [Entra Connect](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/whatis-azure-ad-connect-v2) (formerly Azure AD Connect) should be configured to sync password hashes.

### For deploy.ps1 only

- 📦 **Microsoft.Graph.Authentication** PowerShell module:
  ```powershell
  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
  ```
- 🔐 An account with the following Microsoft Graph permissions:
  - `DeviceManagementScripts.ReadWrite.All`
  - `Group.Read.All`
- 🪪 An active **Intune license** on the tenant.

## 🛠️ Manual Usage

If you only need scripts for a single drive and don't want to use the CSV workflow, see the [📖 templates README](templates/README.md) for manual placeholder replacement instructions.
