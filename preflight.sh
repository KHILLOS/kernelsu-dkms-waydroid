#!/bin/bash
# preflight.sh - Pre-flight checks for KernelSU DKMS on Waydroid
# Run as regular user (uses sudo when needed)

set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RESET='\033[0m'

PASS=0
WARN=0
FAIL=0

log_info() { echo -e "${BLUE}[*] $*${RESET}"; }
log_ok() { echo -e "${GREEN}[✓] $*${RESET}"; PASS=$((PASS+1)); }
log_warn() { echo -e "${YELLOW}[!] $*${RESET}"; WARN=$((WARN+1)); }
log_err() { echo -e "${RED}[✗] $*${RESET}"; FAIL=$((FAIL+1)); }

run_check() {
    local name="$1"
    shift
    log_info "Checking $name..."
    if "$@"; then
        log_ok "$name"
        return 0
    else
        log_err "$name"
        return 1
    fi
}

# ============================================================
# KERNEL CHECKS
# ============================================================
KVERSION=$(uname -r)
log_info "Kernel version: ${KVERSION}"

# Kernel headers
run_check "Kernel headers" test -d "/lib/modules/${KVERSION}/build"

# Required kernel configs
check_config() {
    local config="$1"
    if grep -qE "^${config}=[ym]" "/boot/config-${KVERSION}" 2>/dev/null; then
        return 0
    fi
    if grep -qE "^${config}=\".+\"$" "/boot/config-${KVERSION}" 2>/dev/null; then
        return 0
    fi
    if [ -r /proc/config.gz ]; then
        if zcat /proc/config.gz 2>/dev/null | grep -qE "^${config}=([ym]|\".+\")$"; then
            return 0
        fi
    fi
    return 1
}

run_check "CONFIG_KPROBES" check_config CONFIG_KPROBES
run_check "CONFIG_EXT4_FS" check_config CONFIG_EXT4_FS
run_check "CONFIG_KALLSYMS" check_config CONFIG_KALLSYMS
run_check "CONFIG_MODULES" check_config CONFIG_MODULES
run_check "CONFIG_MODULE_UNLOAD" check_config CONFIG_MODULE_UNLOAD
run_check "CONFIG_KALLSYMS_ALL" check_config CONFIG_KALLSYMS_ALL

# Recommended configs
# CONFIG_KSU_SELINUX is always "n" for DKMS builds (the SELinux backend needs
# kernel-private headers no distro ships), so the host's SELinux state only
# affects how root escalation is labelled - it is informational, not a failure.
if check_config CONFIG_SECURITY_SELINUX; then
    log_info "Host kernel has SELinux; note this build uses the no-op KSU SELinux backend"
else
    log_info "Host kernel has no SELinux; the no-op KSU SELinux backend is used"
fi
run_check "CONFIG_SECURITY" check_config CONFIG_SECURITY
run_check "CONFIG_LSM" check_config CONFIG_LSM
run_check "CONFIG_HAVE_KPROBES" check_config CONFIG_HAVE_KPROBES
run_check "CONFIG_KPROBE_EVENTS" check_config CONFIG_KPROBE_EVENTS
run_check "CONFIG_UPROBES" check_config CONFIG_UPROBES

# Architecture specific
if [ "$(uname -m)" = "x86_64" ]; then
    run_check "CONFIG_X86_64" check_config CONFIG_X86_64
    # Not a real kernel config; the KernelSU Kconfig option is KSU_X86_PATCH_SYSCALL_DISPATCHER.
    log_warn "CONFIG_SYSCALL_DISPATCHER is not a kernel config; KernelSU handles this via CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y"
fi

# ============================================================
# TOOLS CHECKS
# ============================================================
run_check "dkms" command -v dkms
run_check "git" command -v git
run_check "make" command -v make
run_check "gcc" command -v gcc
run_check "modprobe" command -v modprobe
run_check "modinfo" command -v modinfo
run_check "depmod" command -v depmod
run_check "lsmod" command -v lsmod
run_check "rmmod" command -v rmmod
run_check "insmod" command -v insmod

# ============================================================
# BINDER CHECKS (Waydroid requirement)
# ============================================================
log_info "Checking binder support..."
if lsmod | grep -q "^binder_linux"; then
    log_ok "binder_linux module loaded"
else
    if modinfo binder_linux >/dev/null 2>&1; then
        log_warn "binder_linux module available but not loaded"
        log_info "  Load with: sudo modprobe binder_linux devices=binder,hwbinder,vndbinder"
    else
        log_err "binder_linux module not available - install linux-headers and rebuild"
    fi
fi

# Check binder devices
for dev in binder hwbinder vndbinder; do
    if [ -e "/dev/${dev}" ]; then
        log_ok "/dev/${dev} exists"
    else
        log_warn "/dev/${dev} not found"
    fi
done

# ============================================================
# DKMS CHECKS
# ============================================================
log_info "Checking DKMS status..."
if dkms status | grep -q "kernelsu"; then
    log_ok "KernelSU already in DKMS"
    dkms status | grep kernelsu
else
    log_info "KernelSU not yet in DKMS (will be added by install.sh)"
fi

# ============================================================
# WAYDROID CHECKS
# ============================================================
log_info "Checking Waydroid..."
if command -v waydroid >/dev/null 2>&1; then
    log_ok "Waydroid installed"
    waydroid version 2>/dev/null || true
else
    log_warn "Waydroid not installed"
fi

if [ -d /var/lib/waydroid/images ]; then
    log_ok "Waydroid initialized"
    # Check system image
    if [ -f /var/lib/waydroid/images/system.img ]; then
        log_ok "System image present"
    else
        log_warn "System image not found"
    fi
else
    log_warn "Waydroid not initialized (run: waydroid init)"
fi

# Waydroid seccomp profile
if [ -f /var/lib/waydroid/lxc/waydroid/waydroid.seccomp ]; then
    log_ok "Waydroid seccomp profile found"
    if grep -q "reboot" /var/lib/waydroid/lxc/waydroid/waydroid.seccomp; then
        log_warn "reboot syscall blocked in seccomp (will be patched by install.sh)"
    else
        log_ok "reboot syscall already allowed"
    fi
else
    log_info "Waydroid seccomp profile not found (will be created on first run)"
fi

# ============================================================
# SECURE BOOT CHECKS
# ============================================================
log_info "Checking Secure Boot status..."
if [ -d /sys/firmware/efi ]; then
    log_info "UEFI boot detected"
    if command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
            log_warn "Secure Boot ENABLED - kernel modules must be signed"
            log_info "  Options:"
            log_info "  1. Disable Secure Boot in BIOS"
            log_info "  2. Sign module with MOK (Machine Owner Key)"
            log_info "  3. Use modloader (included) which bypasses signature check"
        else
            log_ok "Secure Boot disabled"
        fi
    else
        log_warn "mokutil not installed - cannot check Secure Boot state"
    fi
else
    log_ok "Legacy BIOS boot (Secure Boot not applicable)"
fi

# ============================================================
# EXISTING KERNELSU CHECK
# ============================================================
if lsmod | grep -q "^kernelsu"; then
    log_info "KernelSU module currently loaded"
    modinfo kernelsu | grep -E "^(filename|version|vermagic):"
fi

# ============================================================
# SUMMARY
# ============================================================
echo
echo "================== SUMMARY =================="
echo -e "${GREEN}Passed: ${PASS}${RESET}"
echo -e "${YELLOW}Warnings: ${WARN}${RESET}"
echo -e "${RED}Failed: ${FAIL}${RESET}"
echo "============================================="

if [ $FAIL -gt 0 ]; then
    echo
    log_err "Pre-flight checks FAILED. Fix the above issues before installing."
    exit 1
elif [ $WARN -gt 0 ]; then
    echo
    log_warn "Pre-flight checks passed with warnings. Installation may work but review warnings."
    exit 0
else
    echo
    log_ok "All pre-flight checks PASSED. Ready to install."
    exit 0
fi