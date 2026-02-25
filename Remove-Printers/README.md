# 🖨️ Remove Share Printer – Intune Remediation

A Microsoft Intune Remediation package that detects and removes defined printers from Windows devices. Supports shared (UNC), TCP/IP, and local printers, with wildcard matching.

## 📋 Overview

| Script | Purpose |
|--------|---------|
| **detection.ps1** | 🔍 Detects if any configured printers exist. Exit 1 = remediation needed, Exit 0 = compliant. |
| **remediation.ps1** | 🧹 Removes the detected printers. Runs only when detection returns exit code 1. |

## ✨ Features

- **Exact and wildcard matching** – Use `*` and `?` for pattern-based removal
- **Printer type support** – Shared (UNC), TCP/IP, USB, and other types
- **Logging** – Logs to `%ProgramData%\IntuneLogs\Scripts\` for troubleshooting
- **PowerShell best practices** – Approved verbs, camelCase variables

## ⚙️ Configuration

Edit the `$printersToRemove` array at the top of **both** scripts:

```powershell
$printersToRemove = @(
    "\\PrintServer01\HR-Printer"       # Exact match
    "\\printserver\PRT-HR-*"           # All printers starting with PRT-HR-
    "\\printserver\*"                  # All printers from that print server
    "HR"                               # Local printer named "HR"
)
```

### 🎯 Wildcards

| Pattern | Example matches |
|---------|-----------------|
| `*` | Any number of characters |
| `?` | Single character |
| `\\printserver\*` | All printers from `\\printserver` |
| `\\printserver\PRT-*-01` | `PRT-HR-01`, `PRT-Finance-01`, etc. |

💡 Use the exact display names as shown in **Settings → Bluetooth & devices → Printers & scanners**.

## 🚀 Deployment in Intune

1. In the [Intune admin center](https://go.microsoft.com/fwlink/?linkid=2109431), go to **Devices** → **Manage devices** → **Scripts and remediations**
2. Select **Create script package**
3. **Basics**: Enter a name (e.g., *Remove Share Printer*) and optional description
4. **Settings**:
   - Upload **detection.ps1** as the detection script
   - Upload **remediation.ps1** as the remediation script
   - Save scripts as **UTF-8** (no BOM) before upload
5. **Assignments**: Target the required device or user groups
6. **Review + create**

### ✅ Prerequisites

- Windows 10/11 Enterprise, Professional, or Education
- Intune MDM enrolled or co-managed
- Microsoft Entra (Azure AD) joined or hybrid joined
- [Remediations licensing](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations#licensing) (e.g. Windows E3/E5, M365 E3/E5)

## 📝 Logging & Troubleshooting

Logs are written to:

```
%ProgramData%\IntuneLogs\Scripts\Remove-Printer\
├── detection.log
└── remediation.log
```

🔧 Enable debug logging by setting `$logDebug = $true` in both scripts (in the Logging Setup section).

## 📚 References

- [Use Remediations in Microsoft Intune](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/remediations)
- [Approved Verbs for PowerShell Commands](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)
