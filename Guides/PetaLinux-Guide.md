
# PetaLinux Step-by-Step Guide

Refer to [UG1144](https://www.xilinx.com) for more information on setting up your PetaLinux environment.

**Tested on**:  
- **Tools Version**: 2023.1  
- **Hardware Platforms**: Arty-Z7, KR260 Starter Kit  

Before starting, ensure your terminal is using `Bash` mode by running:  
`chsh -s /bin/bash`.

---

## Setting Up Your Environment

1. Open a terminal and edit the `.bashrc` file:
    ```bash
    nano ~/.bashrc
    ```

2. Add the following lines at the end of the file:
    ```bash
    sudo sysctl fs.inotify.max_user_watches=524288
    source ~/Desktop/petalinux-tool/settings.sh
    PATH="${XSCT_TOOLCHAIN}/bin:${PATH}"
    ```

3. Save and exit. This ensures every terminal you open has the PetaLinux environment.

4. Verify the setup:
    ```bash
    petalinux
    ```
    If a list of commands appears, the setup is complete.

---

## Creating a New Project

Navigate to your desired directory:
```bash
cd <directory_path>
```

To create a PetaLinux project:  
- Without BSP using a template:
    ```bash
    petalinux-create --type project --template zynqMP/zynq --name <project_name>
    ```
- With BSP:
    ```bash
    petalinux-create --type project -s <path_to_bsp> --name <project_name>
    ```

---

## Configuring the Project

Navigate to the project directory:
```bash
cd <project_name>
```

1. Configure with your `XSA` file:
    ```bash
    petalinux-config --get-hw-description=<path_to_xsa_file>
    ```

2. Reconfigure the project:
    ```bash
    petalinux-config
    ```

3. Configure a specific subsystem:
    ```bash
    petalinux-config -c <subsystem>
    ```
    Available subsystems: `rootfs`, `device-tree`, `u-boot`, `kernel`.

---

### Configuring for Offline Use

Ensure offline packages are available locally at:
```
matspen$/General/Development Kits/PetaLinux_installation
```

1. Open the config menu:
    ```bash
    petalinux-config
    ```

2. Set the following options:
    - **Yocto Settings →** `[ * ] Enable BB NO NETWORK`
    - **Yocto Settings → Network sstate feeds URL →**  
      `file:///home/user/Desktop/Petalinux-tools/OfflinePackages/aarch64`
    - **Yocto Settings → Local sstate feeds settings → Local sstate feeds URL →**  
      `file:///home/user/Desktop/Petalinux-tools/OfflinePackages/aarch64`
    - **Yocto Settings → Add pre-mirror URL →**  
      `file:///home/user/Desktop/Petalinux-tools/OfflinePackages/downloads`

3. Modify the following file:
    ```bash
    nano components/yocto/layers/meta-xilinx/meta-xilinx-core/recipes-bsp/pmu-firmware/pmu-rom-native.bb
    ```
    Update line 10 to:
    ```bash
    SRC_URI = "/home/user/Desktop/Petalinux-tools/OfflinePackages/downloads/openDownload_filename=PMU_ROM.tar.gz"
    ```

---

### Customizing the Project

1. For SD card use:
    - Change the root filesystem to `EXT4(sd/emmc)` and set the device node to `/dev/sda`.

2. Add standard libraries and compilers:
    ```bash
    petalinux-config -c rootfs
    ```
    Press `/` and search for `packages-buildessentials` and enable it.\
    Press `/` and search for `packagegroup-petalinux-kria` and disable it. (If enabled it will make problems with the FPGA)
---

## Building the Project
"
1. Build the entire project:
    ```bash
    petalinux-build
    ```

2. Clean and rebuild:
    ```bash
    petalinux-build -x mrproper
    ```

3. Build a specific subsystem:
    ```bash
    petalinux-build -c <subsystem>
    ```
    Available subsystems: `rootfs`, `device-tree`, `u-boot`, `kernel`.

---

## Packaging

### Boot File

Package boot files into `BOOT.BIN`:
```bash
petalinux-package --boot --u-boot --fpga images/linux/system.bit --force
```

### Linux Image

Package the Linux image for SD/eMMC programming:
```bash
petalinux-package --wic --bootfiles "BOOT.BIN,image.ub,system.dtb,boot.scr" --rootfs-file ./images/linux/rootfs.tar.gz
```

For KR260 Starter Kit with BSP:
```bash
petalinux-package --wic --images-dir images/linux/ --bootfiles "ramdisk.cpio.gz.u-boot,boot.scr,Image,system.dtb,system-zynqmp-sck-kr-g-revB.dtb,system.bit" --disk-name "sda"
```

---

## Programming the Hardware

### KR260 Starter Kit

1. Press `FW` and reset the board to enter firmware update mode.
2. Connect via Ethernet.
3. Configure the PC IP to `192.168.0.100`.
4. Open `192.168.0.111` in a browser.
5. Choose a bootable image (A/B).
6. Upload `BOOT.BIN`.

### Zynq Flash (Arty-Z7)

1. Open Vivado and the Hardware Manager.
2. Connect to the board and select "Program Device."
3. Add the Flash device, then browse and upload:
    - `BOOT.BIN`
    - `zynq_fsbl.elf`

### SD/eMMC

- **SD Card**: Use BalenaEtcher or Rufus to flash `petalinux-sdimage.wic.gz`.
- **eMMC**:
    1. Configure target IP: `192.168.1.2`, mask `255.255.255.0`.
    2. Configure PC IP: `192.168.1.1`, mask `255.255.255.0`.
    3. Transfer the image:
        ```bash
        gzip images/linux/petalinux-sdimage.wic
        ssh-keygen -f "/home/linux/.ssh/known_hosts" -R "192.168.1.111"
        scp -r images/linux/petalinux-sdimage.wic.gz petalinux@192.168.1.111:/tmp
        ```
    4. On the board:
        ```bash
        sudo su
        gunzip -c /tmp/petalinux-sdimage.wic.gz | dd of=/dev/mmcblk0 bs=1M status=progress
        sync
        ```

---

## Additional Notes

- **Convert DTB to DTS**:
    ```bash
    sudo apt install dtc
    dtc -I dtb -O dts -o system.dts system.dtb
    ```

- **Configure Ethernet in U-Boot**:
    ```bash
    setenv ethact <eth_interface>
    setenv ipaddr <ip_address>
    setenv netmask <netmask>
    saveenv
    ```

- **KR260 Vivado Version**: Use the version at `matspen$/general/development kits/kria260/vivado`. For AXI interface, use `HPM0` in PS-PL configuration.

- **Adding external packages**
    To add `htop` or `cmake` for example.
    ```bash
    nano <plnx-project>/project-spec/meta-user/conf/user-rootfsconfig
    ```
    in each line you can add 1 packages so for exapmle:
    CONFIG_cmake
    CONFIG_htop