# 🖨️ Mount Shared Printers

Mass-generate Intune Remediation scripts for shared network printers from a single CSV file.

## 📁 Project Structure

```
Mount-SharedPrinters/
├── template/
│   ├── detection.ps1        # Detection template with placeholders
│   ├── remediation.ps1      # Remediation template with placeholders
│   └── README.md            # Manual setup & Intune deployment guide
├── printers/                # Generated output (created by package.ps1)
│   └── <ScriptName>/
│       ├── detection.ps1
│       └── remediation.ps1
├── package.ps1              # Generates scripts from CSV + templates
├── printers.csv             # Printer definitions
└── README.md
```

## 🚀 Usage

### 1. Edit the CSV

Open `printers.csv` and add one row per printer group. Separate multiple printer names with `;`.

```csv
ScriptName,PrintServer,Printers
PRT01,print.domain.local,prt01;prt02
PRT02,print.domain.local,prt03
Office-3F,printserver.contoso.com,HP-LaserJet-4050;Canon-ImageRunner
```

| Column        | Description                                                  |
|---------------|--------------------------------------------------------------|
| `ScriptName`  | Unique identifier for this group -- becomes the output folder name and part of `$scriptName` (`Printer - <ScriptName>`) in the generated scripts |
| `PrintServer` | FQDN of the print server                                    |
| `Printers`    | Semicolon-separated list of shared printer names             |

### 2. Run the Package Script

```powershell
powershell -ExecutionPolicy Bypass -File .\package.ps1
```

The script reads `printers.csv`, replaces the `__SCRIPTNAME__` and `__PRINTERS__` placeholders in the templates, and writes ready-to-upload scripts to `printers/<ScriptName>/`.

For the example CSV above, this generates:

```
printers/
├── PRT01/
│   ├── detection.ps1         # \\print.domain.local\prt01, \prt02
│   └── remediation.ps1
├── PRT02/
│   ├── detection.ps1         # \\print.domain.local\prt03
│   └── remediation.ps1
└── Office-3F/
    ├── detection.ps1         # \\printserver.contoso.com\HP-LaserJet-4050, \Canon-ImageRunner
    └── remediation.ps1
```

### 3. Upload to Intune

Upload each generated `detection.ps1` + `remediation.ps1` pair as an Intune Remediation. See the [template README](template/README.md) for detailed Intune deployment steps.

## 📋 Package Script Logging

`package.ps1` logs to `logs/package.log` and to the console.

```
2026-02-27 12:00:00 [  Start   ] ======== Deploy Script Started ========
2026-02-27 12:00:00 [  Get     ] Reading printer definitions from: .\printers.csv
2026-02-27 12:00:00 [  Info    ] Found 3 printer definition(s)
2026-02-27 12:00:00 [  Run     ] Processing 'PRT01' (Server: print.domain.local)
2026-02-27 12:00:00 [  Success ] Created detection script:  .\printers\PRT01\detection.ps1
2026-02-27 12:00:00 [  Success ] Created remediation script: .\printers\PRT01\remediation.ps1
2026-02-27 12:00:00 [  Info    ] Generation complete: 3/3 succeeded, 0 failed
2026-02-27 12:00:00 [  End     ] ======== Script Completed ========
```

Set `$logDebug = $true` in `package.ps1` to see the full generated printer arrays and raw CSV values for troubleshooting.

## 📌 Requirements

- 💻 Windows 10 / 11
- 🌐 Network access to the print server (for the generated scripts)
- ☁️ Microsoft Intune (for deployment)
