# 🖨️ Printer Script Templates

These templates are used by `package.ps1` to mass-generate printer scripts. You can also use them manually for one-off deployments.

## ✋ Manual Setup

If you only need to deploy a single printer group without using the package script, copy both templates and edit them directly.

### 1. Set the Script Name

Open both `detection.ps1` and `remediation.ps1` and replace the placeholder:

```powershell
$scriptName = "Printer - __SCRIPTNAME__"
```

With a descriptive name, for example:

```powershell
$scriptName = "Printer - Office 2nd Floor"
```

> ⚠️ The `$scriptName` value must be identical in both files -- it controls the log folder path.

### 2. Define Your Printers

Replace the `__PRINTERS__` placeholder with your shared printer UNC paths:

```powershell
$sharedPrinters = @(
    "\\printserver.contoso.com\HP-LaserJet-4050",
    "\\printserver.contoso.com\Canon-ImageRunner"
)
```

> ⚠️ The `$sharedPrinters` array must be identical in both files.

## ☁️ Deploying via Intune

These scripts are designed as an **Intune Remediation** pair (detection + remediation).

### Create the Remediation

1. 🌐 Open the [Microsoft Intune admin center](https://intune.microsoft.com).
2. 📂 Navigate to **Devices** > **Remediations**.
3. ➕ Click **+ Create script package**.
4. 📝 Fill in the basics:
   - **Name:** A descriptive name (e.g. `Mount Printer - Office 2nd Floor`).
   - **Description:** Optional.
5. ⚙️ Under **Settings**:
   - **Detection script file:** Upload `detection.ps1`.
   - **Remediation script file:** Upload `remediation.ps1`.
   - **Run this script using the logged-on credentials:** **Yes**
   - **Run script in 64-bit PowerShell:** **Yes**
   - **Enforce script signature check:** Per your organization's policy.
6. 👥 Under **Assignments**, assign to a **user group** or **device group**.
7. 🕐 Under **Schedule**, set to run **Hourly**.
8. ✅ Click **Create**.

### ⚙️ Recommended Intune Settings

| Setting                                | Value         | Reason                                                        |
|----------------------------------------|---------------|---------------------------------------------------------------|
| Run this script using the logged-on credentials | **Yes**       | Printers are mapped per-user, not per-device                  |
| Run script in 64-bit PowerShell        | **Yes**       | Ensures access to the full printer management cmdlets         |
| Schedule                               | **Hourly**    | Re-checks frequently so printers are restored quickly if removed |

### 🔄 How the Remediation Cycle Works

1. Intune runs `detection.ps1` on the scheduled interval.
2. Detection checks if all printers from the `$sharedPrinters` array are installed.
3. If all printers are present, detection exits with code `0` -- Intune marks the device as **compliant** and does nothing.
4. If any printer is missing, detection exits with code `1` -- Intune triggers `remediation.ps1`.
5. Remediation adds the missing printers via `Add-Printer -ConnectionName`.
6. Remediation verifies the result and exits with `0` (success) or `1` (failure).
7. On the next scheduled run, detection confirms the fix.

## 📋 Logging

Both scripts write structured, color-coded logs to the console and to a log file on disk.

### 📁 Log Location

```
C:\ProgramData\IntuneLogs\Scripts\Printer - <ScriptName>\detection.log
C:\ProgramData\IntuneLogs\Scripts\Printer - <ScriptName>\remediation.log
```

### 📄 Example Output

```
2026-02-27 12:00:00 [  Start   ] ======== Detection Script Started ========
2026-02-27 12:00:00 [  Info    ] ComputerName: PC-001 | User: jdoe | Script: Printer - PRT01
2026-02-27 12:00:00 [  Get     ] Retrieving installed printers...
2026-02-27 12:00:01 [  Error   ] Printer '\\print.domain.local\prt01' is missing.
2026-02-27 12:00:01 [  Info    ] Exit Code: 1
2026-02-27 12:00:01 [  End     ] ======== Script Completed ========
```

### 🏷️ Log Tags

| Tag       | Color      | Purpose                                  |
|-----------|------------|------------------------------------------|
| 🟦 `Start`   | Cyan       | Script start marker                  |
| 🔵 `Get`     | Blue       | Data retrieval operations            |
| 🟪 `Run`     | Magenta    | Action execution (e.g. adding a printer) |
| 🟡 `Info`    | Yellow     | General information                  |
| 🟢 `Success` | Green      | Successful operations                |
| 🔴 `Error`   | Red        | Failures or missing resources        |
| 🟠 `Debug`   | DarkYellow | Verbose troubleshooting output       |
| 🟦 `End`     | Cyan       | Script end marker                    |

### 🎛️ Logging Options

These variables are at the top of each script:

| Variable         | Default  | Description                                                   |
|------------------|----------|---------------------------------------------------------------|
| `$log`           | `$true`  | Master switch -- disables all logging when `$false`           |
| `$logDebug`      | `$false` | Enable `Debug`-tagged messages for verbose troubleshooting    |
| `$logGet`        | `$true`  | Show/hide `Get`-tagged messages                               |
| `$logRun`        | `$true`  | Show/hide `Run`-tagged messages                               |
| `$enableLogFile` | `$true`  | Enable or disable writing to the log file                     |

> 💡 Set `$logDebug = $true` to see detailed per-printer checks and system state -- useful when troubleshooting why a printer fails to install.

## 🧪 Testing Locally

Run the scripts directly in a PowerShell terminal before uploading to Intune:

```powershell
# Check if printers are installed
powershell -ExecutionPolicy Bypass -File .\detection.ps1

# Install missing printers
powershell -ExecutionPolicy Bypass -File .\remediation.ps1
```

> 💡 The print server must be reachable and the user must have permission to connect to the shared printer.
