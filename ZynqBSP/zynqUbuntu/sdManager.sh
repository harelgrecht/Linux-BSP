#!/bin/bash

# ==========================================
# Configuration
# ==========================================
targetDevice="/dev/mmcblk0"
defaultImageName="zynqSdCardBackup.img.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ==========================================
# Helper Functions (camelCase)
# ==========================================

checkRoot() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run as root (sudo).${NC}"
        exit 1
    fi
}

checkDevice() {
    if [ ! -b "$targetDevice" ]; then
        echo -e "${RED}Error: Device $targetDevice not found!${NC}"
        echo "Please check if SD card is inserted."
        exit 1
    fi
}

unmountPartitions() {
    echo -e "${YELLOW}Unmounting partitions on $targetDevice...${NC}"
    umount ${targetDevice}* 2>/dev/null
    echo "Done."
}

backupToPc() {
    local imageFile=${1:-$defaultImageName}
    
    echo -e "${GREEN}Starting Backup:${NC}"
    echo "Source: $targetDevice"
    echo "Destination: $imageFile"
    
    unmountPartitions
    
    echo -e "${YELLOW}Reading and compressing data... (This may take time)${NC}"
    dd if="$targetDevice" bs=4M status=progress | gzip > "$imageFile"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup completed successfully! Image saved as: $imageFile${NC}"
    else
        echo -e "${RED}Backup failed!${NC}"
    fi
}

flashToSd() {
    local imageFile=${1:-$defaultImageName}

    if [ ! -f "$imageFile" ]; then
        echo -e "${RED}Error: Image file '$imageFile' not found.${NC}"
        exit 1
    fi

    echo -e "${RED}WARNING: This will DELETE ALL DATA on $targetDevice${NC}"
    echo "Source Image: $imageFile"
    read -p "Are you sure you want to continue? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 0
    fi

    unmountPartitions

    echo -e "${YELLOW}Flashing image to SD card...${NC}"
    gunzip -c "$imageFile" | dd of="$targetDevice" bs=4M status=progress

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Flashing completed successfully!${NC}"
        # Optional: Resize partition command could go here
    else
        echo -e "${RED}Flashing failed!${NC}"
    fi
}

showUsage() {
    echo "Usage: $0 [mode] [image_name]"
    echo ""
    echo "Modes:"
    echo "  -b, --backup   Create an image from SD card to PC"
    echo "  -r, --restore  Write an image from PC to SD card"
    echo ""
    echo "Examples:"
    echo "  sudo $0 --backup"
    echo "  sudo $0 --backup myCustomImage.img.gz"
    echo "  sudo $0 --restore"
    exit 1
}

# ==========================================
# Main Execution
# ==========================================

checkRoot

case "$1" in
    -b|--backup)
        checkDevice
        backupToPc "$2"
        ;;
    -r|--restore)
        checkDevice
        flashToSd "$2"
        ;;
    *)
        showUsage
        ;;
esac