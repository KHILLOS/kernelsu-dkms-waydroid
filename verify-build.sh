#!/bin/bash
# verify-build.sh - prove the DKMS module links before shipping it
#
# This is the check that was missing: the module used to build "successfully"
# while containing unresolved symbols, so it could never be loaded.  Run this
# after `fetch-kernelsu.sh` + `dkms build`, or from CI.
#
# Usage:
#   sudo ./verify-build.sh                 # verify whatever DKMS built
#   sudo ./verify-build.sh --no-sudo       # same, when already root
#
# Exit codes: 0 = healthy, 1 = problems found, 2 = nothing built yet.

set -uo pipefail

MODULE_NAME="kernelsu"
KERNELSU_VERSION="${KERNELSU_VERSION:-3.3.1}"
KVERSION=$(uname -r)

RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[✓]${RESET} $*"; }
bad()  { echo -e "${RED}[✗]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
info() { echo -e "${BLUE}[*]${RESET} $*"; }

FAIL=0

KVERSION="${KVERSION_OVERRIDE:-$KVERSION}"
KDIR="/lib/modules/${KVERSION}/build"
[ -d "${KDIR}" ] || KDIR="/usr/lib/modules/${KVERSION}/build"

# ---------------------------------------------------------------- locate .ko
info "Kernel: ${KVERSION}"
# Search order matters: an installed module under /lib/modules is the one that
# will actually be loaded, so prefer it over the DKMS build tree.
KO=""
for dir in "/lib/modules/${KVERSION}" "/usr/lib/modules/${KVERSION}"; do
    [ -d "${dir}" ] || continue
    KO=$(find "${dir}" -name "${MODULE_NAME}.ko*" 2>/dev/null | head -n1)
    [ -n "${KO}" ] && break
done
# Not installed yet (dkms build without dkms install): use the DKMS build output.
if [ -z "${KO}" ] && [ -d "/var/lib/dkms/${MODULE_NAME}/${KERNELSU_VERSION}" ]; then
    KO=$(find "/var/lib/dkms/${MODULE_NAME}/${KERNELSU_VERSION}" -path "*${KVERSION}*" \
            -name "${MODULE_NAME}.ko*" 2>/dev/null | head -n1)
fi

if [ -z "${KO}" ]; then
    warn "No ${MODULE_NAME}.ko found for ${KVERSION} - nothing to verify"
    echo "    Build it first:"
    echo "      sudo ./fetch-kernelsu.sh"
    echo "      sudo dkms add -m ${MODULE_NAME} -v ${KERNELSU_VERSION}"
    echo "      sudo dkms build -m ${MODULE_NAME} -v ${KERNELSU_VERSION}"
    exit 2
fi
ok "Found module: ${KO}"

# ---------------------------------------------------------------- decompress
TMPKO=$(mktemp /tmp/verify-XXXXXX.ko)
trap 'rm -f "${TMPKO}"' EXIT

case "${KO}" in
    *.xz)  xz -dc "${KO}" > "${TMPKO}" ;;
    *.zst) zstd -dc "${KO}" > "${TMPKO}" ;;
    *.gz)  gzip -dc "${KO}" > "${TMPKO}" ;;
    *)     cp "${KO}" "${TMPKO}" ;;
esac

if [ ! -s "${TMPKO}" ]; then
    bad "Could not decompress ${KO}"
    exit 1
fi

# ---------------------------------------------------------------- vermagic
VM=$(modinfo -F vermagic "${TMPKO}" 2>/dev/null | awk '{print $1}')
if [ "${VM}" = "${KVERSION}" ]; then
    ok "vermagic matches running kernel (${VM})"
else
    bad "vermagic mismatch: module built for '${VM}', kernel is '${KVERSION}'"
    FAIL=1
fi

# ---------------------------------------------------------------- undefined symbols
# Every undefined symbol must be resolvable: either it is exported by the kernel
# (appears in Module.symvers) or it lives in vmlinux.  A DKMS module may only
# reference exported symbols, and modpost enforces that at build time - this
# re-checks the finished artifact so KBUILD_MODPOST_WARN can never hide it again.
SYMVERS="${KDIR}/Module.symvers"
UNDEF=$(nm -u "${TMPKO}" 2>/dev/null | awk '{print $2}' | sort -u)
UNDEF_COUNT=$(printf '%s\n' "${UNDEF}" | grep -c . || true)

# Internal KernelSU / SELinux helpers must never appear: if one does, an object
# was dropped from the build (the original CONFIG_KSU_SELINUX=n bug).
INTERNAL=$(printf '%s\n' "${UNDEF}" | \
    grep -E '^(ksu_|handle_sepolicy$|getenforce$|setenforce$|is_ksu_domain$|is_task_ksu_domain$|is_zygote$|is_init$|is_adbd$|cache_sid$|setup_selinux$|setup_ksu_cred$|apply_kernelsu_rules$|escape_to_root_for_adb_root$)' || true)

if [ -n "${INTERNAL}" ]; then
    bad "Unresolved internal symbols (an object is missing from the build):"
    printf '%s\n' "${INTERNAL}" | sed 's/^/      /'
    FAIL=1
else
    ok "No unresolved internal symbols (${UNDEF_COUNT} external, all kernel-side)"
fi

# Symbols we already know live in vmlinux and are NOT in Debian/Ubuntu
# Module.symvers (which lists module exports only), so keep a small allowlist
# to avoid false positives when --strict is used.
KNOWN_VMLINUX="tasklist_lock init_mm"
if [ -f "${SYMVERS}" ] && [ "${UNDEF_COUNT}" -gt 0 ]; then
    MISSING=""
    while IFS= read -r sym; do
        [ -n "${sym}" ] || continue
        if grep -qw "${sym}" "${SYMVERS}" 2>/dev/null; then
            continue
        fi
        case " ${KNOWN_VMLINUX} " in *" ${sym} "*) continue ;; esac
        MISSING="${MISSING}${sym}"$'\n'
    done <<< "${UNDEF}"
    if [ -n "${MISSING}" ]; then
        warn "Symbols not found in this kernel's Module.symvers:"
        printf '%s' "${MISSING}" | sed 's/^/      /'
        warn "(built-in vmlinux symbols are not listed there, so treat this as informational)"
    else
        ok "All undefined symbols are accounted for"
    fi
fi

# ---------------------------------------------------------------- modpost log
for LOG in /var/lib/dkms/"${MODULE_NAME}"/*/*/log/make.log; do
    [ -f "${LOG}" ] || continue
    ERRORS=$(grep -cE '(ERROR|WARNING): modpost' "${LOG}" 2>/dev/null || true)
    SUPPRESSED=$(grep -c 'suppressed .* unresolved symbol' "${LOG}" 2>/dev/null || true)
    if [ "${ERRORS:-0}" -gt 0 ] || [ "${SUPPRESSED:-0}" -gt 0 ]; then
        bad "modpost reported problems in ${LOG}"
        grep -E '(ERROR|WARNING): modpost|suppressed' "${LOG}" | head -10 | sed 's/^/      /'
        FAIL=1
    else
        ok "modpost clean: $(basename "$(dirname "$(dirname "${LOG}")")")"
    fi
done

# ---------------------------------------------------------------- build config
if [ -f /usr/src/"${MODULE_NAME}-${KERNELSU_VERSION}"/dkms.conf ]; then
    # Only flag a live setting, not the explanatory comment in dkms.conf.
    if grep -vE '^[[:space:]]*#' /usr/src/"${MODULE_NAME}-${KERNELSU_VERSION}"/dkms.conf \
         | grep -q 'KBUILD_MODPOST_WARN'; then
        bad "dkms.conf still sets KBUILD_MODPOST_WARN - unresolved symbols would be hidden"
        FAIL=1
    else
        ok "dkms.conf does not suppress modpost errors"
    fi
    if grep -q '@PKGVER@\|@KSU_GIT_VERSION@' /usr/src/"${MODULE_NAME}-${KERNELSU_VERSION}"/dkms.conf; then
        bad "dkms.conf still contains unsubstituted placeholders"
        FAIL=1
    else
        ok "dkms.conf placeholders substituted"
    fi
fi

echo
if [ "${FAIL}" -eq 0 ]; then
    ok "Module passed all linkage checks"
    exit 0
else
    bad "Module has problems - do not ship it"
    exit 1
fi
