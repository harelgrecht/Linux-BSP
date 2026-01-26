# Setting Up a TFTP Server and Transferring Files to a Target Device

This guide explains how to set up a **TFTP server** on a **Linux machine** and use it to transfer files to a **target device** (such as an embedded system running U-Boot).

---

## 1. Install and Configure the TFTP Server on the Host Machine

### 1.1 Install TFTP Server

On **Ubuntu/Debian**:

```bash
sudo apt update
sudo apt install tftpd-hpa xinetd tftp tftp-hpa
```

### 1.2 Configure the TFTP Server

Edit the TFTP configuration file:

```bash
sudo nano /etc/default/tftpd-hpa
```

Modify it to look like this:

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="<path_to_tftp_folder>"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"
```

Save and exit.

### 1.3 Create and Set Permissions for the TFTP Directory

```bash
sudo mkdir -p <path_to_tftp_folder>
sudo chmod -R 777 <path_to_tftp_folder>
sudo chown -R tftp:tftp <path_to_tftp_folder>
```

### 1.4 Restart the TFTP Service

```bash
sudo systemctl restart tftpd-hpa
sudo systemctl enable tftpd-hpa
```

---

## 2. Configure U-Boot on the Target Device

### 2.1 Set Up Network Configuration in U-Boot

```bash
setenv ipaddr 192.168.1.100  # Target Device IP
setenv serverip 192.168.1.1  # Host Machine IP (TFTP Server)
saveenv
```

Ensure the host machine and target device are on the same network.

### 2.2 Verify Network Connection

```bash
ping 192.168.1.1
```

If the ping succeeds, the network is working correctly.

---

## 3. Transfer Files Using TFTP

### 3.1 Place Files in the TFTP Directory

On the **host machine**, copy the file to `<path_to_tftp_folder>/`:

```bash
sudo cp BOOT.BIN <path_to_tftp_folder>/
sudo chmod 777 <path_to_tftp_folder>/BOOT.BIN
```

### 3.2 Fetch the File from U-Boot

On the **target device (U-Boot terminal)**, use:

```bash
tftpboot 0x800000 BOOT.BIN
```

- `0x800000` → Memory address where the file will be loaded.
- `BOOT.BIN` → The file to transfer.

To verify the transfer:

```bash
md 0x800000 10  # Display first few bytes of the file
```

---

## 4. Writing the File to Flash Storage

### 4.1 NOR Flash

```bash
sf probe
sf protect unlock 0x0 0x4000000 # unlocking the entire flash(64MB)
sf erase 0x0 0x4000000 # erase the entire flash
sf write 0x800000 0x0 $filesize
```

### 4.2 NAND Flash

```bash
nand erase 0x200000 0x100000
nand write 0x800000 0x200000 $filesize
```

### 4.3 eMMC/SD Card (FAT)

```bash
fatwrite mmc 0:1 0x800000 BOOT.BIN $filesize
```

### 4.4 eMMC/SD Card (RAW)

```bash
mmc write 0x800000 0x1000 0x200
```

---

## 5. Booting from the Transferred File (If Needed)

If the file is a **kernel image**, boot it using:

```bash
bootm 0x800000
```

or for a **Flattened Device Tree (FDT)**:

```bash
bootz 0x800000 - 0x820000
```

---

## 6. Troubleshooting

### 6.1 TFTP File Transfer Fails

- Ensure the file is in `<path_to_tftp_folder>/`.
- Set correct file permissions:
  ```bash
  sudo chmod 777 <path_to_tftp_folder>/BOOT.BIN
  ```
- Verify that the TFTP service is running:
  ```bash
  sudo systemctl status tftpd-hpa
  ```
- Ensure the firewall allows TFTP traffic:
  ```bash
  sudo ufw allow 69/udp  # Ubuntu
  sudo firewall-cmd --add-service=tftp --permanent  # CentOS
  ```

### 6.2 U-Boot Network Issues

- Verify network settings:
  ```bash
  printenv ipaddr
  printenv serverip
  ```
- Test connectivity:
  ```bash
  ping 192.168.1.1
  ```

### 6.3 Flash Writing Fails

- Ensure you **erase flash before writing**.
- Run `sf probe` (NOR flash) or `nand info` (NAND flash) before writing.

---

## 7. Summary of Key Commands

| Task                         | Command                                                                          |
| ---------------------------- | -------------------------------------------------------------------------------- |
| Install TFTP server          | `sudo apt install tftpd-hpa`                                                     |
| Configure TFTP directory     | `sudo mkdir -p <path_to_tftp_folder> && sudo chmod -R 777 <path_to_tftp_folder>` |
| Restart TFTP service         | `sudo systemctl restart tftpd-hpa`                                               |
| Set target IP in U-Boot      | `setenv ipaddr 192.168.1.100`                                                    |
| Set TFTP server IP in U-Boot | `setenv serverip 192.168.1.1`                                                    |
| Transfer file via TFTP       | `tftpboot 0x800000 BOOT.BIN`                                                   |
| Write to NOR Flash           | `sf write 0x800000 0x0 $filesize`                                                |
| Write to NAND Flash          | `nand write 0x800000 0x200000 $filesize`                                         |
| Boot from transferred file   | `bootm 0x800000`                                                                 |

---

## Conclusion

You have successfully set up a **TFTP server**, configured **U-Boot**, transferred a file, and written it to **flash memory**. This setup is commonly used for **bootloader updates, kernel transfers, and firmware flashing** in embedded systems.

---
