# DUST Linux

## general information:
    username: dust
    password: root

    boot mode: 
        make sure SW1 is configure to "1000"
        DipSwitch configuration:
        M0 = hi, m1 = lo, sw0 = lo, sw1 = lo

    flash part name:
        w25q128fv-qspi-x4-single

---
## package commands:
```bash
petalinux-package --boot --u-boot --force

# dosent really needed in this arch
petalinux-package --wic --bootfiles "BOOT.BIN,image.ub,system.dtb,boot.scr" --rootfs-file ./images/linux/rootfs.tar.gz
```
---
# program flash
```bash
time tftpboot 0x100000 BOOT.BIN
sf probe 0 0 0
sf erase 0x0 0x115000
time sf update 0x100000 0x0 ${filesize}
```

## or via vivado
---
# load kernel and rootfs to RAM
## Pull `image.ub` and `rootfs.cpio.gz.u-boot` and `system.bit` via tftp
### Only on first time eMMC programing
```bash
setenv ipaddr 192.168.0.10
setenv serverip 192.168.0.100

tftpboot 0x1000000 image.ub
tftpboot 0x3000000 system.bit
fpga loadb 0 0x3000000 ${filesize}
tftpboot 0x2000000 rootfs.cpio.gz.u-boot


bootm 0x1000000 0x2000000 
```
---
## Create partitions on linux
```bash
sudo su
fdisk /dev/mmcblk1
# delete all existing partitions (verify w)
    d => 1
    d => 2
    w
# next - create new one
    n => p => 1 => Enter => +1G
    n => p => 2 => Enter => Enter
    w

mkfs.vfat -F 32 -n "boot" /dev/mmcblk1p1
mkfs.vfat -n "boot" /dev/mmcblk1p1 
mkfs.ext4 -L "fs" /dev/mmcblk1p2 
sync

# tansfer image.ub and system.bit to bootFiles and rootfs.tar.gz to rootFiles
sudo mount /dev/mmcblk1p1 /home/dust/bootFiles
sudo mount /dev/mmcblk1p2 /home/dust/rootFiles

mkdir /home/dust/bootFiles
scp image.ub system.bit uboot.env dust@192.168.0.10:/home/dust/bootFiles

mkdir /home/dust/rootFiles
scp rootfs.tar.gz dust@192.168.0.10:/home/dust/rootFiles

cd /home/dust/rootFiles
sudo tar -xzvf rootfs.tar.gz
sync
# linux running from emmc automaticly
```
---

# Commands that will go in function under `uboot.env` to automate bsp update
## Use only if the automation didnt work
```bash
# pull from eMMC and boot kernel
fatload mmc 1:1 0x1000000 image.ub
fatload mmc 1:1 0x3000000 system.bit
fpga loadb 0 0x3000000 ${filesize}

setenv bootargs 'console=ttyPS0,115200 eralyprintk root=/dev/mmcblk1p2 rw rootwait ip=192.168.0.10:::255.255.255.0:dust:eth0:off'

bootm 0x1000000 
``` 

```bash
# import uboot.env from eMMC rootfs partions
fatload mmc 1:1 0x1000000 uboot.env 
env import -t 0x1000000
```
---



# last update
19/01/2026
-- workflow works, files and configuration.
-- TODO:
    fix spi thing
    make env load automaticly