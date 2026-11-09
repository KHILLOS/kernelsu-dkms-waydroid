#!/bin/bash
# waydroid-setup.sh - Configure Waydroid for KernelSU root access
# Run as root: sudo ./waydroid-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check Waydroid installation
if ! command -v waydroid >/dev/null 2>&1; then
    log_err "Waydroid not installed"
    exit 1
fi
log_ok "Waydroid found"

# Check if Waydroid is initialized
if [ ! -d /var/lib/waydroid/images ]; then
    log_err "Waydroid not initialized. Run: waydroid init"
    exit 1
fi
log_ok "Waydroid initialized"

# Check KernelSU module
if ! modinfo kernelsu >/dev/null 2>&1; then
    log_err "KernelSU module not installed. Run install.sh first"
    exit 1
fi
log_ok "KernelSU module installed"

# Ensure KernelSU is loaded
if ! cat /proc/modules | grep -q "^kernelsu "; then
    log_info "Loading KernelSU module..."
    load-kernelsu
    sleep 2
    if ! cat /proc/modules | grep -q "^kernelsu "; then
        log_err "Failed to load KernelSU module"
        exit 1
    fi
    log_ok "KernelSU module loaded"
else
    log_ok "KernelSU module already loaded"
fi

# Check Waydroid container status
log_info "Checking Waydroid container..."
if ! waydroid status | grep -q "Session: RUNNING"; then
    log_info "Starting Waydroid session..."
    waydroid session start &
    sleep 5
fi

# Wait for container to be ready
log_info "Waiting for Waydroid container..."
for _ in {1..30}; do
    if waydroid shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
        break
    fi
    sleep 1
done

# Push KernelSU userspace components to container
log_info "Setting up KernelSU in Waydroid container..."

# Create kernel directory in container
waydroid shell mkdir -p /data/adb/ksu 2>/dev/null || true
waydroid shell mkdir -p /data/adb/ksu/bin 2>/dev/null || true

# The KernelSU userspace (ksud) communicates via netlink/sockets
# We need to ensure the container can communicate with the host module
# This is handled by the kernel module's LSM hooks and syscall handling

# Install KernelSU manager APK if available
MANAGER_APK="${SCRIPT_DIR}/KernelSU.apk"
if [ -f "${MANAGER_APK}" ]; then
    log_info "Installing KernelSU Manager APK..."
    waydroid app install "${MANAGER_APK}" 2>/dev/null || log_warn "APK install failed (may already be installed)"
else
    log_warn "KernelSU Manager APK not found at ${MANAGER_APK}"
    log_info "Download from: https://github.com/tiann/KernelSU/releases"
fi

# Verify root access in container
log_info "Testing root access in Waydroid..."
if waydroid shell su -c "id" 2>/dev/null | grep -q "uid=0"; then
    log_ok "Root access working in Waydroid!"
    waydroid shell su -c "id"
else
    log_warn "Root access test failed - checking dmesg..."
    dmesg -T | grep -i kernelsu | tail -5
fi

# Check SELinux status in container
log_info "Checking SELinux status in container..."
waydroid shell getenforce 2>/dev/null || log_warn "Could not get SELinux status"

# Ensure binder is working
log_info "Checking binder..."
if cat /proc/modules | grep -q "^binder "; then
    log_ok "binder module loaded"
else
    log_warn "binder module not loaded - Waydroid may have issues"
    log_info "Try: modprobe binder_linux devices=binder,hwbinder,vndbinder"
fi

echo
log_ok "=== Waydroid setup complete ==="
echo
echo "Next steps:"
echo "  1. Open KernelSU Manager app in Waydroid"
echo "  2. Grant root permissions to desired apps"
echo "  3. Test with: waydroid shell su -c 'whoami'"
echo
echo "If root doesn't work:"
echo "  - Check dmesg: dmesg -T | grep -i kernelsu"
echo "  - Ensure KernelSU module is loaded: lsmod | grep kernelsu"
echo "  - Check Waydroid logs: waydroid log"