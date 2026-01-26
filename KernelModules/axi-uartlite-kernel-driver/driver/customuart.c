#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/platform_device.h>
#include <linux/device.h>
#include <linux/clk.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/irq.h>
#include <linux/interrupt.h>
#include <linux/kfifo.h>
#include <linux/wait.h>
#include <linux/slab.h>
#include <linux/cdev.h>

#define DRIVER_NAME                 "ttyUART"
#define UART_RX_REG                 0x0
#define UART_TX_REG                 0x4
#define UART_STATUS_REG             0x8
#define UART_CTRL_REG               0xC

#define TX_FIFO_FULL_BIT_INDEX      3
#define RX_FIFO_VALID_BIT_INDEX     0
#define INTERRUPT_BIT_INDEX         4

#define UART_RX_FIFO_SIZE           256
#define MAX_SUPPORTED_DEVICES       4
#define BASE_MINOR_NUMBER           0

static dev_t uartDevt;
static struct class *uartClass;

struct customUartDevice {
    void __iomem *baseAddr;
    struct clk *clk;
    int irq;

    struct cdev charDev;
    dev_t devt;
    struct device *uartDevice;

    struct kfifo rxFifo;
    wait_queue_head_t rxWaitQueue;
};

static void enableInterrupts(struct customUartDevice *dev) {
    pr_debug("enableInterrupts(): called\n");
    uint32_t ctrlReg = ioread32(dev->baseAddr + UART_CTRL_REG);
    uint32_t statusReg = ioread32(dev->baseAddr + UART_STATUS_REG);

    pr_debug("enableInterrupts(): Interrupt status before enable = %d\n", !!(statusReg & BIT(INTERRUPT_BIT_INDEX)));

    if (!(statusReg & BIT(INTERRUPT_BIT_INDEX))) {
        ctrlReg |= BIT(INTERRUPT_BIT_INDEX);
        iowrite32(ctrlReg, dev->baseAddr + UART_CTRL_REG);
        pr_debug("enableInterrupts(): Enabled interrupt, new status = %d\n",
                 !!(ioread32(dev->baseAddr + UART_STATUS_REG) & BIT(INTERRUPT_BIT_INDEX)));
    } else {
        pr_debug("enableInterrupts(): Interrupt already enabled\n");
    }
}

static bool rxFifoHasData(struct customUartDevice *dev) {
    uint32_t status = ioread32(dev->baseAddr + UART_STATUS_REG);
    pr_debug("rxFifoHasData(): RX status = %d\n", !!(status & BIT(RX_FIFO_VALID_BIT_INDEX)));
    return status & BIT(RX_FIFO_VALID_BIT_INDEX);
}

static bool isTxFifoFull(struct customUartDevice *dev) {
    uint32_t status = ioread32(dev->baseAddr + UART_STATUS_REG);
    pr_debug("isTxFifoFull(): TX status = %d\n", !!(status & BIT(TX_FIFO_FULL_BIT_INDEX)));
    return status & BIT(TX_FIFO_FULL_BIT_INDEX);
}

static ssize_t customUartWrite(struct file *file, const char __user *buf, size_t count, loff_t *ppos) {
    pr_debug("customUartWrite(): called, count = %zu\n", count);
    struct customUartDevice *dev = file->private_data;
    char txByte;

    for (size_t i = 0; i < count; i++) {
        if (copy_from_user(&txByte, buf + i, 1)) {
            pr_debug("customUartWrite(): copy_from_user failed at index %zu\n", i);
            return -EFAULT;
        }

        while (isTxFifoFull(dev)) {
            pr_debug("customUartWrite(): TX FIFO full, waiting...\n");
            if (signal_pending(current)) {
                pr_debug("customUartWrite(): signal_pending() detected, exiting write\n");
                return -ERESTARTSYS;
            }
            cpu_relax();
        }
        iowrite32(txByte, dev->baseAddr + UART_TX_REG);
        pr_debug("customUartWrite(): Wrote byte 0x%02x to UART\n", txByte);
    }

    pr_debug("customUartWrite(): completed, bytes written = %zu\n", count);
    return count;
}

static irqreturn_t customUartIrqHandler(int irq, void *devId) {
    struct customUartDevice *dev = devId;
    uint32_t rawData;
    uint8_t byte;

    pr_debug("customUartIrqHandler(): Interrupt received\n");

    while (rxFifoHasData(dev)) {
        rawData = ioread32(dev->baseAddr + UART_RX_REG);
        byte = rawData & 0xFF;
        kfifo_in(&dev->rxFifo, &byte, 1);
        pr_debug("customUartIrqHandler(): byte received = 0x%02x\n", byte);
    }
    wake_up_interruptible(&dev->rxWaitQueue);
    pr_debug("customUartIrqHandler(): exiting\n");
    return IRQ_HANDLED;
}

static ssize_t customUartRead(struct file *file, char __user *buf, size_t count, loff_t *ppos) {
    struct customUartDevice *dev = file->private_data;
    unsigned int copied;
    int ret;

    pr_debug("customUartRead(): called, count = %zu\n", count);

    if (kfifo_is_empty(&dev->rxFifo)) {
        pr_debug("customUartRead(): RX FIFO empty\n");
        if (file->f_flags & O_NONBLOCK)
            return -EAGAIN;

        ret = wait_event_interruptible(dev->rxWaitQueue, !kfifo_is_empty(&dev->rxFifo));
        if (ret)
            return ret;
    }

    ret = kfifo_to_user(&dev->rxFifo, buf, count, &copied);
    if (ret) {
        pr_debug("customUartRead(): kfifo_to_user failed\n");
        return -EFAULT;
    }

    pr_debug("customUartRead(): returning %u bytes\n", copied);
    return copied;
}

static int customUartOpen(struct inode *inode, struct file *file) {
    struct customUartDevice *dev = container_of(inode->i_cdev, struct customUartDevice, charDev);
    file->private_data = dev;
    pr_debug("customUartOpen(): opened device %s\n", dev_name(dev->uartDevice));
    return 0;
}

static int customUartRelease(struct inode *inode, struct file *file) {
    pr_debug("customUartRelease(): closed\n");
    return 0;
}

static const struct file_operations uartFops = {
    .owner = THIS_MODULE,
    .read = customUartRead,
    .write = customUartWrite,
    .open = customUartOpen,
    .release = customUartRelease,
};

static int getUartIrq(struct platform_device *pdev, struct customUartDevice *dev) {
    pr_debug("getUartIrq(): getting IRQ\n");
    dev->irq = platform_get_irq(pdev, 0);
    if (dev->irq < 0) {
        pr_err("getUartIrq(): Failed to get IRQ from DT\n");
        return dev->irq;
    }
    pr_debug("getUartIrq(): IRQ number = %d\n", dev->irq);

    return devm_request_irq(&pdev->dev, dev->irq, customUartIrqHandler, IRQF_TRIGGER_RISING, DRIVER_NAME, dev);
}

static int registerUartDevice(struct platform_device *pdev, struct customUartDevice *dev, unsigned int index) {
    pr_debug("registerUartDevice(): called for index %u\n", index);
    int ret;

    dev->devt = MKDEV(MAJOR(uartDevt), BASE_MINOR_NUMBER + index);

    ret = alloc_chrdev_region(&dev->devt, BASE_MINOR_NUMBER + index, 1, DRIVER_NAME);
    if (ret) {
        pr_err("registerUartDevice(): alloc_chrdev_region failed\n");
        return ret;
    }

    cdev_init(&dev->charDev, &uartFops);
    dev->charDev.owner = THIS_MODULE;

    ret = cdev_add(&dev->charDev, dev->devt, 1);
    if (ret) {
        pr_err("registerUartDevice(): cdev_add() failed\n");
        unregister_chrdev_region(dev->devt, 1);
        return ret;
    }

    dev->uartDevice = device_create(uartClass, NULL, dev->devt, dev, "%s%d", DRIVER_NAME, index);
    if (IS_ERR(dev->uartDevice)) {
        ret = PTR_ERR(dev->uartDevice);
        cdev_del(&dev->charDev);
        pr_err("registerUartDevice(): device_create() failed\n");
        return ret;
    }

    pr_debug("registerUartDevice(): device registered successfully as /dev/%s%d\n", DRIVER_NAME, index);
    return 0;
}

static unsigned long getUartClk(struct platform_device *pdev, struct customUartDevice *dev) {
    pr_debug("getUartClk(): called\n");
    dev->clk = devm_clk_get(&pdev->dev, NULL);
    if (IS_ERR(dev->clk)) {
        pr_err("getUartClk(): Failed to get clock\n");
        return 0;
    }

    if (clk_prepare_enable(dev->clk)) {
        pr_err("getUartClk(): clk_prepare_enable() failed\n");
        return 0;
    }

    unsigned long clkRate = clk_get_rate(dev->clk);
    pr_debug("getUartClk(): UART clock rate = %lu\n", clkRate);
    return clkRate;
}

static int customUartProbe(struct platform_device *pdev) {
    pr_debug("customUartProbe(): called for %s\n", dev_name(&pdev->dev));
    struct customUartDevice *dev;
    struct resource *res;
    unsigned long clkRate;
    static unsigned int deviceCount;

    if (deviceCount >= MAX_SUPPORTED_DEVICES) {
        pr_err("customUartProbe(): Max supported devices exceeded\n");
        return -ENOMEM;
    }

    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;

    platform_set_drvdata(pdev, dev);

    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (!res) {
        pr_err("customUartProbe(): No IORESOURCE_MEM in DT\n");
        return -ENODEV;
    }

    dev->baseAddr = devm_ioremap_resource(&pdev->dev, res);
    if (IS_ERR(dev->baseAddr)) {
        pr_err("customUartProbe(): devm_ioremap_resource() failed\n");
        return PTR_ERR(dev->baseAddr);
    }

    pr_debug("customUartProbe(): Mapped UART address: %p\n", dev->baseAddr);

    if (getUartIrq(pdev, dev) < 0)
        return -EINVAL;

    clkRate = getUartClk(pdev, dev);
    if (!clkRate)
        return -EINVAL;

    if (registerUartDevice(pdev, dev, deviceCount) < 0)
        return -ENODEV;

    if (kfifo_alloc(&dev->rxFifo, UART_RX_FIFO_SIZE, GFP_KERNEL)) {
        pr_err("customUartProbe(): Failed to allocate kfifo\n");
        return -ENOMEM;
    }

    init_waitqueue_head(&dev->rxWaitQueue);
    enableInterrupts(dev);

    pr_debug("customUartProbe(): UART device probed successfully, deviceCount = %u\n", deviceCount);
    deviceCount++;
    return 0;
}

static int customUartRemove(struct platform_device *pdev) {
    pr_debug("customUartRemove(): called\n");
    struct customUartDevice *dev = platform_get_drvdata(pdev);

    device_destroy(uartClass, dev->devt);
    cdev_del(&dev->charDev);
    clk_disable_unprepare(dev->clk);
    kfifo_free(&dev->rxFifo);

    pr_debug("customUartRemove(): complete\n");
    return 0;
}

static const struct of_device_id customUartOfMatch[] = {
    { .compatible = "harel,customuart" },
    {},
};
MODULE_DEVICE_TABLE(of, customUartOfMatch);

static struct platform_driver customUartPlatformDriver = {
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = customUartOfMatch,
    },
    .probe = customUartProbe,
    .remove = customUartRemove,
};

static int __init customUartInit(void) {
    pr_debug("customUartInit(): called\n");
    int ret = alloc_chrdev_region(&uartDevt, BASE_MINOR_NUMBER, MAX_SUPPORTED_DEVICES, DRIVER_NAME);
    if (ret)
        return ret;

    uartClass = class_create(THIS_MODULE, DRIVER_NAME);
    if (IS_ERR(uartClass)) {
        unregister_chrdev_region(uartDevt, MAX_SUPPORTED_DEVICES);
        return PTR_ERR(uartClass);
    }

    return platform_driver_register(&customUartPlatformDriver);
}

static void __exit customUartExit(void) {
    pr_debug("customUartExit(): called\n");
    platform_driver_unregister(&customUartPlatformDriver);
    class_destroy(uartClass);
    unregister_chrdev_region(uartDevt, MAX_SUPPORTED_DEVICES);
}

module_init(customUartInit);
module_exit(customUartExit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Harel");
MODULE_DESCRIPTION("Custom AXI UARTLite device driver");
