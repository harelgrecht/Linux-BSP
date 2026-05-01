#!/usr/bin/env bash
# =============================================================================
# 3_burnEmmcRootfs.sh  [DUST]
# Formats the DUST board eMMC root partition (mmcblk0p2) as ext4 and extracts
# the rootfs tarball into it. Optionally installs kernel modules.
#
# When --ver is used, the rootfs tarball and modules tarball are located
# automatically by glob-matching inside the version directory.
#
# Usage:
#   ./3_burnEmmcRootfs.sh [--ver <version>]
#   ./3_burnEmmcRootfs.sh --help
#
# Example:
#   ./3_burnEmmcRootfs.sh --ver dustV1.0
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

# eMMC root partition on the board
emmcDevice="/dev/mmcblk1"
emmcRootPart="${emmcDevice}p2"

# Mount point for root partition on the board
boardRootMount="/home/dust/rootFiles"

# ---------------------------------------------------------------------------
# Default file paths (used when --ver is NOT supplied)
# Set modulesTarPath="" to skip kernel module installation.
# ---------------------------------------------------------------------------
rootfsTarPath="./rootfs.tar.gz"
modulesTarPath=""

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
    echo "  --ver <version>   Use files from ./<version>/"
    echo "                    Rootfs:  first *.tar.gz found in version dir"
    echo "                    Modules: first modules-*.tgz found in version dir"
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
            -o ConnectTimeout=10 "${boardUser}@${boardIp}" "$@"
    else
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${boardUser}@${boardIp}" "$@"
    fi
}

scpCmd() {
    if [[ -n "${boardPassword}" ]]; then
        sshpass -p "${boardPassword}" scp -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 "$@"
    else
        scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$@"
    fi
}

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
# Uses glob matching so exact filenames don't need to be hard-coded.
# ---------------------------------------------------------------------------
if [[ -n "${selectedVer}" ]]; then
    versionDir="${versionsBaseDir}/${selectedVer}"
    if [[ ! -d "${versionDir}" ]]; then
        logError "Version directory not found: '${versionDir}'"
        printHelp
        exit 1
    fi

    # Auto-discover rootfs tarball (first *.tar.gz in version dir)
    rootfsGlob=("${versionDir}"/*.tar.gz)
    if [[ -f "${rootfsGlob[0]}" ]]; then
        rootfsTarPath="${rootfsGlob[0]}"
    else
        logError "No *.tar.gz rootfs tarball found in '${versionDir}'."
        exit 1
    fi

    # Auto-discover modules tarball (first modules-*.tgz in version dir)
    modulesGlob=("${versionDir}"/modules-*.tgz)
    if [[ -f "${modulesGlob[0]}" ]]; then
        modulesTarPath="${modulesGlob[0]}"
    else
        modulesGlob2=("${versionDir}"/modules--*.tgz)
        if [[ -f "${modulesGlob2[0]}" ]]; then
            modulesTarPath="${modulesGlob2[0]}"
        else
            logWarn "No modules-*.tgz found in '${versionDir}'. Kernel module install will be skipped."
            modulesTarPath=""
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Step 1 – Validate source files
# ---------------------------------------------------------------------------
logBanner "DUST eMMC Programmer – Step 3/3: Burn RootFS Partition${selectedVer:+ [${selectedVer}]}"

if [[ ! -f "${rootfsTarPath}" ]]; then
    logError "Rootfs tarball not found at '${rootfsTarPath}'. Aborting."
    if [[ -z "${selectedVer}" ]]; then
        logWarn "Tip: use --ver <version> to load files from a version directory."
        logWarn "Example: $(basename "$0") --ver dustV1.0"
        logWarn "Run $(basename "$0") --help to see available versions."
    fi
    exit 1
fi
logInfo "Found rootfs tarball: '$(basename "${rootfsTarPath}")'."

installModules=false
if [[ -n "${modulesTarPath}" && -f "${modulesTarPath}" ]]; then
    installModules=true
    logInfo "Found kernel modules tarball: '$(basename "${modulesTarPath}")'."
elif [[ -n "${modulesTarPath}" ]]; then
    logWarn "Modules tarball set but not found: '${modulesTarPath}'. Skipping."
else
    logInfo "No modules tarball configured – skipping kernel module installation."
fi

logInfo "Version      : ${selectedVer:-<default paths>}"
logInfo "Rootfs       : ${rootfsTarPath}"
logInfo "Modules      : ${modulesTarPath:-<none>}"

# ---------------------------------------------------------------------------
# Step 2 – Copy files to the board
# ---------------------------------------------------------------------------
cleanBoardHostKey
checkBoardReachable
logInfo "Transferring rootfs tarball to ${boardUser}@${boardIp}:${boardUploadDir}/ ..."
logWarn "This may take several minutes depending on file size and network speed."
scpCmd "${rootfsTarPath}" "${boardUser}@${boardIp}:${boardUploadDir}/"

if [[ "${installModules}" == true ]]; then
    logInfo "Transferring modules tarball ..."
    scpCmd "${modulesTarPath}" "${boardUser}@${boardIp}:${boardUploadDir}/"
fi

logInfo "Transfer complete."

# Determine remote filenames
rootfsTarRemote="${boardUploadDir}/$(basename "${rootfsTarPath}")"
modulesTarRemote="${boardUploadDir}/$(basename "${modulesTarPath:-}")"

# ---------------------------------------------------------------------------
# Step 3 – Format root partition and extract rootfs on the board
# ---------------------------------------------------------------------------
logInfo "Connecting to board to write rootfs to eMMC root partition ..."

sshCmd bash -s << EOF
set -euo pipefail

emmcDev="${emmcDevice}"
rootPart="${emmcRootPart}"
rootMount="${boardRootMount}"
rootfsTar="${rootfsTarRemote}"
modulesTar="${modulesTarRemote}"
doModules="${installModules}"
sudoPass="${boardSudoPassword}"

# sudo wrapper: pipes password via -S when set, otherwise uses plain sudo
runSudo() {
    if [[ -n "\${sudoPass}" ]]; then
        echo "\${sudoPass}" | sudo -S "\$@" 2>/dev/null
    else
        sudo "\$@"
    fi
}

echo "[board] Unmounting root partition if mounted ..."
runSudo umount "\${rootPart}" 2>/dev/null || true

echo "[board] Re-creating p2 on \${emmcDev} ..."
runSudo fdisk "\${emmcDev}" << 'FDISK_CMDS'
d
2
n
p
2


w
FDISK_CMDS

echo "[board] Waiting for kernel to re-read partition table ..."
runSudo partprobe "\${emmcDev}" 2>/dev/null || runSudo blockdev --rereadpt "\${emmcDev}" || true
sleep 2

echo "[board] Formatting \${rootPart} as ext4 ..."
runSudo mkfs.ext4 -L "fs" "\${rootPart}"

echo "[board] Mounting root partition at \${rootMount} ..."
runSudo mkdir -p "\${rootMount}"
runSudo mount "\${rootPart}" "\${rootMount}"

echo "[board] Extracting Ubuntu rootfs – this will take a while ..."
runSudo tar -xzpf "\${rootfsTar}" -C "\${rootMount}"
sync
echo "[board] Rootfs extraction complete."

if [[ "\${doModules}" == true ]]; then
    echo "[board] Installing kernel modules ..."
    tmpModDir="/run/mod_tmp_\$\$"
    runSudo mkdir -p "\${tmpModDir}"
    runSudo tar -xzf "\${modulesTar}" -C "\${tmpModDir}"
    runSudo cp -rf "\${tmpModDir}/lib/modules/" "\${rootMount}/lib/modules/."
    runSudo rm -rf "\${tmpModDir}"
    echo "[board] Kernel modules installed."
fi

sync
echo "[board] Syncing filesystem ..."
runSudo umount "\${rootMount}"
echo "[board] Root partition unmounted. eMMC rootfs programming complete."
EOF

logBanner "Ubuntu rootfs successfully written to eMMC!"
logInfo "Summary of completed steps:"
logInfo "  1. QSPI flash programmed with BOOT.BIN        (1_burnFlash.sh)"
logInfo "  2. eMMC boot partition programmed              (2_burnEmmcBoot.sh)"
logInfo "  3. eMMC root partition populated with rootfs   (3_burnEmmcRootfs.sh)"
logWarn "Power-cycle the board and switch boot mode to eMMC to boot Ubuntu."