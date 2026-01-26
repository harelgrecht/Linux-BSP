# PetaLinux AXI GPIO Driver Guide

This guide covers the entire process of creating, building, and flashing a PetaLinux kernel module for AXI GPIO. It also includes steps for loading the kernel module using TFTP and managing modules on the target Linux system.

## Prerequisites
- Xilinx PetaLinux installed
- Xilinx Vivado installed
- A configured PetaLinux project
- Kria KR260 Starter Kit
- SD card for booting
- Network connection for TFTP boot

## Creating the PetaLinux Module

1. **Navigate to the PetaLinux project:**
   ```bash
   cd /path/to/petalinux/project
   ```
2. **Create a new kernel module:**
   - remember not to use Capslock or '_'
   ```bash
   petalinux-create -t modules -n <modulename> --enable
   ```
3. **Navigate to the module directory:**
   ```bash
   cd components/modules/<modulename>
   ```
4. **Edit `<modulename>.c` to implement the driver logic.** Example:
   ```c
   #include <linux/module.h>
   #include <linux/platform_device.h>

   static int __init axi_gpio_init(void) {
       pr_info("Hello, Custom Driver Initialized\n");
       return 0;
   }
   static void __exit axi_gpio_exit(void) {
       pr_info("Bye, Custom Driver Exited\n");
   }
   module_init(axi_gpio_init);
   module_exit(axi_gpio_exit);
   MODULE_LICENSE("GPL");
   MODULE_AUTHOR("Your Name");
   MODULE_DESCRIPTION("Custom Driver");
   ```
5. **Build the module:**
   ```bash
   petalinux-build -c device-tree
   petalinux-build -c kernel
   petalinux-build -c <modulename>
   ```
6. **Load the module:**\
   There are 2 options:\
   1 - Flashing the whole OS to the SDcard and flash memory.\
   2 - Copy using SCP and Load Kernel Modules.\
   3 - Using TFTP Boot to Load Kernel and Modules.



## Using TFTP Boot to Load Kernel and Modules

### Setup TFTP Boot

1. **Set up the network parameters in U-Boot:**
   ```bash
   setenv ethact eth1 # Set active Ethernet interface
   setenv ipaddr 192.168.0.111 # Board IP
   setenv serverip 192.168.0.110 # TFTP server IP
   ```
2. **Download and flash the image from the TFTP server:**
   ```bash
   tftpboot 0x10000000 /path/to/image.ub
   fatwrite usb 0:1 0x10000000 image.ub 0x${filesize}
   ```
3. **Verify network connectivity:**
   ```bash
   ping 192.168.0.110
   ```
4. **Load the image and boot:**
   ```bash
   time fatload usb 0:1 0x10000000 image.ub
   bootm
   ```

### Copy and Load Kernel Modules

1. **Copy the kernel module from the build system to the target device:**
   ```bash
   scp /path/to/petalinux/project/build/tmp/sysroots-components/xilinx_k26_kr/<modulename>/lib/modules/$(uname -r)/extra/<modulename>.ko user@192.168.0.111:/home/user
   ```
2. **On the target device, load the module:**
   ```bash
   sudo insmod /home/user/<modulename>.ko
   ```
3. **Verify module status:**
   ```bash
   sudo lsmod | grep <modulename>
   ```
4. **Unload the module if needed:**
   ```bash
   sudo rmmod <modulename>
   ```

## Additional Utilities

### Set IP Address on Linux
```bash
sudo ifconfig eth0 192.168.0.111
```

## Booting and Verifying the Module

1. **Check if the module is loaded:**
   ```bash
   dmesg | grep gpio
   ```
   Example output:
   ```
   [    2.460110] gpio gpiochip1: (zynqmp_gpio): not an immutable chip, please consider fixing it!
   [   11.961555] <modulename> a0000000.gpio: AXI GPIO Custom Driver Initialized
   ```
2. **If the module is not loaded, manually load it:**
   ```bash
   sudo insmod /lib/modules/$(uname -r)/extra/<modulename>.ko
   ```
### General Utilities
```bash
echo -ne "\033]0;Custom AXI GPIO\007" # Change terminal title
```