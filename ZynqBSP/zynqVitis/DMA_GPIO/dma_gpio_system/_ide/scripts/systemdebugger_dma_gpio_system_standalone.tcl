# Usage with Vitis IDE:
# In Vitis IDE create a Single Application Debug launch configuration,
# change the debug type to 'Attach to running target' and provide this 
# tcl script in 'Execute Script' option.
# Path of this script: /home/harel/Desktop/Projects/Linux-BSP/ZynqBSP/zynqVitis/DMA_GPIO/dma_gpio_system/_ide/scripts/systemdebugger_dma_gpio_system_standalone.tcl
# 
# 
# Usage with xsct:
# To debug using xsct, launch xsct and run below command
# source /home/harel/Desktop/Projects/Linux-BSP/ZynqBSP/zynqVitis/DMA_GPIO/dma_gpio_system/_ide/scripts/systemdebugger_dma_gpio_system_standalone.tcl
# 
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~"APU*"}
rst -system
after 3000
targets -set -filter {jtag_cable_name =~ "Digilent Arty Z7 003017BC918AA" && level==0 && jtag_device_ctx=="jsn-Arty Z7-003017BC918AA-23727093-0"}
fpga -file /home/harel/Desktop/Projects/Linux-BSP/ZynqBSP/zynqVitis/DMA_GPIO/dma_gpio/_ide/bitstream/ZYNQ_DMA_GPIO.bit
targets -set -nocase -filter {name =~"APU*"}
loadhw -hw /home/harel/Desktop/Projects/Linux-BSP/ZynqBSP/zynqVitis/DMA_GPIO/plat/export/plat/hw/ZYNQ_DMA_GPIO.xsa -mem-ranges [list {0x40000000 0xbfffffff}] -regs
configparams force-mem-access 1
targets -set -nocase -filter {name =~"APU*"}
source /home/harel/Desktop/Projects/Linux-BSP/ZynqBSP/zynqVitis/DMA_GPIO/dma_gpio/_ide/psinit/ps7_init.tcl
ps7_init
ps7_post_config
targets -set -nocase -filter {name =~ "*A9*#0"}
dow /home/harel/Desktop/Projects/Linux-BSP/ZynqBSP/zynqVitis/DMA_GPIO/dma_gpio/Debug/dma_gpio.elf
configparams force-mem-access 0
targets -set -nocase -filter {name =~ "*A9*#0"}
con
