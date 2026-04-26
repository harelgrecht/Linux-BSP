#!/usr/bin/env bash
# =============================================================================
# 1_burnFlash.sh  [DUST]
# Programs the DUST board QSPI flash with BOOT.BIN using Xilinx program_flash
# (part of the Vitis / Vivado toolchain), connected via JTAG.
# Target SoC: Xilinx Zynq-7000
#
# Usage:
#   ./1_burnFlash.sh [--ver <version>]
#   ./1_burnFlash.sh --help
#
# Example:
#   ./1_burnFlash.sh --ver dustV1.0
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration – edit these before running
# ---------------------------------------------------------------------------

# Path to the Vitis / Vivado installation (the one that contains program_flash)
vitisInstallDir="/opt/xilinx/Vitis/2023.1"

# ---------------------------------------------------------------------------
# Default file paths (used when --ver is NOT supplied)
# ---------------------------------------------------------------------------
# Path to BOOT.BIN on this host machine
bootBinPath="./BOOT.BIN"

# Path to the FSBL ELF (required by program_flash to initialise the PS over JTAG)
# NOTE: Zynq-7000 uses zynq_fsbl.elf (NOT zynqmp_fsbl.elf which is for ZynqMP/KR260)
fsblElfPath="./zynq_fsbl.elf"

# Base directory that contains version subdirectories
versionsBaseDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Flash type for the DUST board QSPI
# TODO: DUST – verify flash type on your specific hardware (run: program_flash -partlist)
# Common Zynq-7000 flash types: qspi-x4-single, qspi-x1-single
flashType="qspi-x4-single"

# Flash offset to write BOOT.BIN at (0x0 = start of flash)
flashOffset="0x0"

# hw_server URL (default: local, port 3121)
hwServerUrl="tcp:localhost:3121"

# Set to "true" to auto-start hw_server if not already running
autoStartHwServer=true

# Set to "true" to blank-check the flash before programming
doBlankCheck=false

# Set to "true" to verify the flash after programming
doVerify=false

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
    echo "  --ver <version>   Use BOOT.BIN and fsbl.elf from ./<version>/"
    echo "  --help            Show this help message"
    echo ""
    echo -e "${colCyan}Available versions:${colReset}"
    local foundAny=false
    for dirEntry in "${versionsBaseDir}"/*/; do
        [[ -d "${dirEntry}" ]] && echo "  - $(basename "${dirEntry}")" && foundAny=true
    done
    [[ "${foundAny}" == false ]] && echo "  (none found)"
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
    bootBinPath="${versionDir}/BOOT.BIN"
    # Zynq-7000 FSBL is named zynq_fsbl.elf (ZynqMP uses zynqmp_fsbl.elf)
    fsblElfPath="${versionDir}/zynq_fsbl.elf"
fi

# ---------------------------------------------------------------------------
# Resolve tool paths
# ---------------------------------------------------------------------------
programFlashBin="${vitisInstallDir}/bin/program_flash"
hwServerBin="${vitisInstallDir}/bin/hw_server"

# ---------------------------------------------------------------------------
# Step 1 – Validate tools and source files
# ---------------------------------------------------------------------------
logBanner "DUST Flash Programmer – Step 1/3: Burn QSPI Flash via JTAG${selectedVer:+ [${selectedVer}]}"

exitCode=0

if [[ ! -x "${programFlashBin}" ]]; then
    logError "program_flash not found (or not executable) at '${programFlashBin}'."
    logError "Check that vitisInstallDir is set correctly."
    exitCode=1
fi

if [[ ! -f "${bootBinPath}" ]]; then
    logError "BOOT.BIN not found at '${bootBinPath}'."
    exitCode=1
fi

if [[ ! -f "${fsblElfPath}" ]]; then
    logError "zynqmp_fsbl.elf not found at '${fsblElfPath}'."
    logError "Build it from your PetaLinux project: images/linux/zynqmp_fsbl.elf"
    exitCode=1
fi

[[ "${exitCode}" -ne 0 ]] && exit "${exitCode}"

logInfo "Version       : ${selectedVer:-<default paths>}"
logInfo "program_flash : ${programFlashBin}"
logInfo "BOOT.BIN      : ${bootBinPath}"
logInfo "FSBL ELF      : ${fsblElfPath}"
logInfo "Flash type    : ${flashType}"
logInfo "HW server     : ${hwServerUrl}"

# ---------------------------------------------------------------------------
# Step 2 – Ensure hw_server is running
# ---------------------------------------------------------------------------
hwServerRunning=false
if pgrep -x "hw_server" &>/dev/null; then
    hwServerRunning=true
    logInfo "hw_server is already running."
fi

if [[ "${hwServerRunning}" == false ]]; then
    if [[ "${autoStartHwServer}" == true ]]; then
        if [[ ! -x "${hwServerBin}" ]]; then
            logError "hw_server not found at '${hwServerBin}'. Cannot auto-start."
            exit 1
        fi
        logInfo "Starting hw_server in the background ..."
        "${hwServerBin}" &
        hwServerPid=$!
        sleep 2

        if ! kill -0 "${hwServerPid}" 2>/dev/null; then
            logError "hw_server failed to start. Check JTAG cable connection."
            exit 1
        fi
        logInfo "hw_server started (PID ${hwServerPid})."
    else
        logWarn "hw_server is not running and autoStartHwServer=false."
        logWarn "Start hw_server manually, then re-run this script."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 3 – Build the program_flash argument list
# ---------------------------------------------------------------------------
programFlashArgs=(
    -f      "${bootBinPath}"
    -fsbl   "${fsblElfPath}"
    -flash_type "${flashType}"
    -offset "${flashOffset}"
)

[[ "${doBlankCheck}" == true ]] && programFlashArgs+=(-blank_check)
[[ "${doVerify}"     == true ]] && programFlashArgs+=(-verify)

# ---------------------------------------------------------------------------
# Step 4 – Program the flash
# ---------------------------------------------------------------------------
logInfo "Running program_flash ..."
logInfo "Command: ${programFlashBin} ${programFlashArgs[*]}"
echo ""

"${programFlashBin}" "${programFlashArgs[@]}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
logBanner "QSPI Flash successfully programmed with BOOT.BIN!"
logWarn "Set the boot-mode switches back to QSPI boot mode."
logWarn "Power-cycle the board and use run load_ramdisk_tftp to continue flashing."
