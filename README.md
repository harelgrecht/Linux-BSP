# Linux BSP

Board Support Package, kernel drivers, and platform automation work for **Zynq-7000** and **Kria KR260 (Zynq UltraScale+)** platforms.

---

## KernelModules

Custom Linux kernel drivers written in C for direct hardware interaction.

| Driver | Description |
|---|---|
| [axi-gpio-kernel-driver](./KernelModules/axi-gpio-kernel-driver) | Character device driver for memory-mapped AXI GPIO IP core |
| [axi-uartlite-kernel-driver](./KernelModules/axi-uartlite-kernel-driver) | Serial driver with interrupt handling and circular buffer |
| [network-monitor-firewall](./KernelModules/network-monitor-firewall) | Kernel-space netfilter hook for packet monitoring and filtering |

---

## AutoBurn

Automated board programming scripts for flashing and provisioning embedded targets over TFTP and eMMC.

| Platform | Description |
|---|---|
| [AutoBurnMUST](./AutoBurn/AutoBurnMUST) | TFTP boot, flash, and eMMC programming pipeline for Kria KR260 |
| [AutoBurnDust](./AutoBurn/AutoBurnDust) | Adapted automation suite for the DUST board platform |

---

## ZynqBSP

BSP and build configurations for Zynq-7000 targets.

| Folder | Description |
|---|---|
| [vivadoZynq](./ZynqBSP/vivadoZynq) | Vivado block design project (AXI DMA + GPIO) |
| [zynqPLNX](./ZynqBSP/zynqPLNX) | PetaLinux project configuration |
| [zynqVitis](./ZynqBSP/zynqVitis) | Vitis software platform workspace |

---

## ZynqMpBSP

BSP and platform work for Kria KR260 (Zynq UltraScale+).

| Folder | Description |
|---|---|
| [KR260_Yocto](./ZynqMpBSP/KR260_Yocto) | Custom Yocto layer configuration for Kria KR260 |
| [Hardening](./ZynqMpBSP/Hardening) | Linux security hardening scripts and configuration |
| [KriaDocs](./ZynqMpBSP/KriaDocs) | Platform references and pin constraint files |

---

## Guides

Step-by-step technical guides for platform bringup and tooling.

| Guide | Description |
|---|---|
| [PetaLinux-Guide.md](./Guides/PetaLinux-Guide.md) | Full PetaLinux build and configuration walkthrough |
| [KernelModule.md](./Guides/KernelModule.md) | Writing, building, and loading custom kernel modules |
| [RealTimePatchGuide.md](./Guides/RealTimePatchGuide.md) | Applying `PREEMPT_RT` patch for deterministic latency on kernel 6.12 |
| [tftp.md](./Guides/tftp.md) | TFTP server setup for network booting |

---

## Tech Stack

| Area | Technologies |
|---|---|
| Languages | C, Bash |
| Build Systems | PetaLinux, Yocto, Make |
| Kernel APIs | Netfilter, Character devices, Platform drivers, IRQ |
| Platforms | Kria KR260, Zynq-7000, Custom PCBs |
| Tools | Vivado, Vitis, U-Boot, TFTP, eMMC |

---

## Hardware

- Kria KR260 Starter Kit (Zynq UltraScale+)
- Digilent Arty-Z7 (Zynq-7000)
- Custom PCB boards based on Zynq-7000
