# Hi there, I'm Harel! 👋
🚀 **Embedded Linux Developer** | Board Support Packages (BSP) | Kernel Modules

I specialize in bringing hardware to life using **Embedded Linux**. My work ranges from building custom Yocto/PetaLinux distributions to writing kernel drivers and real-time userspace applications.

---

## 🐧 Linux BSP & Infrastructure
*Core infrastructure projects for Zynq-7000 and Kria SOM platforms.*

| Project | Description | Tech Stack |
| :--- | :--- | :--- |
| **[Zynq Custom RootFS](https://github.com/harelgrecht/zynq-custom-rootfs)** | Custom-built Ubuntu-based root filesystem for Zynq-7000, including bootloader configuration. | `U-Boot` `RootFS` `Zynq-7000` |
| **[Kria KR260 BSP](https://github.com/harelgrecht/kria-bsp)** | Board Support Package for Xilinx Kria KR260, utilizing PetaLinux tools. | `PetaLinux` `Yocto` `KR260` |
| **[Real-Time Linux Patch]([https://github.com/harelgrecht/Linux-BSP/tree/main/Guides](https://github.com/harelgrecht/Linux-BSP/blob/main/Guides/RealTimePatchGuide.md))** | Implementation and configuration of `PREEMPT_RT` patch on kernel 6.12 for deterministic latency. | `Kernel` `Real-Time` `Patching` |

## 🔌 Linux Kernel Modules
*Custom drivers written in C for direct hardware interaction.*
* **[Network Monitor Firewall](https://github.com/harelgrecht/network-monitor-firewall)** - A kernel-space network packet filter and monitor hook.
* **[AXI GPIO Driver](https://github.com/harelgrecht/axi-gpio-driver)** - Character device driver for memory-mapped AXI GPIO IP.
* **[AXI UART Lite](https://github.com/harelgrecht/axi-uartlite-driver)** - Serial communication driver handling interrupts and circualr buffers.

## 📡 Embedded Applications
*Userspace networking and high-performance logic.*

* **[Ethernet Packet Processor](https://github.com/harelgrecht/Ethernet-Packet-Processor)** - High-performance raw socket handling and packet inspection engine.
* **[Ethernet 1588 Parser](https://github.com/harelgrecht/Ethernet-1588-Parser)** - IEEE 1588 PTP protocol parser for precise time synchronization.
* **[STM32 ToF Alarm](https://github.com/harelgrecht/STM32u5_ToF_Alarm)** - Bare-metal application utilizing Time-of-Flight sensors on STM32U5.

---

### 📚 Knowledge Base
I document my learning process. Check out my guides:
* [Embedded Linux Guides](https://github.com/harelgrecht/Linux-BSP/tree/main/Guides) - Collections of tutorials on Kernel modules, TFTP boot, and Device Trees.

---

## 🧰 Tools Used

- PetaLinux, Yocto
- Vivado + Vitis
- Linux Kernel Module APIs
- Git, GitHub
- STM32CubeIDE, FreeRTOS

## 🪛 Hardware Used

- Kria KR260 Starter Kit
- STM32U5-NUCLEO
- Digilent Arty-Z7
- Custom PCB Boards including ZYNQ7000

---

## 💼 Author

**Harel**  
Linux BSP & Embedded Software Developer in Progress  
➡️ [GitHub](https://github.com/harelgrecht)  
➡️ [Linkedin]()  

---
