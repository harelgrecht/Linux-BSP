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
# TODO: DUST – set the correct board IP address
boardIp="192.168.0.10"
# TODO: DUST – set the correct SSH username for the ramdisk
boardUser="dust"
# TODO: DUST – set the SSH password (leave empty for SSH key auth)
boardPassword="root"
# TODO: DUST – set the sudo password on the board (leave empty if NOPASSWD)
boardSudoPassword="root"

# eMMC root partition to package
# TODO: DUST – verify eMMC device name (check with: lsblk on the board)
emmcRootPart="/dev/mmcblk0p2"

# Temporary mount point on the board
boardMountPoint="/mnt/root"

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

logInfo "Connecting to board ..."

sshCmd bash -s << EOF
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

echo "[board] Unmounting partition if already mounted ..."
runSudo umount "\${rootPart}" 2>/dev/null || true

echo "[board] Mounting \${rootPart} at \${mountPoint} ..."
runSudo mkdir -p "\${mountPoint}"
runSudo mount "\${rootPart}" "\${mountPoint}"

echo "[board] Creating rootfs tarball in /dev/shm (RAM) ..."
echo "[board] This may take a few minutes ..."
runSudo tar \
    -C "\${mountPoint}" \
    --numeric-owner \
    --exclude=./proc \
    --exclude=./sys \
    --exclude=./dev \
    --exclude=./run \
    --exclude=./tmp \
    -czpfv "\${tmpTar}" \
    .

echo "[board] Rootfs packaged successfully."
echo "[board] Tarball size: \$(du -sh "\${tmpTar}" | cut -f1)"

echo "[board] Unmounting \${rootPart} ..."
runSudo umount "\${mountPoint}"

echo "[board] Changing ownership of tarball to user ..."
runSudo chown \$(id -u):\$(id -g) "\${tmpTar}"

echo "[board] Ready for download."
EOF

# ---------------------------------------------------------------------------
# Step 2 – Copy the tarball from the board to the host
# ---------------------------------------------------------------------------
logInfo "Downloading tarball from board to '${outputPath}' ..."
logWarn "This may take several minutes depending on rootfs size and network speed."

scpGetCmd "${boardUser}@${boardIp}:${boardTmpTar}" "${outputPath}"

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
