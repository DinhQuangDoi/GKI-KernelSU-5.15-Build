# GKI KernelSU SUSFS

**Personal Build - Android 13 (5.15.178)**

Automated GKI Kernel Build with KernelSU + SUSFS + ZRAM + BBG integrated.

---

## Features

| Feature | Description |
|:---|:---|
| **KernelSU** | Root solution based on kernel hooks |
| **SUSFS** | Hide root traces, spoof uname, magic mount |
| **ZRAM LZ4KD** | Enhanced memory compression |
| **BBG** | Baseband Guard (anti-brick protection) |
| **Stock Config** | Spoof `/proc/config.gz` to match your device |

---

## Quick Start

### 1. Fork This Repository

Click **Fork** on GitHub, then clone your forked repo locally.

### 2. Add Your Stock Config (Optional)

```bash
# Get from your device (running stock ROM)
adb pull /proc/config.gz

# Decompress and rename
gunzip config.gz
mv config stock_defconfig

# Upload to config/ folder and commit
git add config/stock_defconfig
git commit -m "Add stock config"
git push
```

### 3. Run Workflow

1. Go to **Actions** tab
2. Select **Build Kernel** workflow
3. Click **Run workflow**
4. Configure options:
   - `use_zram`: Enable ZRAM compression (default: true)
   - `use_bbg`: Enable Baseband Guard (default: true)
   - `use_rekernel`: Enable Re-Kernel driver (default: false)
   - `cancel_susfs`: Disable SUSFS (default: false)
   - `kernelsu_branch`: Custom KSU branch/commit (optional)
   - `version`: Custom version name (optional)

### 4. Download Build

After build completes, download from **Actions** > **Build Kernel** > Artifacts.

---

## Build Configuration Options

| Option | Default | Description |
|:---|:---:|:---|
| `use_zram` | true | Enable ZRAM LZ4KD compression |
| `use_bbg` | true | Enable BBG anti-brick protection |
| `use_rekernel` | false | Enable Re-Kernel driver |
| `cancel_susfs` | false | Disable SUSFS completely |
| `kernelsu_branch` | main | KSU branch or commit hash |
| `version` | auto | Custom version suffix |

---

## Custom Commit Pinning

When upstream updates cause build failures, you can pin specific commits.

### Get Commit Hash

- **SUSFS**: https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android13-5.15
- **SukiSU**: https://github.com/ReSukiSU/ReSukiSU/commits/main

### Configure

Edit `config/config`:

```ini
# Enable custom commits
custom=true

# SUSFS commit hash
gki-android13-5.15=abc123def456

# SukiSU commit hash
sukisu=
```

> Empty value = use latest commit of that branch.

---

## Common Build Failures

If build fails with SUSFS/KernelSU out of sync errors:

```
SukiSU builtin branch: https://github.com/SukiSU-Ultra/SukiSU-Ultra/tree/builtin
SUSFS gki-android13-5.15: https://gitlab.com/simonpunk/susfs4ksu/-/tree/gki-android13-5.15
```

Wait for SukiSU to sync with latest SUSFS commit, or manually pin compatible versions.

---

## Recommended Modules

| Module | Repository |
|:---|:---|
| LSPosed-Irena | https://github.com/re-zero001/LSPosed-Irena |
| Zygisk Next | https://github.com/Dr-TSNG/ZygiskNext |
| TrickyStore | https://github.com/5ec1cff/TrickyStore |

---

## Kernel Info

| Item | Value |
|:---|:---|
| Android Version | 13 |
| Kernel Version | 5.15.178 |
| OS Patch Level | 2025-03 |
| KSU Variant | ReSukiSU |

---

## Repository Structure

```
.github/workflows/
├── main.yml              # Entry point workflow
├── kernel-a13-5-15.yml   # Android 13 build config
└── build.yml            # Core build process

config/
├── config               # Custom commit pinning
└── stock_defconfig      # Your stock kernel config

data/android13/
└── 5.15.json            # Kernel version data

zram/                     # ZRAM/LZ4KD patches
```

---

## Disclaimer

> **Risk Warning**: This project integrates multiple upstream components. Before flashing:
> 1. Backup your stock boot image
> 2. Ensure you can restore to stock kernel
> 3. Use at your own risk