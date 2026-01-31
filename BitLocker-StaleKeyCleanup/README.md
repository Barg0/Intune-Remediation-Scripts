# 🔐 BitLocker Stale Key Cleanup - Intune Remediation

Removes **orphaned OS volume** BitLocker recovery keys from Microsoft Entra ID via Intune Remediation. Only stale keys for the **operating system drive** are deleted; data drive keys are never touched. Current/active keys are always preserved.

## 📁 Contents

- `detection.ps1` – Detection script (runs first; exits 1 when orphaned OS keys exist)
- `remediation.ps1` – Remediation script (removes orphaned OS keys when triggered)
- `README.md` – This file

## 📖 Background

Microsoft Entra ID supports a **maximum of 200 BitLocker recovery keys per device**. When this limit is reached:
- New recovery keys cannot be escrowed
- Silent BitLocker encryption fails (if policy requires key backup before enabling)
- Devices can end up unencrypted until manually fixed

This solution proactively cleans up **orphaned OS volume keys** (from previous key rotations) before hitting the limit. Data drive keys (fixed/removable) are intentionally left in Entra.

## 🎯 Scope: OS Volume Keys Only

| Action | OS Volume Keys | Data Drive Keys (Fixed/Removable) |
|--------|----------------|-----------------------------------|
| **Delete orphaned** | Yes | No – left in Entra |
| **Keep current** | Yes | Yes – never touched |

- **Orphaned** = key in Entra that does not match any current recovery protector on the device
- **Drive type** is determined by the API response (`volumeType`: 1=OS, 2=FixedData, 3=Removable)
- Keys without `volumeType` in the API response are skipped (not deleted)

## ⚙️ How It Works

Based on the [Patch My PC research](https://patchmypc.com/blog/bitlocker-recovery-key-cleanup/):

1. **Device-side API**: Windows uses an undocumented Enterprise Registration API (`enterpriseregistration.windows.net`) for BitLocker key operations
2. **Authentication**: The device authenticates using its **MS-Organization-Access** certificate (present on Entra-joined devices)
3. **Batch limit**: The API only allows **16 keys per DELETE request** – the scripts handle batching
4. **Orphaned OS keys only**: Only keys that are orphaned **and** have `volumeType` = 1 (OS) are deleted
5. **Drive type from API**: Drive type is read from the API response (`volumeType`/`vol`), not from the local device
6. **Case-insensitive KID comparison**: The device returns Key IDs in uppercase, the API in lowercase; comparison uses case-insensitive logic so the same key is correctly recognized
7. **No early exit**: If the device has no BitLocker volumes or no recovery protectors, the script still calls the API. Any orphaned OS keys in Entra are deleted (e.g. after decryption or reinstall)

### 🔄 Execution Flow

1. Resolve MS-Organization-Access certificate and device ID
2. Collect current recovery protector KIDs from **all** BitLocker-protected volumes (OS + data drives)
3. Call the API to retrieve all keys for the device
4. Identify orphaned keys where `volumeType` = 1 (OS)
5. Delete orphaned OS keys in batches of 16

## 🔌 API Details (from Patch My PC)

The scripts use the Enterprise Registration API:

- **URL**: `https://enterpriseregistration.windows.net/manage/common/bitlocker/{deviceId}?api-version=1.2`
- **Path**: `manage/common/bitlocker` – uses `common`, not tenant-specific path
- **Auth**: MS-Organization-Access certificate (device TLS)
- **Headers**: `User-Agent: BitLocker/10.0 (Windows)`, `Accept: application/json`, `ocp-adrs-client-name: windows`, `ocp-adrs-client-version: 10.0`
- **Response**: `{ keys: [ { kid: "...", volumeType: 1 }, ... ] }` – `volumeType` (1=OS, 2=FixedData, 3=Removable) determines which orphaned keys are deleted
- **DELETE**: Same URL, body `{"kids": [...]}`, max 16 keys per request

## ✅ Requirements

- **Entra ID joined** (or Hybrid Entra joined) device
- **MS-Organization-Access** certificate in `LocalMachine\My` (auto-provisioned during join)
- **Intune managed** (for remediation deployment)
- **Run as System** (default for Intune Remediation)

BitLocker does not need to be currently enabled; the script will still remove orphaned OS keys left from previously encrypted drives.

## 🚀 Intune Setup

### 1️⃣ Create the Remediation

1. Go to **Microsoft Intune** → **Devices** → **Remediations**
2. Click **Create script package**
3. **Basics**:
   - Name: `BitLocker Stale Recovery Key Cleanup`
   - Description: `Removes orphaned OS volume BitLocker keys from Entra ID to prevent 200-key limit issues`
4. **Settings**:
   - **Detection script file**: Upload `detection.ps1`
   - **Remediation script file**: Upload `remediation.ps1`
   - **Run this script using the logged-on credentials**: **No** (must run as System to access machine cert store)
   - **Enforce script signature check**: **No** (unless you sign the scripts)
5. Assign to your device groups (e.g., all Windows devices with BitLocker)

### 2️⃣ Schedule

- Configure a schedule (e.g., daily or weekly)
- Remediation runs only when detection returns non-compliant (exit 1)

## 📋 Script Behavior

| Script        | Exit 0                      | Exit 1                      |
|---------------|-----------------------------|-----------------------------|
| **Detection** | Compliant (no action)       | Non-compliant (run fix)     |
| **Remediation** | Success                  | Error (retry on next run)   |

**Detection** exits 1 when:
- At least one **orphaned OS volume key** exists in Entra (not on any current volume **and** `volumeType` = 1)

**Detection** exits 0 (compliant) when:
- No orphaned OS keys exist, or
- API returns no keys, or
- Cert/API errors (to avoid remediation loops)

**Remediation** removes only orphaned OS volume keys in batches of 16. Data drive keys are never modified.

## 📝 Logging

Logs are written to:
- `%ProgramData%\IntuneLogs\Scripts\BitLocker-StaleKeyCleanup\detection.log`
- `%ProgramData%\IntuneLogs\Scripts\BitLocker-StaleKeyCleanup\remediation.log`

### 🔍 Troubleshooting / Debug Logging

Set `$logDebug = $true` at the top of each script for verbose `[Debug]` logs:
- MDM enrollment status and enrollment UPN
- All BitLocker volumes and their current KIDs
- Drive type per key from API (OS, FixedData, Removable)
- Certificate thumbprint and subject
- Device ID
- API URIs, request/response parsing
- Orphaned non-OS keys skipped (with reason)
- Batch delete operations

## 🟢 Viability

**Client remediation is viable.** The scripts use the device-side Enterprise Registration API (`manage/common/bitlocker/{deviceId}`) with the MS-Organization-Access certificate and BitLocker-specific headers, as documented in the [Patch My PC article](https://patchmypc.com/blog/bitlocker-recovery-key-cleanup/). **Graph cannot delete BitLocker keys** – there is no delete API.

## ⚠️ Limitations & Notes

1. **OS volume keys only**: Orphaned data drive keys (FixedData, Removable) are intentionally left in Entra.

2. **Drive type from API**: If the API omits `volumeType` for a key, that key is not deleted (conservative).

3. **Undocumented API**: The Enterprise Registration BitLocker endpoints are not officially documented. The scripts use the structure from the Patch My PC article (`manage/common/bitlocker`, api-version 1.2, BitLocker headers).

4. **National clouds**: For GCC/GCC High/China, the base host may differ (e.g., `enterpriseregistration.windows.us`). Update the URL in both scripts if needed.

## 🙏 Thanks

Many thanks to **[Patch My PC](https://patchmypc.com)** for their research and [blog post](https://patchmypc.com/blog/bitlocker-recovery-key-cleanup/) on BitLocker stale key cleanup. Their work documenting the undocumented Enterprise Registration API, the correct URL structure (`manage/common/bitlocker`), required headers, and MS-Organization-Access certificate authentication made this solution possible.

## 📚 References

- [BitLocker Stale Recovery Key Cleanup – Patch My PC](https://patchmypc.com/blog/bitlocker-recovery-key-cleanup/)
- [Intune Remediations – Microsoft Docs](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remediations)
- [List recoveryKeys – Microsoft Graph](https://learn.microsoft.com/en-us/graph/api/bitlocker-list-recoverykeys)
