#!/usr/bin/env bash
# =============================================================================
# 0_setupTftp.sh  [DUST]
# Configures the host TFTP server to serve files from a version directory.
#
# The TFTP server is used by U-Boot on the DUST board to load the FPGA
# bitstream and ramdisk before eMMC programming (scripts 2 & 3).
#
# Usage:
#   ./0_setupTftp.sh --ver <version>
#   ./0_setupTftp.sh --help
#
# Example:
#   ./0_setupTftp.sh --ver dustV1.0
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration – edit these before running
# ---------------------------------------------------------------------------

# Base directory that contains version subdirectories (where this script lives)
versionsBaseDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TFTPD-HPA config file
tftpConfigFile="/etc/default/tftpd-hpa"

# TFTP service name
tftpServiceName="tftpd-hpa"
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
    echo "  $(basename "$0") --ver <version>"
    echo ""
    echo -e "${colCyan}Options:${colReset}"
    echo "  --ver <version>   Name of the version folder to serve via TFTP"
    echo "                    (must be a subdirectory of: ${versionsBaseDir})"
    echo "  --help            Show this help message"
    echo ""
    echo -e "${colCyan}Available versions:${colReset}"
    local foundAny=false
    for dirEntry in "${versionsBaseDir}"/*/; do
        [[ -d "${dirEntry}" ]] && echo "  - $(basename "${dirEntry}")" && foundAny=true
    done
    [[ "${foundAny}" == false ]] && echo "  (none found)"
    echo ""
    echo -e "${colCyan}Example:${colReset}"
    echo "  $(basename "$0") --ver dustV1.0"
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

if [[ -z "${selectedVer}" ]]; then
    logError "--ver argument is required."
    echo ""
    printHelp
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve and validate version directory
# ---------------------------------------------------------------------------
versionDir="${versionsBaseDir}/${selectedVer}"

logBanner "DUST TFTP Setup – Version: ${selectedVer}"

if [[ ! -d "${versionDir}" ]]; then
    logError "Version directory not found: '${versionDir}'"
    echo ""
    printHelp
    exit 1
fi

logInfo "Version directory : ${versionDir}"
logInfo "TFTP config file  : ${tftpConfigFile}"

# ---------------------------------------------------------------------------
# Validate tftpd-hpa config file is accessible
# ---------------------------------------------------------------------------
if [[ ! -f "${tftpConfigFile}" ]]; then
    logError "TFTP config file not found at '${tftpConfigFile}'."
    logError "Is tftpd-hpa installed? Run: sudo apt install tftpd-hpa"
    exit 1
fi

# Show current setting
currentDir=$(grep -E '^TFTP_DIRECTORY=' "${tftpConfigFile}" | cut -d'"' -f2 || echo "(not set)")
logInfo "Current TFTP_DIRECTORY: ${currentDir}"
logInfo "New     TFTP_DIRECTORY: ${versionDir}"

# ---------------------------------------------------------------------------
# Update TFTP_DIRECTORY in config file
# ---------------------------------------------------------------------------
logInfo "Updating ${tftpConfigFile} ..."
sudo sed -i "s|^TFTP_DIRECTORY=.*|TFTP_DIRECTORY=\"${versionDir}\"|" "${tftpConfigFile}"

# Verify the update
newDir=$(grep -E '^TFTP_DIRECTORY=' "${tftpConfigFile}" | cut -d'"' -f2)
if [[ "${newDir}" != "${versionDir}" ]]; then
    logError "Failed to update TFTP_DIRECTORY. Check permissions on ${tftpConfigFile}."
    exit 1
fi

# Fix permissions so tftpd can read the version directory
logInfo "Setting TFTP read permissions on '${versionDir}' ..."
sudo chmod -R a+r "${versionDir}"
sudo chmod a+x  "${versionDir}"

# ---------------------------------------------------------------------------
# Restart TFTP service
# ---------------------------------------------------------------------------
logInfo "Restarting ${tftpServiceName} ..."
sudo systemctl restart "${tftpServiceName}"

# Confirm service is active
if sudo systemctl is-active --quiet "${tftpServiceName}"; then
    logInfo "Service '${tftpServiceName}' is running."
else
    logError "Service '${tftpServiceName}' failed to start."
    sudo systemctl status "${tftpServiceName}" --no-pager || true
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
logBanner "TFTP server configured for version '${selectedVer}'"
logInfo "Files now served from: ${versionDir}"
logWarn "U-Boot commands to load FPGA + ramdisk:"
echo "    run load_fpga_tftp"
echo "    run load_ramdisk_tftp"
