# 🛠️ Templates - Manual Usage

These template scripts are designed as **Intune Proactive Remediation** script pairs for setting friendly labels on network drives mapped via the [Drive Mapping ADMX](https://call4cloud.nl/intune-drive-mappings-admx-drive-letters/).

## 📖 Background

When network drives are mounted through the Intune Drive Mapping ADMX, Windows displays the raw UNC path (e.g. `\\files.domain.local\Marketing$`) as the drive name in File Explorer 😩. To show a friendly label instead, a `_LabelFromReg` registry value must be set under:

```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\##server#share
```

These scripts automate that through Intune's remediation framework 🎉.

## 📄 Template Files

| File | Purpose |
|---|---|
| 🔍 `detection.ps1` | Checks whether the `_LabelFromReg` value exists and matches the desired label. Exits `0` if correct, `1` if missing or mismatched. |
| 🔧 `remediation.ps1` | Sets the `_LabelFromReg` value to the desired label, then validates the write. Exits `0` on success, `1` on failure. |

## 🔤 Placeholders

Both templates contain three placeholders that must be replaced before deployment:

| Placeholder | Description | Example |
|---|---|---|
| `__DRIVE_LETTER__` | The mapped drive letter | `M` |
| `__DRIVE_PATH__` | The full UNC path to the share | `\\files.domain.local\Marketing$` |
| `__DRIVE_LABEL__` | The friendly label to display | `Marketing` |

## ✏️ Manual Steps

If you want to create scripts for a single drive without using `package.ps1`:

1. 📋 **Copy both templates** to a new folder (e.g. `M/`).

2. ✏️ **Open each file** and replace the placeholders with your values:

   ```powershell
   # Before
   $scriptName = "Network Drive - Label - __DRIVE_LETTER__"
   $networkDrivePath = "__DRIVE_PATH__"
   $desiredLabel = "__DRIVE_LABEL__"

   # After
   $scriptName = "Network Drive - Label - M"
   $networkDrivePath = "\\files.domain.local\Marketing$"
   $desiredLabel = "Marketing"
   ```

3. ☁️ **Upload to Intune** as a Proactive Remediation:
   - 🌐 Go to **Devices > Remediations** (or **Reports > Endpoint analytics > Proactive remediations**).
   - ➕ Click **Create script package**.
   - 🔍 Upload `detection.ps1` as the detection script.
   - 🔧 Upload `remediation.ps1` as the remediation script.
   - 👤 Set **Run this script using the logged-on credentials** to **Yes** (the scripts write to `HKCU`).
   - 💻 Set **Run script in 64-bit PowerShell** to **Yes**.
   - 👥 Assign to a user or device group.

## 🔄 How Detection & Remediation Works

```
🔍 Detection runs on schedule
        │
        ├── Registry path not found? ──> ⏳ Waits up to 20 min (10 retries x 2 min)
        │                                    │
        │                              Still missing? ──> ❌ Exit 1 (triggers remediation)
        │
        ├── _LabelFromReg missing? ──> ❌ Exit 1 (triggers remediation)
        │
        ├── _LabelFromReg != desired? ──> ❌ Exit 1 (triggers remediation)
        │
        └── _LabelFromReg == desired ──> ✅ Exit 0 (compliant, no action)

🔧 Remediation (only runs after detection exits 1)
        │
        ├── Sets _LabelFromReg to desired label
        │
        ├── Validates the write
        │       │
        │       ├── Match ──> ✅ Exit 0 (success)
        │       └── Mismatch ──> ❌ Exit 1 (failure)
        │
        └── Set-ItemProperty fails ──> ❌ Exit 1 (failure)
```

## 📝 Logging

Both scripts write logs to:

```
%ProgramData%\IntuneLogs\Scripts\%USERNAME%\Network Drive - Label - <DriveLetter>\
```

- 🔍 `detection.log` - detection script output
- 🔧 `remediation.log` - remediation script output
