
# Custom AXI UARTLite Kernel Module

## Overview

This Linux kernel module provides a character device interface to a Xilinx AXI UARTLite hardware IP block, 
typically instantiated in the programmable logic of Xilinx FPGAs such as the Kria KR260.

The driver supports multiple UARTLite instances via device tree configuration, interrupt-driven receive, 
and synchronous (polling) transmit.

- **Driver Name**: `ttyUART`
- **Device Nodes**: `/dev/ttyUART0`, `/dev/ttyUART1`, ..., up to MAX_SUPPORTED_DEVICE (4 by default)

## Features

- Support for multiple AXI UARTLite instances
- Interrupt-driven receive using kernel FIFOs (`kfifo`)
- Polling-based transmit
- Character device interface (`/dev/ttyUARTn`)
- Device Tree integration for resource management (memory regions, clocks, IRQs)

## Limitations

- **Baudrate**: Fixed at hardware generation time; cannot be changed at runtime.
- **Parity**: Not supported by AXI UARTLite IP.

## Device Tree Example

```
axi_uartlite_0: serial@a0010000 {
    compatible = "harel,customuart";
    reg = <0x0 0xa0010000 0x0 0x10000>;
    clock-names = "s_axi_aclk";
    clocks = <&zynqmp_clk 71>;
    interrupt-parent = <&gic>;
    interrupts = <0 104 1>;
};
```


## License

Author: Harel
