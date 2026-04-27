#!/usr/bin/env bash
# =============================================================================
# 2_burnEmmcBoot.sh  [DUST]
# Partitions the DUST board eMMC and writes image.ub + system.bit to the
# FAT32 boot partition (mmcblk0p1).
#
# Usage:
#   ./2_burnEmmcBoot.sh [--ver <version>]
#   ./2_burnEmmcBoot.sh --help
#
# Example:
#   ./2_burnEmmcBoot.sh --ver dustV1.0
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Static configuration – always required
# ---------------------------------------------------------------------------
boardIp="192.168.0.10"
boardUser="dust"
boardPassword="root"     # SSH password – leave empty to use SSH key auth
boardSudoPassword="root" # sudo password on the board – leave empty if NOPASSWD

# Destination directory on the board for uploaded files
boardUploadDir="/home/dust"

# eMMC block device on the board (DUST: eMMC is mmcblk1, SD card is mmcblk0)
emmcDevice="/dev/mmcblk1"
emmcBootPart="${emmcDevice}p1"
# NOTE: p2 (root partition) is formatted and populated by 3_burnEmmcRootfs.sh

# Mount point for boot partition on the board
boardBootMount="/home/dust/bootFiles"

# ---------------------------------------------------------------------------
# Default file paths (used when --ver is NOT supplied)
# ---------------------------------------------------------------------------
imageUbPath="./image.ub"
systemBitPath="./system.bit"
extraEnvPath="./uboot.env" 

# Base directory containing version subdirectories
versionsBaseDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------

# ANSI colour helpers
colGreen='\033[0;32m'
colYellow='\033[1;33m'
colRed='\033[0;31m'
colCyan='\033[0;36m'
colReset='\033[0m'

logInfo()   { echo -e "${colGreen}[INFO]${colReset}  $*"; }
logWarn()   { echo -e "${colYellow}[WARN]${colReset}  $*"; }
logError()  { echo -e "${colRed}[ERROR]${colReset} $*" >&2; }
logBanner() {
    echo -e "\n${colGreen}========================================${colReset}"
    echo -e "${colGreen}  $*${colReset}"
    echo -e "${colGreen}========================================${colReset}\n"
}

printHelp() {
    echo -e "${colCyan}Usage:${colReset}"
    echo "  $(basename "$0") [--ver <version>]"
    echo ""
    echo -e "${colCyan}Options:${colReset}"
    echo "  --ver <version>   Use files from ./<version>/  (image.ub, system.bit)"
    echo "  --help            Show this help message"
    echo ""
    echo -e "${colCyan}Available versions:${colReset}"
    local foundAny=false
    for dirEntry in "${versionsBaseDir}"/*/; do
        [[ -d "${dirEntry}" ]] && echo "  - $(basename "${dirEntry}")" && foundAny=true
    done
    [[ "${foundAny}" == false ]] && echo "  (none found)"
}

sshCmd() {
    if [[ -n "${boardPassword}" ]]; then
        sshpass -p "${boardPassword}" ssh -o StrictHostKeyChecking=no \
            "${boardUser}@${boardIp}" "$@"
    else
        ssh -o StrictHostKeyChecking=no "${boardUser}@${boardIp}" "$@"
    fi
}

scpCmd() {
    if [[ -n "${boardPassword}" ]]; then
        sshpass -p "${boardPassword}" scp -o StrictHostKeyChecking=no "$@"
    else
        scp -o StrictHostKeyChecking=no "$@"
    fi
}

# Remove any stale host key for the board (ramdisk regenerates keys on every boot)
cleanBoardHostKey() {
    logInfo "Removing stale known_hosts entry for ${boardIp} ..."
    ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${boardIp}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
selectedVer=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ver)
            [[ -z "${2:-}" ]] && { logError "--ver requires a value."; exit 1; }
            selectedVer="$2"
            shift 2
            ;;
        --help|-h)
            printHelp
            exit 0
            ;;
        *)
            logError "Unknown argument: '$1'"
            printHelp
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve file paths from version directory (if --ver supplied)
# ---------------------------------------------------------------------------
if [[ -n "${selectedVer}" ]]; then
    versionDir="${versionsBaseDir}/${selectedVer}"
    if [[ ! -d "${versionDir}" ]]; then
        logError "Version directory not found: '${versionDir}'"
        printHelp
        exit 1
    fi
    imageUbPath="${versionDir}/image.ub"
    systemBitPath="${versionDir}/system.bit"
    extraEnvPath="${versionDir}/uboot.env"

fi

# ---------------------------------------------------------------------------
# Step 1 – Validate source files
# ---------------------------------------------------------------------------
logBanner "DUST eMMC Programmer – Step 2/3: Burn Boot Partition${selectedVer:+ [${selectedVer}]}"

missingFiles=0
for filePath in "${imageUbPath}" "${systemBitPath}" "${extraEnvPath}"; do
    if [[ ! -f "${filePath}" ]]; then
        logError "Required file not found: '${filePath}'"
        missingFiles=$((missingFiles + 1))
    fi
done

if [[ "${missingFiles}" -gt 0 ]]; then
    logError "Missing ${missingFiles} required file(s). Aborting."
    if [[ -z "${selectedVer}" ]]; then
        logWarn "Tip: use --ver <version> to load files from a version directory."
        logWarn "Example: $(basename "$0") --ver dustV1.0"
        logWarn "Run $(basename "$0") --help to see available versions."
    fi
    exit 1
fi

logInfo "Version    : ${selectedVer:-<default paths>}"
logInfo "image.ub   : ${imageUbPath}"
logInfo "system.bit : ${systemBitPath}"
logInfo "uboot.env  : ${extraEnvPath}"


# ---------------------------------------------------------------------------
# Step 2 – Copy source files to the board
# ---------------------------------------------------------------------------
cleanBoardHostKey
logInfo "Transferring image.ub and system.bit to ${boardUser}@${boardIp}:${boardUploadDir}/ ..."
scpCmd "${imageUbPath}" "${systemBitPath}" "${extraEnvPath}" "${boardUser}@${boardIp}:${boardUploadDir}/"
logInfo "Transfer complete."

# ---------------------------------------------------------------------------
# Step 3 – Partition, format, and populate the boot partition on the board
# ---------------------------------------------------------------------------
logInfo "Connecting to board to partition and program eMMC boot partition ..."

sshCmd bash -s << EOF
set -euo pipefail

emmcDev="${emmcDevice}"
emmcBootPart="${emmcBootPart}"
bootMount="${boardBootMount}"
uploadDir="${boardUploadDir}"
sudoPass="${boardSudoPassword}"

# sudo wrapper: pipes password via -S when set, otherwise uses plain sudo
runSudo() {
    if [[ -n "\${sudoPass}" ]]; then
        echo "\${sudoPass}" | sudo -S "\$@" 2>/dev/null
    else
        sudo "\$@"
    fi
}

echo "[board] Unmounting boot partition if mounted ..."
runSudo umount "\${emmcBootPart}" 2>/dev/null || true

echo "[board] Repartitioning \${emmcDev} ..."
# d 1  -> delete existing p1
# n p 1 <start> +1G -> 1 GiB FAT32 boot partition
# w -> write
runSudo fdisk "\${emmcDev}" << 'FDISK_CMDS'
d
1
n
p
1

+1G

w
FDISK_CMDS

echo "[board] Waiting for kernel to re-read partition table ..."
runSudo partprobe "\${emmcDev}" 2>/dev/null || runSudo blockdev --rereadpt "\${emmcDev}" || true
sleep 2

echo "[board] Formatting boot partition (p1) as FAT32 ..."
runSudo mkfs.vfat -F 32 -n "boot" "\${emmcBootPart}"

sync

echo "[board] Mounting boot partition at \${bootMount} ..."
runSudo mkdir -p "\${bootMount}"
runSudo mount "\${emmcBootPart}" "\${bootMount}"

echo "[board] Copying image.ub and system.bit to boot partition ..."
runSudo mv "\${uploadDir}/image.ub"    "\${bootMount}/"
runSudo mv "\${uploadDir}/system.bit"  "\${bootMount}/"
runSudo mv "\${uploadDir}/uboot.env"   "\${bootMount}/"

echo "[board] Syncing ..."
sync

echo "[board] Unmounting boot partition ..."
runSudo umount "\${bootMount}"

echo "[board] eMMC boot partition (p1) programming complete."
EOF

logBanner "eMMC boot partition (p1) successfully programmed!"
logWarn "p2 (root partition) is unformatted – run 3_burnEmmcRootfs.sh next."