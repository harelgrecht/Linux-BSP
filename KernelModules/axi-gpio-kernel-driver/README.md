# 🧠 AXI GPIO - Custom Linux Kernel Driver for Kria KR260

This project provides a **custom Linux kernel module** that replaces the default Xilinx AXI GPIO driver on the Kria KR260. It gives you full control over GPIO read/write from a memory-mapped kernel module with a `/sys/class/gpio_custom/` interface, making it suitable for learning and real-world embedded control.

---

## 📌 Features

- ✅ Replaces Xilinx default AXI GPIO kernel module
- ✅ Direct memory-mapped access to GPIO registers
- ✅ Sysfs interface to export pins and control them
- ✅ User-space C library planned (`libgpio`)
- 🧪 Tested with real hardware GPIO toggling

---

## 📂 Repo Structure

```
axi-gpio-custom-driver/
├── driver/
│   └── cusomgpio.c              # Custom kernel module
├── dts/
│   └── system-user.dtsi         # Device Tree overlay
├── Makefile                     # Kernel module Makefile
├── test/
│   └── gpio_toggle.sh           # Simple GPIO test script
├── README.md                    
```

---

## ⚙️ Building the Module

```bash
# Create a module project
petalinux-create -t modules -n cusomgpio --enable
#module name cannot use'_' or '-' or capslock.

# Navigate to the module dir
cd project-spec/meta-user/recipes-modules/cusomgpio/files

# Implement the module in the .c file, when finished
petalinux-build -c cusomgpio

# Transfter the .ko file to the running linux board

# On host machine
sudo ifconfig <device> 192.168.0.100

# On running linux board
sudo ifconfig <device> 192.168.0.10

cd build/tmp/sysroots-components/xilinx_k26_kr/cusomgpio/lib/modules/6.1.5-xilinx-v2023.1/extra/
scp -r cusomgpio.ko <username>@<target ip>:/home/<username>
```

---

## 🚀 Inserting the Module

```bash
sudo insmod cusomgpio.ko
dmesg | tail
```

Look for:
```bash
AXI GPIO Custom Driver Init
Mapping GPIO base succeeded
GPIO module Loaded
```

---

## 📖 Usage

After inserting the module, the following sysfs path will be available:

```bash
/sys/class/gpio/gpiochip<num>/
```

You can toggle or read GPIO like so:

```bash
cd /sys/class/gpio
# Look for the axi labeled gpio chip
cat gpiochip<num>/label
sudo echo <pin_num> > export
# To toggle the GPIO
sudo echo out > /gpio<num>/direction
sudo echo 1 > /gpio<num>/value
# To read the GPIO
sudo echo in > /gpio<num>/direction
sudo cat gpio<num>/value
```
---

## 👷 TODO / Planned Features

- [ ] Create a small user-space C library for easier usage
- [ ] Clean error handling and logging

---

## 📚 Background

This driver was written as a learning exercise to better understand **custom memory-mapped I/O**, **sysfs interfaces**, and **device tree overlays** in Linux kernel development on Xilinx platforms like the **Kria KR260**.

---

## 🙋 About the Author

**Harel** – Embedded Linux & Kernel Developer in Progress  
Check out the full [development roadmap](https://github.com/harelgrecht/kr260-linux-roadmap.git) to see how this project fits into a larger embedded Linux journey.

---