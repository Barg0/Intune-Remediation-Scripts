# 🖨️ Mount Shared Printers

Mass-generate and deploy Intune Remediation scripts for shared network printers from a single CSV file. 🚀

## 📁 Project Structure

```
Mount-SharedPrinters/
├── 📂 template/
│   ├── 🔍 detection.ps1        # Detection template with placeholders
│   ├── 🔧 remediation.ps1      # Remediation template with placeholders
│   └── 📖 README.md            # Manual setup & Intune deployment guide
├── 📂 printers/                # Generated output (created by package.ps1)
│   └── 📂 <ScriptName>/
│       ├── 🔍 detection.ps1
│       └── 🔧 remediation.ps1
├── 📦 package.ps1              # Generates scripts from CSV + templates
├── 🚀 deploy.ps1               # Deploys generated scripts to Intune via Graph API
├── 📋 printers.csv             # Printer definitions
└── 📖 README.md
```

## 🚀 Usage

### ✏️ 1. Edit the CSV

Open `printers.csv` and add one row per printer group. Separate multiple printer names with `;`.

```csv
ScriptName,PrintServer,Printers,EntraGroup
PRT01,print.domain.local,prt01;prt02,SG-Intune-Printer-PRT01
PRT02,print.domain.local,prt03,SG-Intune-Printer-PRT02
Office-3F,printserver.contoso.com,HP-LaserJet-4050;Canon-ImageRunner,SG-Intune-Printer-Office3F
```

| Column        | Description                                                  |
|---------------|--------------------------------------------------------------|
| `ScriptName`  | 🏷️ Unique identifier — becomes the output folder name and part of `$scriptName` (`Printer - <ScriptName>`) in the generated scripts |
| `PrintServer` | 🖥️ FQDN of the print server                                 |
| `Printers`    | 🖨️ Semicolon-separated list of shared printer names          |
| `EntraGroup`  | 👥 Entra ID security group the Intune remediation will be assigned to |

### 📦 2. Run the Package Script

```powershell
powershell -ExecutionPolicy Bypass -File .\package.ps1
```

The script reads `printers.csv`, replaces the `__SCRIPTNAME__` and `__PRINTERS__` placeholders in the templates, and writes ready-to-upload scripts to `printers/<ScriptName>/`. ✨

For the example CSV above, this generates:

```
printers/
├── 📂 PRT01/
│   ├── 🔍 detection.ps1         # \\print.domain.local\prt01, \prt02
│   └── 🔧 remediation.ps1
├── 📂 PRT02/
│   ├── 🔍 detection.ps1         # \\print.domain.local\prt03
│   └── 🔧 remediation.ps1
└── 📂 Office-3F/
    ├── 🔍 detection.ps1         # \\printserver.contoso.com\HP-LaserJet-4050, \Canon-ImageRunner
    └── 🔧 remediation.ps1
```

### ☁️ 3. Deploy to Intune

You can deploy either **automatically** with `deploy.ps1` or **manually** through the Intune portal.

#### 🤖 Option A: Automated Deployment

> ⚠️ **Prerequisite:** Run `package.ps1` first to generate the scripts in `printers/`.

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1
```

`deploy.ps1` connects to Microsoft Graph via interactive login and processes each row in `printers.csv`. The script is **idempotent** — running it again will update existing remediations rather than creating duplicates. ♻️

**🔄 For each CSV entry, the script will:**

1. 📄 Read the packaged `detection.ps1` and `remediation.ps1` from `printers/<ScriptName>/`.
2. 🔐 Base64-encode both scripts for the Graph API payload.
3. 🔍 Search Intune for an existing remediation named `🖨️ Printer - <ScriptName>`.
4. ✅ **Create** the remediation if it doesn't exist, or **update** it if it does.
5. 👥 Resolve the `EntraGroup` by display name to its Entra ID object ID.
6. 🎯 Assign the remediation to that group (with optional device filter).
7. ⏰ Apply the configured run schedule to the assignment.

**🔑 Required Graph Scopes** (prompted during interactive login):

- `DeviceManagementScripts.ReadWrite.All`
- `Group.Read.All`

**📦 Required PowerShell Module:**

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

**⚙️ Configuration**

Before running, review and adjust the settings at the top of `deploy.ps1`:

🏷️ **Intune Remediation Settings**

| Setting              | Default       | Description                                                  |
|----------------------|---------------|--------------------------------------------------------------|
| `$intuneNamePrefix`  | `🖨️ Printer` | Display name prefix — each remediation is named `{prefix} - {ScriptName}` |
| `$intunePublisher`   | `Barg0`       | Publisher / author shown in Intune                           |

⏰ **Schedule Settings**

| Setting              | Default   | Description                                                      |
|----------------------|-----------|------------------------------------------------------------------|
| `$scheduleType`      | `Hourly`  | Schedule type: `Hourly` or `Daily`                               |
| `$scheduleInterval`  | `1`       | Interval: every X hours (1–23) or every X days (1–23)            |
| `$scheduleDailyTime` | `08:00`   | Time of day to run (only used when `$scheduleType` is `Daily`)   |
| `$scheduleUseUtc`    | `$false`  | Use UTC for the daily schedule time (only used with `Daily`)     |

🎯 **Device Filter Settings**

| Setting              | Default                                | Description                                      |
|----------------------|----------------------------------------|--------------------------------------------------|
| `$deviceFilterId`    | `19d6856c-7fc9-41fb-aa6b-aff4427d3113` | Device filter GUID — leave empty (`""`) to skip  |
| `$deviceFilterType`  | `include`                              | Filter mode: `include` or `exclude`              |

📝 **Logging Settings**

| Setting           | Default | Description                              |
|-------------------|---------|------------------------------------------|
| `$log`            | `$true` | Enable or disable all logging            |
| `$enableLogFile`  | `$true` | Write logs to `log/deploy.log` on disk   |

#### 🖱️ Option B: Manual Upload

Upload each generated `detection.ps1` + `remediation.ps1` pair as an Intune Remediation through the portal. See the [template README](template/README.md) for step-by-step instructions. 📖

### 🔎 Finding the Device Filter ID

If you want to scope the assignment to a device filter, you need its GUID. There are three ways to find it:

**🖱️ Via the Intune Portal:**

1. Go to **Devices > Filters** (under Organize devices).
2. Click the filter you want to use.
3. The GUID is shown in the **Filter ID** field on the overview page, or in the browser URL:

```
https://intune.microsoft.com/.../assignmentFilter/<GUID>/...
```

**💻 Via PowerShell** (after connecting to Graph):

```powershell
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"
Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters" -Method GET |
    Select-Object -ExpandProperty value |
    Format-Table displayName, id, platform
```

**🌐 Via Graph Explorer:**

```
GET https://graph.microsoft.com/beta/deviceManagement/assignmentFilters
```

## 📋 Logging

Both `package.ps1` and `deploy.ps1` log to the console and to `log/` (`package.log` and `deploy.log` respectively). 📝

```
2026-02-27 12:00:00 [  Start   ] ======== Script Started ========
2026-02-27 12:00:00 [  Get     ] Reading printer definitions from: .\printers.csv
2026-02-27 12:00:00 [  Info    ] Found 3 printer group(s)
2026-02-27 12:00:00 [  Run     ] Processing 'PRT01' (Server: print.domain.local)
2026-02-27 12:00:00 [  Success ] Created detection script:  .\printers\PRT01\detection.ps1
2026-02-27 12:00:00 [  Success ] Created remediation script: .\printers\PRT01\remediation.ps1
2026-02-27 12:00:00 [  Info    ] Generation complete: 3/3 succeeded, 0 failed
2026-02-27 12:00:00 [  End     ] ======== Script Completed ========
```

Set `$logDebug = $true` in `package.ps1` to see the full generated printer arrays and raw CSV values for troubleshooting. 🐛

## 📌 Requirements

- 💻 Windows 10 / 11
- 🌐 Network access to the print server (for the generated scripts)
- ☁️ Microsoft Intune (for deployment)
- 📦 `Microsoft.Graph.Authentication` PowerShell module (for `deploy.ps1`)
