#!/usr/bin/env bash
# =============================================================================
# 4_packageRootfs.sh  [DUST]
# Packages the rootfs currently installed on the DUST board eMMC (p2)
# into a tarball and copies it back to this host machine.
#
# The board must be running a PetaLinux ramdisk (loaded via TFTP) so that
# the eMMC root partition is NOT actively in use.
#
# Usage:
#   ./4_packageRootfs.sh [--ver <version>] [--name <filename>]
#   ./4_packageRootfs.sh --help
#
# Examples:
#   ./4_packageRootfs.sh --ver dustV1.1
#   ./4_packageRootfs.sh --ver dustV1.1 --name rootfs-custom.tar.gz
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Static configuration – always required
# ---------------------------------------------------------------------------
# set the correct board IP address
boardIp="192.168.0.10"
# set the correct SSH username for the ramdisk
boardUser="dust"
# set the SSH password (leave empty for SSH key auth)
boardPassword="root"
# set the sudo password on the board (leave empty if NOPASSWD)
boardSudoPassword="root"

# eMMC root partition to package (DUST: eMMC is mmcblk1, so root is mmcblk1p2)
emmcRootPart="/dev/mmcblk1p2"

# Temporary mount point on the board
boardMountPoint="/mnt/rootFS"

# Temporary tarball path on the board (in /dev/shm = RAM, avoids eMMC writes)
boardTmpTar="/dev/shm/rootfs-package-tmp.tar.gz"

# Base directory that contains version subdirectories
versionsBaseDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default output directory on the host
outputDir="${versionsBaseDir}"

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
    echo "  $(basename "$0") [--ver <version>] [--name <filename>]"
    echo ""
    echo -e "${colCyan}Options:${colReset}"
    echo "  --ver  <version>   Save tarball into ./<version>/ directory"
    echo "  --name <filename>  Override the output filename (default: auto-generated with date)"
    echo "  --help             Show this help message"
    echo ""
    echo -e "${colCyan}Available versions:${colReset}"
    local foundAny=false
    for dirEntry in "${versionsBaseDir}"/*/; do
        [[ -d "${dirEntry}" ]] && echo "  - $(basename "${dirEntry}")" && foundAny=true
    done
    [[ "${foundAny}" == false ]] && echo "  (none found)"
    echo ""
    echo -e "${colCyan}Examples:${colReset}"
    echo "  $(basename "$0") --ver dustV1.1"
    echo "  $(basename "$0") --ver dustV1.1 --name rootfs-custom.tar.gz"
}

sshCmd() {
    if [[ -n "${boardPassword}" ]]; then
        sshpass -p "${boardPassword}" ssh -o StrictHostKeyChecking=no \
            "${boardUser}@${boardIp}" "$@"
    else
        ssh -o StrictHostKeyChecking=no "${boardUser}@${boardIp}" "$@"
    fi
}

scpGetCmd() {
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

checkBoardReachable() {
    logInfo "Checking board is reachable at ${boardIp} ..."
    if ! ping -c 1 -W 3 "${boardIp}" &>/dev/null; then
        logError "Board at ${boardIp} is NOT reachable."
        logError "  → Is the board running the ramdisk? (U-Boot: run load_ramdisk_tftp)"
        logError "  → Is the Ethernet cable connected?"
        logError "  → Is your host on the same subnet? (ip addr show)"
        exit 1
    fi
    logInfo "Board reachable. Testing SSH ..."
    if ! sshCmd true 2>/dev/null; then
        logError "SSH to ${boardUser}@${boardIp} failed."
        logError "  → Check boardUser (\"${boardUser}\") and boardPassword (\"${boardPassword}\")"
        logError "  → Is sshpass installed? sudo apt install sshpass"
        exit 1
    fi
    logInfo "SSH connection OK."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
selectedVer=""
customName=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ver)
            [[ -z "${2:-}" ]] && { logError "--ver requires a value."; exit 1; }
            selectedVer="$2"
            shift 2
            ;;
        --name)
            [[ -z "${2:-}" ]] && { logError "--name requires a value."; exit 1; }
            customName="$2"
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
# Resolve output path
# ---------------------------------------------------------------------------
if [[ -n "${customName}" ]]; then
    outputFileName="$(basename "${customName}")"
else
    outputFileName="rootfs-DUST-$(date +%Y%m%d-%H%M%S).tar.gz"
fi

if [[ -n "${selectedVer}" ]]; then
    versionDir="${versionsBaseDir}/${selectedVer}"
    if [[ ! -d "${versionDir}" ]]; then
        logWarn "Version directory '${versionDir}' does not exist – creating it."
        mkdir -p "${versionDir}"
    fi
    outputDir="${versionDir}"
fi

outputPath="${outputDir}/${outputFileName}"

# ---------------------------------------------------------------------------
# Banner & summary
# ---------------------------------------------------------------------------
logBanner "DUST RootFS Packager${selectedVer:+ [→ ${selectedVer}]}"
logInfo "Board           : ${boardUser}@${boardIp}"
logInfo "eMMC partition  : ${emmcRootPart}"
logInfo "Output file     : ${outputPath}"

# ---------------------------------------------------------------------------
# Step 1 – Connect to the board and package the rootfs
# ---------------------------------------------------------------------------
cleanBoardHostKey
checkBoardReachable

# ---------------------------------------------------------------------------
# Step 1 – Package the rootfs on the board
# ---------------------------------------------------------------------------
logInfo "Starting rootfs packaging on board ..."

sshCmd bash -s << ENDSSH
set -euo pipefail

rootPart="${emmcRootPart}"
mountPoint="${boardMountPoint}"
tmpTar="${boardTmpTar}"
sudoPass="${boardSudoPassword}"

runSudo() {
    if [[ -n "\${sudoPass}" ]]; then
        echo "\${sudoPass}" | sudo -S "\$@" 2>/dev/null
    else
        sudo "\$@"
    fi
}

runSudo rm -f "\${tmpTar}" 2>/dev/null || true

echo "[board] Unmounting \${rootPart} if already mounted ..."
runSudo umount "\${rootPart}" 2>/dev/null || true

echo "[board] Mounting \${rootPart} at \${mountPoint} ..."
runSudo mkdir -p "\${mountPoint}"
if ! runSudo mount "\${rootPart}" "\${mountPoint}"; then
    echo "[board] ERROR: Could not mount \${rootPart}."
    echo "[board]        Is the eMMC programmed? Check: lsblk"
    exit 1
fi

echo "[board] Creating rootfs tarball in /dev/shm (RAM) ..."
echo "[board] Progress shown every 3 seconds ..."

runSudo tar \
    -C "\${mountPoint}" \
    --numeric-owner \
    --exclude=./proc \
    --exclude=./sys \
    --exclude=./dev \
    --exclude=./run \
    --exclude=./tmp \
    -czpf "\${tmpTar}" \
    . &
TAR_PID=\$!

while kill -0 \${TAR_PID} 2>/dev/null; do
    SIZE=\$(du -sh "\${tmpTar}" 2>/dev/null | cut -f1 || echo "...")
    echo -ne "[board] Progress: \${SIZE} written\r"
    sleep 3
done
wait \${TAR_PID}
TAR_EXIT=\$?
echo ""

if [[ "\${TAR_EXIT}" -ne 0 ]]; then
    echo "[board] ERROR: tar failed (exit \${TAR_EXIT}). Check free RAM: free -h"
    exit 1
fi

echo "[board] Tarball size: \$(du -sh "\${tmpTar}" | cut -f1)"

echo "[board] Unmounting \${rootPart} ..."
runSudo umount "\${mountPoint}"

echo "[board] Fixing tarball ownership ..."
runSudo chown \$(id -u):\$(id -g) "\${tmpTar}"

echo "[board] Ready for download."
ENDSSH

# ---------------------------------------------------------------------------
# Step 2 – Copy the tarball from the board to the host
# ---------------------------------------------------------------------------
logInfo "Downloading tarball from board → '${outputPath}' ..."
logWarn "This may take several minutes depending on rootfs size and network speed."

if ! scpGetCmd "${boardUser}@${boardIp}:${boardTmpTar}" "${outputPath}"; then
    logError "SCP download failed."
    logError "  → Is the board still reachable? (ping ${boardIp})"
    logError "  → Is ${boardTmpTar} present on the board?"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 3 – Clean up the temp tarball on the board
# ---------------------------------------------------------------------------
logInfo "Cleaning up temporary tarball on board ..."
sshCmd "rm -f '${boardTmpTar}'" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
outputSize=$(du -sh "${outputPath}" | cut -f1)
logBanner "RootFS packaged successfully!"
logInfo "Saved to : ${outputPath}"
logInfo "Size     : ${outputSize}"

if [[ -n "${selectedVer}" ]]; then
    logInfo ""
    logInfo "To re-flash this rootfs onto a new board, run:"
    logInfo "  ./3_burnEmmcRootfs.sh --ver ${selectedVer}"
fi
