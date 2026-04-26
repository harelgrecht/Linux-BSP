# KR260 Auto-Programming Guide

> **Complete guide for programming the Kria KR260 SOM** with a custom PetaLinux
> image and Ubuntu rootfs. Follow the steps below in order — even if you have
> never done this before.

---

## Table of Contents

1. [What This Does](#1-what-this-does)
2. [Host PC Setup (one-time)](#2-host-pc-setup-one-time)
3. [Hardware Setup](#3-hardware-setup)
4. [File Organization — Versions](#4-file-organization--versions)
5. [Adding a New Version](#5-adding-a-new-version)
6. [Programming Sequence (Step-by-Step)](#6-programming-sequence-step-by-step)
   - [Step 0 — Configure TFTP](#step-0--configure-tftp)
   - [Step 1 — Program QSPI Flash](#step-1--program-qspi-flash)
   - [Step 2 — Program eMMC Boot Partition](#step-2--program-emmc-boot-partition)
   - [Step 3 — Program eMMC Root Partition](#step-3--program-emmc-root-partition)
7. [Script Reference](#7-script-reference)
8. [Troubleshooting](#8-troubleshooting)
9. [TODO — Planned Features](#9-todo--planned-features)

---

## 1. What This Does

The KR260 board needs two storage devices programmed before it can boot Linux:

| Storage | What goes there | How it's programmed |
|---------|----------------|---------------------|
| **QSPI Flash** | `BOOT.BIN` — U-Boot + FSBL + PMUFW | Script 1 via JTAG |
| **eMMC p1** (FAT32, 1 GiB) | `image.ub` + `system.bit` — Linux kernel + FPGA bitstream | Script 2 via SSH |
| **eMMC p2** (ext4, rest) | Ubuntu rootfs + kernel modules | Script 3 via SSH |

The four scripts in this folder automate all of that from your host PC.

```
0_setupTftp.sh      → Points TFTP server at your version folder
1_burnFlash.sh      → Flashes BOOT.BIN to QSPI via JTAG
2_burnEmmcBoot.sh   → Writes image.ub + system.bit to eMMC p1 via SSH
3_burnEmmcRootfs.sh → Writes Ubuntu rootfs to eMMC p2 via SSH
```

---

## 2. Host PC Setup (one-time)

Run these commands once on your Ubuntu/Debian host machine.

### 2.1 Install required packages

```bash
sudo apt update
sudo apt install -y sshpass tftpd-hpa openssh-client
```

| Package | Why |
|---------|-----|
| `sshpass` | Used by scripts 2 & 3 to pass the board SSH password non-interactively |
| `tftpd-hpa` | TFTP server used to serve ramdisk & FPGA bitstream to the board |
| `openssh-client` | SSH & SCP for scripts 2 & 3 |

### 2.2 Install Vitis / Vivado

Script 1 needs `program_flash` which is part of the **Xilinx Vitis or Vivado toolchain**.

- Download from: https://www.xilinx.com/support/download.html
- Supported version: **2023.1** (other versions may work)
- Default install path: `/home/<user>/xilinx/Vitis/2023.1`

After installing, open `1_burnFlash.sh` and set:
```bash
vitisInstallDir="/home/user/xilinx/Vitis/2023.1"   # ← your actual path
```

### 2.3 Install TFTP server (if not already done)

```bash
sudo apt install -y tftpd-hpa

# Verify service is running:
sudo systemctl status tftpd-hpa
```

---

## 3. Hardware Setup

### What you need

- KR260 carrier board + SOM
- **JTAG cable** (Digilent JTAG-HS2, SmartLynq, or onboard JTAG-USB)
  - Connected to the JTAG header on the KR260
  - Required **only** for Script 1 (flash programming)
- **Ethernet cable** between your host PC and the KR260
  - Required for Scripts 2 & 3
- **USB-to-UART cable** (optional but recommended for U-Boot console access)
  - Connect to `/dev/ttyUSB0` on the host (115200 baud)
  - Access with: `sudo tio /dev/ttyUSB0` or `minicom -b 115200 -D /dev/ttyUSB0`

### Boot Mode Switches

The KR260 boot mode is controlled by physical switches on the carrier board.

| Mode | When to use |
|------|-------------|
| **JTAG** | Required for Script 1 (flash programming) |
| **QSPI** | Normal operation after flash is programmed |
| **eMMC** | After all scripts complete — boots Ubuntu |

> Consult the KR260 carrier card user guide for the exact switch positions.

### Network Setup

Scripts 2 & 3 connect to the board over SSH. Make sure:

- Board IP: `192.168.0.10` (default in scripts, change if needed)
- Host IP: must be on the same subnet (e.g. `192.168.0.1`)

To set a static IP on your host:
```bash
sudo ip addr add 192.168.0.1/24 dev eth0   # replace eth0 with your interface
```

---

## 4. File Organization — Versions

Each BSP release lives in its own **version directory** alongside the scripts:

```
AutoProgramingKria/
├── 0_setupTftp.sh
├── 1_burnFlash.sh
├── 2_burnEmmcBoot.sh
├── 3_burnEmmcRootfs.sh
├── readme.md
│
├── mustV3.1/                          ← version directory
│   ├── BOOT.BIN                       ← from PetaLinux build
│   ├── zynqmp_fsbl.elf                ← from PetaLinux build
│   ├── image.ub                       ← from PetaLinux build
│   ├── system.bit                     ← from PetaLinux build
│   ├── ubuntu-rootfs-*.tar.gz         ← Ubuntu rootfs tarball
│   └── modules--*.tgz                 ← kernel modules (optional)
│
├── mustV3.2/                          ← next version
│   └── ...
```

### Where each file comes from

| File | Source in your PetaLinux workspace |
|------|-------------------------------------|
| `BOOT.BIN` | `images/linux/BOOT.bin` |
| `zynqmp_fsbl.elf` | `images/linux/zynqmp_fsbl.elf` |
| `image.ub` | `images/linux/image.ub` |
| `system.bit` | `images/linux/system.bit` |
| `rootfs.cpio.gz.u-boot` | `images/linux/rootfs.cpio.gz.u-boot` *(ramdisk for TFTP boot)* |
| `ubuntu-rootfs-*.tar.gz` | Custom Ubuntu rootfs tarball |
| `modules--*.tgz` | `build/tmp/deploy/images/xilinx-k26-kr/modules--*.tgz` |

---

## 5. Adding a New Version

Follow these steps every time you have a new BSP build:

### Step 1 — Create the version directory

Name it something descriptive. Convention is `mustV<major>.<minor>`:
```bash
mkdir mustV3.2
```

### Step 2 — Copy build artifacts from your PetaLinux workspace

```bash
PETALINUX_WS="/path/to/your/petalinux/project"
VER="mustV3.2"

cp "${PETALINUX_WS}/images/linux/BOOT.bin"              ${VER}/BOOT.BIN
cp "${PETALINUX_WS}/images/linux/zynqmp_fsbl.elf"       ${VER}/
cp "${PETALINUX_WS}/images/linux/image.ub"              ${VER}/
cp "${PETALINUX_WS}/images/linux/system.bit"            ${VER}/
cp "${PETALINUX_WS}/images/linux/rootfs.cpio.gz.u-boot" ${VER}/

# Kernel modules (glob matches the long versioned filename automatically)
cp "${PETALINUX_WS}"/build/tmp/deploy/images/xilinx-k26-kr/modules--*.tgz ${VER}/
```

### Step 3 — Copy the Ubuntu rootfs tarball

```bash
cp /path/to/ubuntu-rootfs-ZYNQMP-2404-Ver3_2.tar.gz mustV3.2/
```

### Step 4 — Verify the directory contents

```bash
ls -lh mustV3.2/
```

You should see all of:
```
BOOT.BIN
zynqmp_fsbl.elf
image.ub
system.bit
rootfs.cpio.gz.u-boot
ubuntu-rootfs-*.tar.gz
modules--*.tgz          (optional but recommended)
```

### Step 5 — Run the scripts with your new version

```bash
./0_setupTftp.sh    --ver mustV3.2
./1_burnFlash.sh    --ver mustV3.2
./2_burnEmmcBoot.sh --ver mustV3.2
./3_burnEmmcRootfs.sh --ver mustV3.2
```

> **Tip:** To see all available versions at any time, run:
> ```bash
> ./1_burnFlash.sh --help
> ```

---

## 6. Programming Sequence (Step-by-Step)

Run the four scripts **in order**. Each one is independent — you can re-run any
step individually if something goes wrong.

---

### Step 0 — Configure TFTP

The board needs a TFTP server on the host to load the ramdisk and FPGA bitstream
over the network (used in Steps 2 & 3 to boot the board into a temporary Linux
environment from which eMMC is programmed).

```bash
./0_setupTftp.sh --ver mustV3.1
```

**What it does:**
- Updates `/etc/default/tftpd-hpa` to serve files from `mustV3.1/`
- Restarts the TFTP service

**Verify it worked:**
```bash
sudo systemctl status tftpd-hpa
```

---

### Step 1 — Program QSPI Flash

Programs `BOOT.BIN` into the QSPI flash chip using JTAG. This is what the board
boots from on power-on.

#### Before running:

1. **Set boot-mode switches to JTAG**
2. **Connect the JTAG cable** from your PC to the KR260 JTAG header
3. **Power on the board**

#### Run:

```bash
./1_burnFlash.sh --ver mustV3.1
```

#### After it completes:

1. **Set boot-mode switches back to QSPI**
2. **Power-cycle the board** — it will now boot U-Boot from the new flash

> **Note:** `zynqmp_fsbl.elf` is used by the tool to initialize the board over
> JTAG. It is not written to flash itself.

---

### Step 2 — Program eMMC Boot Partition

Partitions the eMMC storage and writes `image.ub` (Linux kernel + device tree)
and `system.bit` (FPGA bitstream) to the FAT32 boot partition.

#### Before running:

The board must be running a **temporary PetaLinux ramdisk** loaded over TFTP.
Do this from the U-Boot console (connect via USB-UART, 115200 baud):

```
# In U-Boot:
run load_fpga_tftp
run load_ramdisk_tftp
```

The board will boot into a minimal PetaLinux environment. Wait for the login
prompt, then run the script from your host PC:

#### Run:

```bash
./2_burnEmmcBoot.sh --ver mustV3.1
```

**What it does (on the board):**
- Unmounts any existing eMMC partitions
- Re-partitions the entire eMMC:
  - **p1** — 1 GiB, FAT32, labelled `boot-firmware`
  - **p2** — remaining space, left for Step 3
- Formats p1 and copies `image.ub` + `system.bit` into it

> ⚠️ **Warning:** This re-partitions the **entire eMMC**. All existing data is erased.

---

### Step 3 — Program eMMC Root Partition

Formats the root partition (p2) as ext4 and extracts the Ubuntu rootfs + kernel
modules into it.

#### Before running:

The board must **still be running the ramdisk** from Step 2. Do **not**
power-cycle between Steps 2 and 3.

#### Run:

```bash
./3_burnEmmcRootfs.sh --ver mustV3.1
```

**What it does (on the board):**
- Formats p2 as ext4 (label: `fs`)
- Extracts the Ubuntu rootfs tarball into p2
- Installs kernel modules from `modules--*.tgz` into `/lib/modules/`
- Syncs and unmounts

> This step transfers ~1.7 GB and will take **several minutes**.

#### After it completes:

1. **Set boot-mode switches to eMMC**
2. **Power-cycle the board**

The board will boot into Ubuntu from eMMC. 🎉

---

## 7. Script Reference

### Board Credentials (scripts 2 & 3)

Both scripts have these at the top of the file:

```bash
boardIp="192.168.0.10"      # KR260 IP address
boardUser="petalinux"       # SSH username (PetaLinux ramdisk default)
boardPassword="root"        # SSH password (PetaLinux ramdisk default)
boardSudoPassword="root"    # sudo password on the board
```

Change these if your network or board credentials differ.

### `--ver` Argument

All four scripts accept `--ver <version>` to select a version directory.
Files are resolved automatically:

| Script | Files loaded from version dir |
|--------|-------------------------------|
| `0_setupTftp.sh` | Entire directory set as TFTP root |
| `1_burnFlash.sh` | `BOOT.BIN`, `zynqmp_fsbl.elf` |
| `2_burnEmmcBoot.sh` | `image.ub`, `system.bit` |
| `3_burnEmmcRootfs.sh` | `*.tar.gz` (auto-glob), `modules--*.tgz` (auto-glob) |

### `--help` Argument

Every script accepts `--help` and prints usage + available versions:

```bash
./1_burnFlash.sh --help
```

---

## 8. Troubleshooting

### `sshpass: command not found`

```bash
sudo apt install -y sshpass
```

### `program_flash: command not found`

Set `vitisInstallDir` in `1_burnFlash.sh` to the correct path:
```bash
vitisInstallDir="/home/yourname/xilinx/Vitis/2023.1"
```

### `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`

The ramdisk generates a new SSH host key on every boot. The scripts handle this
automatically by running `ssh-keygen -R <boardIp>` before connecting.
If you still see it, run manually:
```bash
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.0.10
```

### `sudo: a terminal is required to read the password`

Set `boardSudoPassword` in the script config to the board's sudo password:
```bash
boardSudoPassword="root"
```

### U-Boot: TFTP load fails / file not found

Re-run the TFTP setup script to make sure the server is pointing at the right
version directory:
```bash
./0_setupTftp.sh --ver mustV3.1
```

Then check the TFTP service is running:
```bash
sudo systemctl status tftpd-hpa
```

### U-Boot: `run load_fpga_tftp` command not found

The U-Boot environment needs the `load_fpga_tftp` and `load_ramdisk_tftp`
variables. These should be set by the BOOT.BIN from your PetaLinux build.
Check with:
```
printenv load_fpga_tftp
```

### eMMC partition errors / fdisk fails

If `fdisk` errors about partitions being busy:
1. Reboot the board into ramdisk again (the eMMC won't be mounted)
2. Re-run the script

### Script 3 fails mid-extraction

The rootfs extraction is resumable — the partition is formatted fresh at the
start of the script each run, so just re-run:
```bash
./3_burnEmmcRootfs.sh --ver mustV3.1
```

### Board won't boot after programming

Check the boot-mode switches are set to **eMMC** mode.
If the board hangs at U-Boot, verify `image.ub` was transferred correctly by
re-running script 2.

### `No *.tar.gz rootfs tarball found in version dir`

Make sure your Ubuntu rootfs tarball is inside the version directory and has
a `.tar.gz` extension:
```bash
ls mustV3.1/*.tar.gz
```

---

## 9. TODO — Planned Features

- [x] **Package running rootfs** — Implemented as `4_packageRootfs.sh`. Mounts
  eMMC p2 read-only on the ramdisk, tarballs to `/dev/shm` (board RAM),
  and SCPs the result back to the host. Supports `--ver` to save directly
  into a version directory and `--name` to override the output filename.

- [ ] **DUST board support** — Extend all scripts (or add a `--board` argument)
  to support the DUST platform in addition to the KR260. Details TBD.
