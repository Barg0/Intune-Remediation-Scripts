# 🖨️ Mount Shared Printers

Intune Remediation script pair that automatically detects and mounts shared network printers on Windows devices.

## ⚙️ How It Works

Intune Remediations use a **detection + remediation** model:

1. 🔍 **`detection.ps1`** runs first and checks whether the specified printers are installed.
   - ✅ Exit code `0` -- all printers are present, nothing to do.
   - ❌ Exit code `1` -- one or more printers are missing, triggers remediation.
2. 🔧 **`remediation.ps1`** runs only when detection reports a failure. It adds the missing printers via `Add-Printer -ConnectionName` and verifies the result.

## 🚀 Setup

### 1. Configure the Scripts

Both scripts share the same configuration block at the top. You need to edit **both files** to match your environment.

📛 **Set the script name** (used for log folder naming):

```powershell
$scriptName = "Printer - Office 2nd Floor"
```

🖨️ **Define your shared printers** using their full UNC paths:

```powershell
$sharedPrinters = @(
    "\\printserver.contoso.com\HP-LaserJet-4050",
    "\\printserver.contoso.com\Canon-ImageRunner"
)
```

> ⚠️ **Important:** The `$scriptName` and `$sharedPrinters` values must be identical in both `detection.ps1` and `remediation.ps1`.

### 2. Deploy via Intune

1. 🌐 Open the [Microsoft Intune admin center](https://intune.microsoft.com).
2. 📂 Navigate to **Devices** > **Remediations**.
3. ➕ Click **+ Create script package**.
4. 📝 Fill in the basics:
   - **Name:** A descriptive name (e.g. `Mount Printer - Office 2nd Floor`).
   - **Description:** Optional.
5. ⚙️ Under **Settings**:
   - **Detection script file:** Upload `detection.ps1`.
   - **Remediation script file:** Upload `remediation.ps1`.
   - **Run this script using the logged-on credentials:** **Yes** (printers are per-user).
   - **Run script in 64-bit PowerShell:** **Yes**.
   - **Enforce script signature check:** Per your organization's policy.
6. 👥 Under **Assignments**, assign to a device or user group.
7. 🕐 Set the **Schedule** (e.g. once every hour, once a day).
8. ✅ Click **Create**.

### 📦 Deploying Multiple Printers

You can deploy different printer sets by creating separate copies of the script pair, each with its own `$scriptName` and `$sharedPrinters`. Create one Intune Remediation per printer group and assign each to the appropriate user/device groups.

## 📋 Logging

Both scripts write structured logs to the console and to a log file on disk.

### 📁 Log Location

```
C:\ProgramData\IntuneLogs\Scripts\<username>\<scriptName>\detection.log
C:\ProgramData\IntuneLogs\Scripts\<username>\<scriptName>\remediation.log
```

### 📄 Log Format

```
2026-02-27 12:00:00 [  Start   ] ======== Detection Script Started ========
2026-02-27 12:00:00 [  Info    ] ComputerName: PC-001 | User: jdoe | Script: Printer - Office
2026-02-27 12:00:00 [  Get     ] Retrieving installed printers...
2026-02-27 12:00:01 [  Error   ] Printer '\\server\printer1' is missing.
2026-02-27 12:00:01 [  Info    ] Exit Code: 1
2026-02-27 12:00:01 [  End     ] ======== Script Completed ========
```

### 🏷️ Log Tags

| Tag       | Color      | Purpose                              |
|-----------|------------|--------------------------------------|
| 🟦 `Start`   | Cyan       | Script start marker                  |
| 🔵 `Get`     | Blue       | Data retrieval operations            |
| 🟪 `Run`     | Magenta    | Action execution (e.g. adding a printer) |
| 🟡 `Info`    | Yellow     | General information                  |
| 🟢 `Success` | Green      | Successful operations                |
| 🔴 `Error`   | Red        | Failures or missing resources        |
| 🟠 `Debug`   | DarkYellow | Verbose debug output                 |
| 🟦 `End`     | Cyan       | Script end marker                    |

### 🎛️ Logging Options

| Variable         | Default | Description                                      |
|------------------|---------|--------------------------------------------------|
| `$log`           | `$true` | Master switch -- disables all logging when `$false` |
| `$logRun`        | `$false`| Show/hide `Run`-tagged messages                  |
| `$enableLogFile` | `$true` | Enable or disable writing to the log file        |

## 🧪 Running Locally (Testing)

You can test the scripts directly in a PowerShell terminal before deploying to Intune:

```powershell
# Check if printers are installed
powershell -ExecutionPolicy Bypass -File .\detection.ps1

# Install missing printers
powershell -ExecutionPolicy Bypass -File .\remediation.ps1
```

> 💡 **Note:** The target print server must be reachable from the machine you're testing on, and the user must have permission to connect to the shared printer.

## 📌 Requirements

- 💻 Windows 10 / 11
- 🌐 Network access to the print server
- ☁️ Microsoft Intune (for automated deployment)
- 👤 Scripts must run in the **user context** (printers are per-user mappings)
