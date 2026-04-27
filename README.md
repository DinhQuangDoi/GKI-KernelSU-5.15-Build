# GKI KernelSU SUSFS

**Personal Build - Android 13 (5.15.178)**

> Forked from [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS)

---

## Features

| Feature | Description |
|:---|:---|
| **KernelSU** | Root solution based on kernel hooks |
| **SUSFS** | Hide root traces, spoof uname, magic mount |
| **ZRAM LZ4KD** | Enhanced memory compression |
| **BBG** | Baseband Guard (anti-brick protection) |
| **Stock Config** | Spoof `/proc/config.gz` to match your device |
| **Droidspaces** | A container runtime that uses Linux kernel namespaces to run full Linux distributions with a real init system (systemd, OpenRC, etc.) as PID 1 |

---

## Credits & Acknowledgments

This project is based on **GKI_KernelSU_SUSFS** by [zzh20188](https://github.com/zzh20188).

| Project | Repository | Description |
|:---|:---|:---|
| **KernelSU** | [kernelsu.org](https://kernelsu.org/) | Kernel-based root solution |
| **SUSFS** | [gitlab.com/simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) | Super User SUS FileSystem |
| **ReSukiSU** | [github.com/ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | KernelSU variant |
| **Baseband Guard** | [github.com/vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard) | BBG anti-brick protection |
| **Re-Kernel** | [github.com/Sakion-Team/Re-Kernel](https://github.com/Sakion-Team/Re-Kernel) | GKI Vendor Hooks driver |
| **AnyKernel3** | [github.com/coolzyd9107/AnyKernel3](https://github.com/coolzyd9107/AnyKernel3) | Flashable kernel template |