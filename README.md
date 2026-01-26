# 🚀 Kria KR260 Linux Kernel Development Roadmap

Welcome! This repo tracks my personal journey to become a Linux kernel and embedded software developer using the Kria KR260 platform and PetaLinux. Each project builds on the previous one, from basic system setup to writing custom drivers and real-time networking features.

---

## 🧭 Project Roadmap

| ✅ Status | Project | Description |
|----------|---------|-------------|
| ✅ DONE | [PetaLinux Setup](https://github.com/harelgrecht/kr260-linux-roadmap) | Built and booted a custom PetaLinux image for the KR260. Learned SD boot flow, kernel config, DTS overlays. |
| ✅ DONE | [Ethernet Packet Processor](https://github.com/harelgrecht/Ethernet-Packet-Processor) | Multithreaded user-space app capturing packets, custom process them, and resending via Ethernet over UDP. |
| ✅ DONE | [Ethernet 1588 Parser](https://github.com/harelgrecht/Ethernet-1588-Parser) | Parsing raw sniffed L2 ethernet packets into PtPv2-1588 structre and converting to ToD, and writing them back to the PL. |
| ✅ DONE | [AXI GPIO Kernel Module](https://github.com/harelgrecht/kr260-linux-roadmap) | Replaced Xilinx GPIO driver with a custom kernel module. Controlled GPIO directly from PL with memory-mapped IO. |
| ✅ DONE | [AXI UART Lite Driver](https://github.com/harelgrecht/kr260-linux-roadmap) | Polling-based driver to replace the default AXI UART Lite. Exposes `/dev/ttyUART`. Includes user-space C library. |
| 🛠️ IN-PROGRESS | [Ethernet PHY Expansion](https://github.com/harelgrecht/kr260-linux-roadmap) | Enables extra Ethernet ports by integrating PHYs in PL and modifying DTS. Learning DTS structure and PHY reset flows. |
| ✅ DONE  | [Real Time Patch](https://github.com/harelgrecht/kr260-linux-roadmap) | Learn and enable Real Time Patch to the Zynq UltraScale+ BSP. |
| ✅ DONE  | [ToFGuard-U5](https://github.com/harelgrecht/STM32u5_ToF_Alarm) | Multi-task FreeRTOS app on STM32, fusing I2C & ToF optic sensor data using a thread-safe mutex. |
| 🛠️ IN-PROGRESS | [Network Monitor & FireWall]() | Kernel module to filter network packets by user request using netfilter and procfs. |


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

---
