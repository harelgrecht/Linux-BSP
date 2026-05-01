#!/usr/bin/env bash
# =============================================================================
# 2_burnEmmcBoot.sh  [MUST / KR260]
# Partitions the KR260 eMMC and writes image.ub + system.bit to the
# FAT32 boot partition (mmcblk0p1).
#
# Usage:
#   ./2_burnEmmcBoot.sh [--ver <version>] [--only image|bit]
#   ./2_burnEmmcBoot.sh --help
#
# Examples:
#   ./2_burnEmmcBoot.sh --ver mustV3.1               # Full repartition + both files
#   ./2_burnEmmcBoot.sh --ver mustV3.1 --only image  # Replace image.ub only
#   ./2_burnEmmcBoot.sh --ver mustV3.1 --only bit    # Replace system.bit only
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Static configuration – edit these before running
# ---------------------------------------------------------------------------
boardIp="192.168.0.10"
boardUser="petalinux"
boardPassword="root"     # SSH password – leave empty to use SSH key auth
boardSudoPassword="root" # sudo password on the board – leave empty if NOPASSWD

boardUploadDir="/home/petalinux"
boardBootMount="/home/petalinux/bootFiles"

# eMMC device (KR260: eMMC is mmcblk0)
emmcDevice="/dev/mmcblk0"
emmcBootPart="${emmcDevice}p1"

# Default file paths (used when --ver is NOT supplied)
imageUbPath="./image.ub"
systemBitPath="./system.bit"

versionsBaseDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
colGreen='\033[0;32m'; colYellow='\033[1;33m'
colRed='\033[0;31m';   colCyan='\033[0;36m';  colReset='\033[0m'

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
    echo "  $(basename "$0") [--ver <version>] [--only image|bit]"
    echo ""
    echo -e "${colCyan}Options:${colReset}"
    echo "  --ver  <version>  Load files from ./<version>/ directory"
    echo "  --only image      Transfer & update image.ub only (no repartition)"
    echo "  --only bit        Transfer & update system.bit only (no repartition)"
    echo "  --help            Show this help"
    echo ""
    echo -e "${colCyan}Modes:${colReset}"
    echo "  Full (default)  : Wipes + repartitions eMMC, copies both files"
    echo "  Partial (--only): Mounts existing p1, replaces the selected file only"
    echo ""
    echo -e "${colCyan}Available versions:${colReset}"
    local foundAny=false
    for d in "${versionsBaseDir}"/*/; do
        [[ -d "$d" ]] && echo "  - $(basename "$d")" && foundAny=true
    done
    [[ "${foundAny}" == false ]] && echo "  (none found)"
}

sshCmd() {
    if [[ -n "${boardPassword}" ]]; then
        sshpass -p "${boardPassword}" ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=10 "${boardUser}@${boardIp}" "$@"
    else
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            "${boardUser}@${boardIp}" "$@"
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
        logError "Checklist:"
        logError "  1. Ethernet cable connected?"
        logError "  2. Board powered on and running ramdisk?"
        logError "     In U-Boot: run load_fpga_tftp && run load_ramdisk_tftp"
        logError "  3. Host IP on same subnet? Check: ip addr show"
        logError "     Set:  sudo ip addr add 192.168.0.1/24 dev eth0"
        logError "  4. boardIp correct? Current: \"${boardIp}\""
        exit 1
    fi
    logInfo "Board reachable. Testing SSH ..."
    if ! sshCmd true 2>/dev/null; then
        logError "SSH to ${boardUser}@${boardIp} failed."
        logError "Checklist:"
        logError "  1. Ramdisk fully booted? (Wait for login prompt on UART)"
        logError "  2. boardUser correct? Current: \"${boardUser}\""
        logError "  3. boardPassword correct? Current: \"${boardPassword}\""
        logError "  4. sshpass installed? Run: sudo apt install sshpass"
        exit 1
    fi
    logInfo "SSH connection OK."
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
selectedVer=""
onlyFile=""   # "" = full, "image" = image.ub only, "bit" = system.bit only

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ver)
            [[ -z "${2:-}" ]] && { logError "--ver requires a value."; exit 1; }
            selectedVer="$2"; shift 2 ;;
        --only)
            [[ -z "${2:-}" ]] && { logError "--only requires: image or bit"; exit 1; }
            case "${2}" in
                image|bit) onlyFile="${2}" ;;
                *) logError "--only must be 'image' or 'bit' (got '${2}')"; exit 1 ;;
            esac
            shift 2 ;;
        --help|-h) printHelp; exit 0 ;;
        *) logError "Unknown argument: '$1'"; printHelp; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve version directory
# ---------------------------------------------------------------------------
if [[ -n "${selectedVer}" ]]; then
    versionDir="${versionsBaseDir}/${selectedVer}"
    if [[ ! -d "${versionDir}" ]]; then
        logError "Version directory not found: '${versionDir}'"
        logError "Run $(basename "$0") --help to list available versions."
        exit 1
    fi
    imageUbPath="${versionDir}/image.ub"
    systemBitPath="${versionDir}/system.bit"
fi

# ---------------------------------------------------------------------------
# Step 1 – Validate source files
# ---------------------------------------------------------------------------
modeLabel="Full (wipe + repartition + both files)"
[[ "${onlyFile}" == "image" ]] && modeLabel="Partial – image.ub only (no repartition)"
[[ "${onlyFile}" == "bit"   ]] && modeLabel="Partial – system.bit only (no repartition)"

logBanner "KR260 eMMC Programmer – Step 2/3: Burn Boot Partition${selectedVer:+ [${selectedVer}]}"
logInfo "Mode       : ${modeLabel}"
logInfo "Version    : ${selectedVer:-<default paths>}"

missingFiles=0
if [[ "${onlyFile}" != "bit" && ! -f "${imageUbPath}" ]]; then
    logError "image.ub not found at '${imageUbPath}'"
    ((missingFiles++)) || true
fi
if [[ "${onlyFile}" != "image" && ! -f "${systemBitPath}" ]]; then
    logError "system.bit not found at '${systemBitPath}'"
    ((missingFiles++)) || true
fi
if [[ "${missingFiles}" -gt 0 ]]; then
    logError "Missing ${missingFiles} required file(s). Aborting."
    [[ -z "${selectedVer}" ]] && logWarn "Tip: use --ver <version>. Run --help for available versions."
    exit 1
fi
[[ "${onlyFile}" != "bit"   ]] && logInfo "image.ub   : ${imageUbPath}"
[[ "${onlyFile}" != "image" ]] && logInfo "system.bit : ${systemBitPath}"

# ---------------------------------------------------------------------------
# Step 2 – Connectivity pre-flight
# ---------------------------------------------------------------------------
cleanBoardHostKey
checkBoardReachable

# ---------------------------------------------------------------------------
# Step 3 – Transfer files
# ---------------------------------------------------------------------------
logInfo "Transferring to ${boardUser}@${boardIp}:${boardUploadDir}/ ..."
[[ "${onlyFile}" != "bit"   ]] && { logInfo "  → image.ub";   scpCmd "${imageUbPath}"   "${boardUser}@${boardIp}:${boardUploadDir}/"; }
[[ "${onlyFile}" != "image" ]] && { logInfo "  → system.bit"; scpCmd "${systemBitPath}" "${boardUser}@${boardIp}:${boardUploadDir}/"; }
logInfo "Transfer complete."

# ---------------------------------------------------------------------------
# Step 4 – Partition / update boot partition on the board
# ---------------------------------------------------------------------------
logInfo "Connecting to board ..."

sshCmd bash -s << EOF
set -euo pipefail

emmcDev="${emmcDevice}"
emmcBootPart="${emmcBootPart}"
bootMount="${boardBootMount}"
uploadDir="${boardUploadDir}"
sudoPass="${boardSudoPassword}"
onlyFile="${onlyFile}"

runSudo() {
    if [[ -n "\${sudoPass}" ]]; then
        echo "\${sudoPass}" | sudo -S "\$@" 2>/dev/null
    else
        sudo "\$@"
    fi
}

if [[ -z "\${onlyFile}" ]]; then
    # ── FULL MODE: wipe → repartition → format → copy both ───────────────
    echo "[board] Unmounting all partitions on \${emmcDev} ..."
    for part in "\${emmcDev}"p*; do
        runSudo umount "\${part}" 2>/dev/null || true
    done

    echo "[board] Wiping partition table on \${emmcDev} ..."
    # Zero the MBR so fdisk always sees a completely blank disk –
    # this works on brand-new SOMs and disks with any existing layout.
    runSudo dd if=/dev/zero of="\${emmcDev}" bs=512 count=1 2>/dev/null

    echo "[board] Creating partitions (p1=1GiB FAT32, p2=rest ext4) ..."
    printf 'n\np\n1\n\n+1G\nn\np\n2\n\n\nw\n' | runSudo fdisk "\${emmcDev}"

    echo "[board] Waiting for partition table re-read ..."
    runSudo partprobe "\${emmcDev}" 2>/dev/null || \
        runSudo blockdev --rereadpt "\${emmcDev}" || true
    sleep 2

    echo "[board] Formatting p1 as FAT32 ..."
    runSudo mkfs.vfat -F 32 -n "boot-firmware" "\${emmcBootPart}"
    sync

    echo "[board] Mounting p1 at \${bootMount} ..."
    runSudo mkdir -p "\${bootMount}"
    runSudo mount "\${emmcBootPart}" "\${bootMount}"

    echo "[board] Copying image.ub and system.bit ..."
    runSudo mv "\${uploadDir}/image.ub"   "\${bootMount}/"
    runSudo mv "\${uploadDir}/system.bit" "\${bootMount}/"

else
    # ── PARTIAL MODE: mount existing p1, replace one file ────────────────
    echo "[board] Mounting existing boot partition at \${bootMount} ..."
    runSudo mkdir -p "\${bootMount}"
    runSudo mount "\${emmcBootPart}" "\${bootMount}" 2>/dev/null || {
        echo "[board] ERROR: Could not mount \${emmcBootPart}."
        echo "[board]        Run without --only to do a full repartition first."
        exit 1
    }

    if [[ "\${onlyFile}" == "image" ]]; then
        echo "[board] Replacing image.ub ..."
        runSudo cp "\${uploadDir}/image.ub" "\${bootMount}/image.ub"
    elif [[ "\${onlyFile}" == "bit" ]]; then
        echo "[board] Replacing system.bit ..."
        runSudo cp "\${uploadDir}/system.bit" "\${bootMount}/system.bit"
    fi
fi

sync
echo "[board] Syncing ..."
runSudo umount "\${bootMount}"
echo "[board] Boot partition unmounted. Done."
EOF

logBanner "eMMC boot partition programmed successfully!"
if [[ -z "${onlyFile}" ]]; then
    logWarn "p2 (root partition) is unformatted – run 3_burnEmmcRootfs.sh next."
fi
