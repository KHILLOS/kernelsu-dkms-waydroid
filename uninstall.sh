#!/bin/bash
# uninstall.sh - Remove KernelSU DKMS module
# Run as root: sudo ./uninstall.sh

set -euo pipefail

KERNELSU_VERSION="3.3.1"
MODULE_NAME="kernelsu"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'

log_info() { echo -e "${BLUE}[+] $*${RESET}"; }
log_ok() { echo -e "${GREEN}[✓] $*${RESET}"; }
log_warn() { echo -e "${YELLOW}[!] $*${RESET}"; }
log_err() { echo -e "${RED}[✗] $*${RESET}"; }

if [ "$EUID" -ne 0 ]; then
    log_err "Please run as root (use sudo)"
    exit 1
fi

# Unload module if loaded
if lsmod | grep -q "^${MODULE_NAME}"; then
    log_info "Unloading module..."
    rmmod "${MODULE_NAME}" 2>/dev/null || log_warn "Module may be in use"
fi

# Remove from DKMS
log_info "Removing from DKMS..."
dkms remove -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" --all 2>/dev/null || log_warn "DKMS remove failed or not installed"

# Remove modprobe config
log_info "Removing modprobe configuration..."
rm -f /etc/modprobe.d/00-kernelsu.conf

# Remove scripts
log_info "Removing scripts..."
rm -f /usr/bin/load-kernelsu
rm -f /usr/bin/modloader

# Remove DKMS source directory
DKMS_DIR="/usr/src/kernelsu-${KERNELSU_VERSION}"
if [ -d "${DKMS_DIR}" ]; then
    log_info "Removing DKMS source directory: ${DKMS_DIR}"
    rm -rf "${DKMS_DIR}"
fi

# Update module dependencies
log_info "Updating module dependencies..."
depmod -a "$(uname -r)"

# Restore Waydroid seccomp if backup exists
BACKUP=$(ls -t /var/lib/waydroid/lxc/waydroid/waydroid.seccomp.bak.* 2>/dev/null | head -1)
if [ -n "${BACKUP}" ]; then
    log_info "Restoring Waydroid seccomp from backup..."
    cp "${BACKUP}" /var/lib/waydroid/lxc/waydroid/waydroid.seccomp
    log_ok "Waydroid seccomp restored"
fi

log_ok "=== Uninstall complete ==="