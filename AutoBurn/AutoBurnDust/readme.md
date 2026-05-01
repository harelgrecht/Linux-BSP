# DUST Auto-Programming Guide

> **Complete guide for programming the DUST board** (Xilinx Zynq-7000) with a
> custom PetaLinux image and Linux rootfs. Follow the steps in order.

---

## Table of Contents

1. [What This Does](#1-what-this-does)
2. [Host PC Setup (one-time)](#2-host-pc-setup-one-time)
3. [Hardware Setup](#3-hardware-setup)
4. [File Organization — Versions](#4-file-organization--versions)
5. [Adding a New Version](#5-adding-a-new-version)
6. [Programming Sequence (Step-by-Step)](#6-programming-sequence-step-by-step)
7. [Script Reference](#7-script-reference)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. What This Does

The DUST board (Zynq-7000) uses two storage devices:

| Storage | What goes there | How it's programmed |
|---------|----------------|---------------------|
| **QSPI Flash** (16 MiB, `w25q128`) | `BOOT.BIN` — FSBL + U-Boot + FPGA bitstream | Script 1 via JTAG |
| **eMMC p1** (`/dev/mmcblk1p1`, FAT32, 1 GiB) | `image.ub` + `system.bit` | Script 2 via SSH |
| **eMMC p2** (`/dev/mmcblk1p2`, ext4, rest) | Linux rootfs + kernel modules | Script 3 via SSH |

> ⚠️ **DUST vs MUST:** On DUST the eMMC is `/dev/mmcblk1` (not `mmcblk0`).
> The SD card / boot medium is `mmcblk0`. Do not confuse the two.

```
0_setupTftp.sh      → Points TFTP server at your version folder
1_burnFlash.sh      → Flashes BOOT.BIN to QSPI via JTAG  (Zynq-7000 FSBL)
2_burnEmmcBoot.sh   → Writes image.ub + system.bit to eMMC p1 via SSH
3_burnEmmcRootfs.sh → Writes Linux rootfs to eMMC p2 via SSH
4_packageRootfs.sh  → Packages the live eMMC rootfs back to a tarball
```

---

## 2. Host PC Setup (one-time)

```bash
sudo apt update
sudo apt install -y sshpass tftpd-hpa openssh-client
```

| Package | Why |
|---------|-----|
| `sshpass` | Non-interactive SSH password for scripts 2–4 |
| `tftpd-hpa` | TFTP server for U-Boot ramdisk boot |
| `openssh-client` | SSH & SCP |

### Vitis / Vivado

Script 1 needs `program_flash` from the **Xilinx Vitis or Vivado toolchain (2023.1)**.

After installing, open `1_burnFlash.sh` and set:
```bash
vitisInstallDir="/home/yourname/xilinx/Vitis/2023.1"
```

---

## 3. Hardware Setup

### What you need

- DUST carrier board + Zynq-7000 SOM
- **JTAG cable** — connected to JTAG header (needed for Script 1 only)
- **Ethernet cable** — between host PC and DUST board (needed for Scripts 2–4)
- **USB-to-UART cable** (recommended) — for U-Boot console access
  - 115200 baud: `sudo tio /dev/ttyUSB0`

### Boot Mode

| Mode | When to use |
|------|-------------|
| **JTAG** | Script 1 (flash programming) |
| **QSPI** | After flashing — loads U-Boot |
| **eMMC** | After all scripts — boots Linux |

### Network Setup

- Board IP: `192.168.0.10` (set in scripts)
- Host IP must be on same subnet, e.g. `192.168.0.1`

```bash
sudo ip addr add 192.168.0.1/24 dev eth0   # replace eth0 with your interface
```

### Important: eMMC vs SD on DUST

```
/dev/mmcblk0  →  SD card (boot medium, NOT the target for scripts 2/3)
/dev/mmcblk1  →  eMMC   (this is what we program)
```

---

## 4. File Organization — Versions

```
AutoBurnDust/
├── 0_setupTftp.sh
├── 1_burnFlash.sh
├── 2_burnEmmcBoot.sh
├── 3_burnEmmcRootfs.sh
├── 4_packageRootfs.sh
├── readme.md
│
├── dustV1.1/                          ← version directory
│   ├── BOOT.BIN                       ← from PetaLinux build
│   ├── zynq_fsbl.elf                  ← Zynq-7000 FSBL (NOT zynqmp_fsbl.elf)
│   ├── image.ub                       ← from PetaLinux build
│   ├── system.bit                     ← from PetaLinux build
│   ├── rootfs.cpio.gz.u-boot          ← ramdisk for TFTP boot
│   ├── rootfs-*.tar.gz                ← Linux rootfs tarball
│   └── modules--*.tgz                 ← kernel modules (optional)
│
└── dustV1.2/                          ← next version
    └── ...
```

### Key Difference from MUST

| File | MUST (KR260 / ZynqMP) | DUST (Zynq-7000) |
|------|----------------------|-----------------|
| FSBL ELF | `zynqmp_fsbl.elf` | **`zynq_fsbl.elf`** |
| eMMC device | `/dev/mmcblk0` | **`/dev/mmcblk1`** |
| Board user | `petalinux` | **`dust`** |

---

## 5. Adding a New Version

### Step 1 — Create the version directory

```bash
mkdir dustV1.2
```

### Step 2 — Copy PetaLinux build artifacts

```bash
PETALINUX_WS="/path/to/your/petalinux/project"
VER="dustV1.2"

cp "${PETALINUX_WS}/images/linux/BOOT.bin"              ${VER}/BOOT.BIN
cp "${PETALINUX_WS}/images/linux/zynq_fsbl.elf"         ${VER}/    # Zynq-7000 FSBL
cp "${PETALINUX_WS}/images/linux/image.ub"              ${VER}/
cp "${PETALINUX_WS}/images/linux/system.bit"            ${VER}/
cp "${PETALINUX_WS}/images/linux/rootfs.cpio.gz.u-boot" ${VER}/

# Kernel modules (glob)
cp "${PETALINUX_WS}"/build/tmp/deploy/images/zynq*/modules--*.tgz ${VER}/
```

### Step 3 — Copy rootfs tarball

```bash
cp /path/to/rootfs-DUST-*.tar.gz dustV1.2/
```

### Step 4 — Verify

```bash
ls -lh dustV1.2/
# Must contain: BOOT.BIN  zynq_fsbl.elf  image.ub  system.bit
#               rootfs.cpio.gz.u-boot  rootfs-*.tar.gz
```

### Step 5 — Run scripts

```bash
./0_setupTftp.sh      --ver dustV1.2
./1_burnFlash.sh      --ver dustV1.2
./2_burnEmmcBoot.sh   --ver dustV1.2
./3_burnEmmcRootfs.sh --ver dustV1.2
```

---

## 6. Programming Sequence (Step-by-Step)

### Step 0 — Configure TFTP

```bash
./0_setupTftp.sh --ver dustV1.1
```

Points the TFTP server (`tftpd-hpa`) at your version directory so U-Boot can
load the ramdisk and FPGA bitstream over the network.

---

### Step 1 — Program QSPI Flash

**Before running:**
1. Set boot-mode switches to **JTAG**
2. Connect JTAG cable
3. Power on board

```bash
./1_burnFlash.sh --ver dustV1.1
```

**After:**
1. Set boot-mode switches to **QSPI**
2. Power-cycle the board

> Flash chip: `w25q128` (16 MiB). Uses `zynq_fsbl.elf` to init the Zynq-7000 PS over JTAG.

---

### Step 2 — Program eMMC Boot Partition

**Before running:** Board must be running the **PetaLinux ramdisk** over TFTP.

From the U-Boot console (UART):
```
run load_fpga_tftp
run load_ramdisk_tftp
```

Wait for the board to boot into the ramdisk (login prompt on UART), then:

```bash
./2_burnEmmcBoot.sh --ver dustV1.1
```

**Full mode** (default) — works on brand-new SOMs with no partition table:
- Wipes the partition table with `dd`
- Creates p1 (1 GiB FAT32) + p2 (rest)
- Formats p1 and copies `image.ub` + `system.bit`

**Partial update** (existing board, update one file only):
```bash
./2_burnEmmcBoot.sh --ver dustV1.1 --only image   # Update image.ub only
./2_burnEmmcBoot.sh --ver dustV1.1 --only bit     # Update system.bit only
```

> ⚠️ Full mode re-partitions the **entire eMMC** — all existing data is erased.

---

### Step 3 — Program eMMC Root Partition

Board must **still be in ramdisk** (do not power-cycle between steps 2 and 3).

```bash
./3_burnEmmcRootfs.sh --ver dustV1.1
```

- Formats p2 as ext4
- Extracts rootfs tarball into p2
- Installs kernel modules (if present)

> This step transfers a large file and will take **several minutes**.

**After:**
1. Set boot-mode switches to **eMMC**
2. Power-cycle the board → boots Linux 🎉

---

### Step 4 — Package Running RootFS (optional)

If you want to capture the current eMMC rootfs as a tarball (e.g. after customising
a running system):

Board must be in **ramdisk** (not booted from eMMC):

```bash
./4_packageRootfs.sh --ver dustV1.2          # Save into dustV1.2/ directory
./4_packageRootfs.sh --name my-backup.tar.gz # Save with custom name
```

Progress is shown every 3 seconds as the tarball grows.

---

## 7. Script Reference

### Board Credentials

Set at the top of scripts 2, 3, 4:

```bash
boardIp="192.168.0.10"
boardUser="dust"
boardPassword="root"
boardSudoPassword="root"
```

### `--ver` Argument

| Script | Files loaded from version dir |
|--------|-------------------------------|
| `0_setupTftp.sh` | Entire directory served via TFTP |
| `1_burnFlash.sh` | `BOOT.BIN`, `zynq_fsbl.elf` |
| `2_burnEmmcBoot.sh` | `image.ub`, `system.bit` |
| `3_burnEmmcRootfs.sh` | `*.tar.gz` (auto-glob), `modules--*.tgz` (auto-glob) |

### `--only` Argument (script 2 only)

```bash
--only image   # Update image.ub only, mount existing p1, no repartition
--only bit     # Update system.bit only, mount existing p1, no repartition
```

### `--help`

Every script accepts `--help`:
```bash
./1_burnFlash.sh --help
```

---

## 8. Troubleshooting

### `sshpass: command not found`
```bash
sudo apt install -y sshpass
```

### `Board at 192.168.0.10 is NOT reachable`
The pre-flight check failed. In order:
1. Is the Ethernet cable plugged in?
2. Did U-Boot successfully run `load_fpga_tftp` and `load_ramdisk_tftp`?
3. Is your host on the same subnet?
   ```bash
   sudo ip addr add 192.168.0.1/24 dev eth0
   ```

### `SSH connection failed`
1. Did the ramdisk fully boot? Check UART for login prompt.
2. Verify `boardUser="dust"` and `boardPassword="root"` in the script config.

### `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`
The ramdisk regenerates SSH host keys on every boot. The scripts handle this
automatically. If you still see it:
```bash
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.0.10
```

### TFTP fails in U-Boot
```bash
./0_setupTftp.sh --ver dustV1.1
sudo systemctl status tftpd-hpa
```

### Script 2 fails with `Could not mount /dev/mmcblk1p1`
You used `--only` on a board that hasn't been fully partitioned yet.
Run without `--only` first to do a full repartition:
```bash
./2_burnEmmcBoot.sh --ver dustV1.1
```

### Wrong eMMC device
On DUST, eMMC is **`/dev/mmcblk1`**. If you see unexpected behavior,
SSH into the board and verify:
```bash
lsblk
# mmcblk0  → SD card
# mmcblk1  → eMMC  ← this is what we program
```

### `No *.tar.gz rootfs tarball found in version dir`
```bash
ls dustV1.1/*.tar.gz
```
Make sure the rootfs tarball is in the version directory with `.tar.gz` extension.
