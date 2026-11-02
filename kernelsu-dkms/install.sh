#!/bin/bash
# install.sh - Install KernelSU DKMS module for Waydroid
# Run as root: sudo ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KERNELSU_VERSION="3.3.1"
MODULE_NAME="kernelsu"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'

log_info() { echo -e "${BLUE}[+] $*${RESET}"; }
log_ok() { echo -e "${GREEN}[✓] $*${RESET}"; }
log_warn() { echo -e "${YELLOW}[!] $*${RESET}"; }
log_err() { echo -e "${RED}[✗] $*${RESET}"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    log_err "Please run as root (use sudo)"
    exit 1
fi

# Check kernel headers
KVERSION=$(uname -r)
if [ ! -d "/lib/modules/${KVERSION}/build" ]; then
    log_err "Kernel headers not found for ${KVERSION}"
    log_info "Install with: apt install linux-headers-${KVERSION}"
    exit 1
fi
log_ok "Kernel headers found: ${KVERSION}"

# Check required kernel configs
log_info "Checking kernel configuration..."
REQUIRED_CONFIGS=("CONFIG_KPROBES" "CONFIG_EXT4_FS" "CONFIG_KALLSYMS" "CONFIG_MODULES")
for config in "${REQUIRED_CONFIGS[@]}"; do
    if grep -q "^${config}=[ym]" "/boot/config-${KVERSION}" 2>/dev/null; then
        log_ok "${config}=y/m"
    elif [ -r /proc/config.gz ] && zcat /proc/config.gz 2>/dev/null | grep -q "^${config}=[ym]"; then
        log_ok "${config}=y/m"
    else
        log_warn "${config} not found in kernel config - module may not work"
    fi
done

# Check for SELinux
if grep -q "^CONFIG_SECURITY_SELINUX=y" "/boot/config-${KVERSION}" 2>/dev/null || \
   zcat "/proc/config.gz" 2>/dev/null | grep -q "^CONFIG_SECURITY_SELINUX=y"; then
    log_ok "SELinux support detected in kernel"
    : SELINUX_AVAILABLE=1
else
    log_warn "SELinux not in kernel config - CONFIG_KSU_SELINUX will be disabled"
    : SELINUX_AVAILABLE=0
fi

# Check for x86_64
if [ "$(uname -m)" = "x86_64" ]; then
    log_ok "x86_64 architecture - CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER will be enabled"
    : X86_64=1
else
    log_info "Non-x86 architecture - CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER not applicable"
    : X86_64=0
fi

# Fetch and prepare source
log_info "Fetching KernelSU source..."
./fetch-kernelsu.sh

# Add to DKMS (remove any previous copy first so re-runs work)
log_info "Adding to DKMS..."
dkms remove -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" --all 2>/dev/null || true
dkms add -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}"

# Build
log_info "Building module with DKMS..."
dkms build -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" --force

# Install
log_info "Installing module..."
dkms install -m "${MODULE_NAME}" -v "${KERNELSU_VERSION}" --force

# Install modprobe config
log_info "Installing modprobe configuration..."
install -Dm644 "${SCRIPT_DIR}/00-kernelsu.conf" /etc/modprobe.d/00-kernelsu.conf

# Install load script
log_info "Installing load script..."
install -Dm755 "${SCRIPT_DIR}/load-kernelsu" /usr/bin/load-kernelsu

# Install modloader if available
if [ -f "${SCRIPT_DIR}/modloader" ]; then
    log_info "Installing modloader..."
    install -Dm755 "${SCRIPT_DIR}/modloader" /usr/bin/modloader
else
    log_warn "modloader not found - downloading..."
    curl -L "https://github.com/shadichy/modloader/releases/download/v2.0.0/modloader-x86_64-glibc" -o /tmp/modloader
    install -Dm755 /tmp/modloader /usr/bin/modloader
fi

# Update module dependencies
log_info "Updating module dependencies..."
depmod -a "${KVERSION}"

# Verify module
log_info "Verifying module..."
if modinfo "${MODULE_NAME}" >/dev/null 2>&1; then
    log_ok "Module ${MODULE_NAME} installed successfully"
    modinfo "${MODULE_NAME}" | grep -E "^(filename|version|vermagic|depends):"
else
    log_err "Module verification failed"
    exit 1
fi

# Load module for testing
log_info "Testing module load..."
if load-kernelsu; then
    log_ok "Module loaded successfully"
    sleep 2
    dmesg -T | grep -i kernelsu | tail -5
    log_info "Unloading test module..."
    rmmod "${MODULE_NAME}" 2>/dev/null || true
else
    log_err "Module load test failed"
    dmesg -T | grep -i kernelsu | tail -10
    exit 1
fi

# Waydroid seccomp patch
if [ -f /var/lib/waydroid/lxc/waydroid/waydroid.seccomp ]; then
    log_info "Patching Waydroid seccomp profile..."
    cp /var/lib/waydroid/lxc/waydroid/waydroid.seccomp "/var/lib/waydroid/lxc/waydroid/waydroid.seccomp.bak.$(date +%s)"
    sed -i '/reboot/d' /var/lib/waydroid/lxc/waydroid/waydroid.seccomp
    log_ok "Waydroid seccomp patched (reboot syscall allowed)"
else
    log_info "Waydroid not installed or seccomp profile not found - skipping"
fi

echo
log_ok "=== Installation complete! ==="
echo
echo "To load KernelSU:"
echo "  sudo load-kernelsu"
echo
echo "To verify:"
echo "  lsmod | grep kernelsu"
echo "  dmesg | grep -i kernelsu"
echo
echo "For Waydroid:"
echo "  1. Start Waydroid session"
echo "  2. In container: su (should work via KernelSU)"
echo
echo "DKMS status:"
dkms status | grep kernelsu