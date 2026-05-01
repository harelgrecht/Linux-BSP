#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/device.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/io.h> 
#include <linux/dma-mapping.h>

#define DRIVER_NAME "dmaDriver"

#define DMA_CONTROL_REG 0x00
#define DMA_STATUS_REG 0X04

struct descriptorFileds {
    uint32_t nextDescriptor;    // 00
    uint32_t nextDescriptorMsb; // 04
    uint32_t bufferAddress;     // 08
    uint32_t bufferAddressMsb;  // 0c
    uint32_t reserved0;         // 10
    uint32_t reserved1;         // 14
    uint32_t control;           // 18
    uint32_t status;            // 1c
    uint32_t app0;              // 20
    uint32_t app1;              // 24
    uint32_t app2;              // 28
    uint32_t app3;              // 2c
    uint32_t app4;              // 30
};

void __iomem *dmaBaseAddr;


struct txHandler{
    struct descriptorFileds *txDescriptor;
    dma_addr_t txDescriptorPhysical;
    u8 *txBuffer;
    dma_addr_t txBufferPhysical;
};
static struct txHandler txChan;


static int allocateMem(struct platform_device *pdev) {
    txChan.txDescriptor = dma_alloc_coherent(&pdev->dev,  sizeof(struct descriptorFileds), txChan.txDescriptorPhysical, GFP_KERNEL);
    if(!txChan.txDescriptor) {
        dev_err(&pdev->dev, "Failed to allocate TX Descriptor\n");
        return -ENOMEM;
    }

    txChan.txBuffer = dma_alloc_coherent(&pdev->dev, 1024, txChan.txBufferPhysical, GFP_KERNEL);
    if(!txChan.txBuffer) {
        dev_err(&pdev->dev, "Failed to allocate TX Buffer\n");
        dma_free_coherent(&pdev->dev, sizeof(struct descriptorFileds), txChan.txDescriptor, txChan.txDescriptorPhysical);
        return -ENOMEM;
    }

    dev_info(&pdev->dev, "TX Descriptor: Virtual = %p, Physical = %pad\n", txChan.txDescriptor, &txChan.txDescriptorPhysical);
    dev_info(&pdev->dev, "TX Buffer: Virtual = %p, Physical = %pad\n", txChan.txBuffer, &txChan.txBufferPhysical);
    return 0;
}


void startDmaTransfer(struct platform_device *pdev) {
    txChan.txDescriptor.nextDescriptor = txChan.txDescriptorPhysical;
    txChan.txBuffer.bufferAddress = txChan.txBufferPhysical;
}



/* Match Table(Look up for the right driver in the DT) */
static const struct of_device_id dmaOfMatch[] = {
    { .compatible = "harel,dmaDriver" },
    {},
};
MODULE_DEVICE_TABLE(of, dmaOfMatch);

static int dmaProbe(struct platform_device *pdev) {
    struct device *dev = &pdev->dev;
	struct resource *res;
	u32 statusRegVal;

    dev_info(dev, "DMA driver Probe STARTED\n");

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if(!res) {
		dev_err(dev, "Failed to get memory resource\n");
		return -ENODEV;
	}

	dmaBaseAddr = devm_ioremap_resource(dev, res);
	if(IS_ERR(dmaBaseAddr)) {
		dev_err(dev, "Failed to ioremap\n");
        return PTR_ERR(dmaBaseAddr);
	}

   	dev_info(dev, "Successfully mapped physical addr 0x%llx to virtual addr %p\n", 
             (unsigned long long)res->start, dmaBaseAddr);

	statusRegVal = ioread32(dmaBaseAddr + DMA_STATUS_REG);
    dev_info(dev, "Read MM2S_DMASR (Offset 0x04): 0x%08X\n", statusRegVal);

    dev_info(dev, "DMA driver Probe DONE\n");
    return 0;
}

static int dmaRemove(struct platform_device *pdev) {
    dev_info(&pdev->dev, "Harel's DMA Driver Removed.\n");
    return 0;
}

/* Platform Driver Definition */
static struct platform_driver dmaPlatformDriver = {
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = dmaOfMatch,
    },
    .probe = dmaProbe,     
    .remove = dmaRemove, 
};

/* Init and Exit */
static int __init dmaInit(void) {
    pr_info("Init DMA module...START\n");
    return platform_driver_register(&dmaPlatformDriver);
	
}

static void __exit dmaExit(void) {
    pr_info("Exit DMA module...START\n");
    platform_driver_unregister(&dmaPlatformDriver);
    pr_info("Exit DMA module...DONE\n");
}

module_init(dmaInit);
module_exit(dmaExit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Harel Grecht");
MODULE_DESCRIPTION("Custom axi DMA driver");