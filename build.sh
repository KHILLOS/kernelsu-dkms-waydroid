#!/bin/bash
# build.sh - one-shot build for the KernelSU Waydroid DKMS module
#
# Runs the full pipeline with a verification gate at the end:
#   fetch upstream -> apply patches -> dkms add/build -> verify linkage
#
# Usage:
#   sudo ./build.sh            # build + verify
#   sudo ./build.sh --clean    # remove previous build first
#
# Requires: dkms, git, patch, make, gcc, kernel headers for the running kernel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="kernelsu"
KERNELSU_VERSION="${KERNELSU_VERSION:-3.3.1}"
KVERSION="${KVERSION_OVERRIDE:-$(uname -r)}"

RED='\033[1;31m'; GREEN='\033[1;32m'; BLUE='\033[1;34m'; RESET='\033[0m'
info() { echo -e "${BLUE}[+]${RESET} $*"; }
ok()   { echo -e "${GREEN}[✓]${RESET} $*"; }
die()  { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }

[ "${EUID}" -eq 0 ] || die "Please run as root (use sudo)"

export PATH="${PATH}:/usr/sbin:/sbin"

for tool in dkms git patch make gcc modinfo depmod; do
    command -v "${tool}" >/dev/null 2>&1 || die "Required tool not found: ${tool}"
done

KDIR="/lib/modules/${KVERSION}/build"
[ -d "${KDIR}" ] || KDIR="/usr/lib/modules/${KVERSION}/build"
[ -d "${KDIR}" ] || die "Kernel headers not found for ${KVERSION}. Install linux-headers-${KVERSION}."

if [ "${1:-}" = "--clean" ]; then
    info "Removing previous DKMS build..."
    dkms remove -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" --all >/dev/null 2>&1 || true
    rm -rf "/usr/src/${MODULE_NAME}-${KERNELSU_VERSION}"
fi

info "Fetching and preparing KernelSU v${KERNELSU_VERSION}..."
bash "${SCRIPT_DIR}/fetch-kernelsu.sh" >/dev/null || die "fetch-kernelsu.sh failed"

info "Adding to DKMS..."
dkms remove -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" --all >/dev/null 2>&1 || true
dkms add -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" >/dev/null || die "dkms add failed"

info "Building for ${KVERSION}..."
dkms build -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" -k "${KVERSION}" \
    --kernelsourcedir "${KDIR}" 2>&1 | tail -3
ok "Build finished"

info "Verifying module linkage..."
if KVERSION_OVERRIDE="${KVERSION}" "${SCRIPT_DIR}/verify-build.sh"; then
    ok "Build verified - install with: sudo ./install.sh"
else
    die "Verification failed - the built module is not loadable"
fi
