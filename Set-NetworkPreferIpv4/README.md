# 🔄 Prefer IPv4 over IPv6 – Proactive Remediation

An **Intune Proactive Remediation** package that keeps the **prefer IPv4 over IPv6** setting consistent across your devices. If a Windows Update or other process changes the registry value, remediation will restore it on the next scheduled run.

---

## 📦 What's Included

| File | Purpose |
|------|---------|
| **detection.ps1** | Checks if `DisabledComponents` = 32 (compliant) |
| **remediation.ps1** | Sets the registry value when detection fails |
| **README.md** | This file |

---

## 🎯 How It Works

1. **Detection script** runs first:
   - Reads `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\DisabledComponents`
   - **Exit 0** → Value is 32 (compliant) → No remediation
   - **Exit 1** → Value missing or different → Remediation runs

2. **Remediation script** runs only when detection returns Exit 1:
   - Sets `DisabledComponents` to 32 (DWord)
   - Validates the change
   - **Exit 0** → Success  
   - **Exit 1** → Failure (e.g. permission error)

---

## 🚀 Deploy in Microsoft Intune

### Step 1: Create the Remediation

1. Sign in to **Microsoft Intune** → **Reports** → **Endpoint analytics** → **Proactive remediations**
2. Click **Create script package**
3. Enter a name (e.g. `Prefer IPv4 over IPv6`)

### Step 2: Upload Scripts

1. **Detection script file:** Upload `detection.ps1`
2. **Remediation script file:** Upload `remediation.ps1`

### Step 3: Assign & Schedule

1. Assign to your device groups (User or Device)
2. Set a schedule (e.g. **Daily**) so it can catch changes after Windows Updates
3. Save and deploy

---

## 📅 Recommended Schedule

| Schedule | Use case |
|----------|----------|
| **Daily** | Balance between prompt remediation and overhead |
| **Every 8 hours** | Faster response to Windows Updates |
| **Weekly** | Lower overhead, slower recovery |

---

## 📝 Logging

Both scripts write to the same log directory with separate log files:

| Script       | Log path                                                                 |
|--------------|---------------------------------------------------------------------------|
| **Detection**   | `%ProgramData%\IntuneLogs\Scripts\Set-NetworkPreferIpv4\detection.log`   |
| **Remediation** | `%ProgramData%\IntuneLogs\Scripts\Set-NetworkPreferIpv4\remediation.log` |

Script output is also available in the Intune portal under the remediation run details.

---

## ✅ Exit Codes

### Detection script

| Exit Code | Meaning |
|-----------|---------|
| `0` | Compliant – `DisabledComponents` = 32 |
| `1` | Non-compliant – value missing or different |

### Remediation script

| Exit Code | Meaning |
|-----------|---------|
| `0` | Success – value set and validated |
| `1` | Failure – set or validation failed |

---

## 🔗 Related

- **Platform script** (`Set-NetworkPreferIpv4.ps1` in the parent folder) – for one-time deployment via Intune Platform Scripts
- This remediation package – for ongoing enforcement via Proactive Remediation

Use both for consistent initial configuration and ongoing compliance.
