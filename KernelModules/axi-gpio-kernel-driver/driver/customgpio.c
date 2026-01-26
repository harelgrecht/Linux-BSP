#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gpio/driver.h>
#include <linux/io.h>
#include <linux/platform_device.h>

#define DRIVER_NAME "customgpio"
#define GPIO_BASE_ADDR 0xA0000000
#define GPIO_TRI_OFFSET 0x04

static void __iomem *gpio_base;
static struct gpio_chip custom_gpio_chip;

/* Read GPIO value */
static int gpio_get(struct gpio_chip *chip, unsigned int offset) {
    u32 reg_val;
    reg_val = ioread32(gpio_base);
    return (reg_val >> offset) & 1;
}

/* Set GPIO value */
static void gpio_set(struct gpio_chip *chip, unsigned int offset, int value) {
    u32 reg_val;
    reg_val = ioread32(gpio_base);
    if (value == 1)
        reg_val |= (1 << offset);
    else
        reg_val &= ~(1 << offset);
    iowrite32(reg_val, gpio_base);
    reg_val = ioread32(gpio_base);
}

/* Set GPIO direction to input */
static int gpio_direction_input(struct gpio_chip *chip, unsigned int offset) {
    u32 reg_val;
    reg_val = ioread32(gpio_base + GPIO_TRI_OFFSET);
    reg_val |= (1 << offset); // Set bit for input
    iowrite32(reg_val, gpio_base + GPIO_TRI_OFFSET);
    return 0;
}

/* Set GPIO direction to output */
static int gpio_direction_output(struct gpio_chip *chip, unsigned int offset, int value) {
    u32 reg_val;
    reg_val = ioread32(gpio_base + GPIO_TRI_OFFSET);
    reg_val &= ~(1 << offset); // Clear bit for output
    iowrite32(reg_val, gpio_base + GPIO_TRI_OFFSET);
    return 0;
}

static int __init gpio_init(void) {
    int ret;
    printk(KERN_INFO "AXI GPIO Custom Driver Init\n");

    gpio_base = ioremap(GPIO_BASE_ADDR, 0x08);
    if(!gpio_base){
        printk(KERN_ERR "Mapping GPIO base failed\n");
        return -ENOMEM;
    } else {
        printk(KERN_INFO "Mapping GPIO base succeeded\n");
    }

    custom_gpio_chip.label = DRIVER_NAME;
    custom_gpio_chip.base = -1; // let the krenel choose a base number dynamclly
    custom_gpio_chip.ngpio = 2; // number of gpios
    custom_gpio_chip.parent = NULL;
    custom_gpio_chip.owner = THIS_MODULE;
    custom_gpio_chip.get = gpio_get;
    custom_gpio_chip.set = gpio_set;
    custom_gpio_chip.direction_input = gpio_direction_input;
    custom_gpio_chip.direction_output = gpio_direction_output;

    ret = gpiochip_add_data(&custom_gpio_chip, NULL);
    if(ret) {
        printk(KERN_ERR "gpiochip add data failed\n");
        iounmap(gpio_base);
        return ret;
    }
    printk(KERN_INFO "GPIO module Loaded\n");
    return 0;
}

static void __exit gpio_exit(void) {
    gpiochip_remove(gpio_base);
    if(gpio_base)
        iounmap(gpio_base);
    printk(KERN_INFO "GPIO module unloaded\n");
}

module_init(gpio_init);
module_exit(gpio_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Harel");
MODULE_DESCRIPTION("Custom AXI GPIO Driver");