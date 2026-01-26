# AXI UART Lite Linux Kernel Driver for Kria KR260

This repository contains a custom Linux kernel driver for the Xilinx AXI UART Lite IP core, with full support for:

- Multiple UART devices (up to 4 configurable via `MAX_SUPPORTED_DEVICE`)
- Interrupt-driven receive (RX) handling
- Kernel FIFO (`kfifo`) usage for RX buffering
- Example user-space test program (`examples/UartTest.c`)
- Optional user-space C library for easier integration (`libCustomUart/`)

---

## Directory Structure

```
axi-uartlite-kernel-driver/
├── driver/               # Kernel module source code
│   ├── customuart.c
│   └── README.md
├── dtsi/                 # Device tree overlays (system-user.dtsi)
│   └── system-user.dtsi
├── examples/             # Example user-space test applications
│   └── UartTest.c
├── libCustomUart/        # Optional: Reusable C library for accessing UART devices
│   ├── CustomUart.c
│   └── CustomUart.h
└── README.md             # This file
```

---

## Features

- TX via polling (blocking behavior if FIFO is full)
- RX via interrupt with buffering in a kernel-managed kfifo
- Device nodes: `/dev/ttyUART0`, `/dev/ttyUART1`, ...
- Supports up to 4 UART devices
- FIFO size: 256 bytes (per device)

---

## Building and Installing with PetaLinux

1. Add this module to your PetaLinux project (`recipes-modules/`).
2. Enable the module:
   ```bash
   petalinux-config -c rootfs
   ```
   ➔ Select your module under **Modules → customuart**

3. Build:
   ```bash
   petalinux-build -c customuart
   ```

4. Ensure DTS is configured properly (see below).

---

## Device Tree Example

Add your UART devices in `system-user.dtsi`:

```dts
axi_uartlite_0: serial@a0010000 {
    compatible = "harel,customuart";
    reg = <0x0 0xa0010000 0x0 0x10000>;
    interrupt-parent = <&gic>;
    interrupts = <0 104 1>;
    clocks = <&zynqmp_clk 71>;
    clock-names = "s_axi_aclk";
    current-speed = <9600>;      // informational only
    xlnx,baudrate = <0x2580>;    // informational only
};
```

---

## Example Usage

```bash
echo "Hello" > /dev/ttyUART0
cat /dev/ttyUART0
```

If TX and RX are shorted, you should see the echoed string.

---

## Example Application

Compile:
```bash
gcc -o UartTest examples/UartTest.c
```
Run:
```bash
./UartTest /dev/ttyUART0
```

---

## Library (Optional)

You can use the `libCustomUart/` directory to write applications against a more structured API.

---

## Known Limitations

- **Baud Rate**: Fixed in hardware at synthesis time. Cannot change dynamically.
- **Parity/Stop Bits**: Not supported by AXI UART Lite.
- **TX is blocking** if FIFO full.

---

## License
GPL

Author: Harel
