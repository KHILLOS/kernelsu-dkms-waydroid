#!/bin/bash
# check-noop-backend.sh - assert the no-op SELinux backend defines every symbol
#
# With CONFIG_KSU_SELINUX=n, kernel/selinux/selinux_none.c must define every
# symbol the rest of the module calls. A missing definition is not always a
# build error - with sufficient warning suppression it becomes an unloadable
# .ko - so this is checked explicitly.
#
# Usage: ./tools/check-noop-backend.sh [patch-file]
#
# Exits non-zero and prints ::error:: annotations (pickup by GitHub Actions)
# for anything missing.

set -uo pipefail

P="${1:-patches/0004-selinux-noop-backend.patch}"

if [ ! -f "${P}" ]; then
    echo "::error::patch not found: ${P}"
    exit 1
fi

# Every symbol selinux_none.c must provide.
REQUIRED="setup_selinux setenforce getenforce cache_sid
          is_task_ksu_domain is_ksu_domain is_zygote is_init is_adbd
          apply_kernelsu_rules handle_sepolicy setup_ksu_cred
          escape_to_root_for_adb_root
          ksu_selinux_hide_init ksu_selinux_hide_exit
          ksu_selinux_hide_drop_backup_if_unused
          ksu_selinux_hide_handle_second_stage
          ksu_selinux_hide_handle_post_fs_data"

missing=0
checked=0

for sym in ${REQUIRED}; do
    checked=$((checked + 1))
    # A definition is added by the patch as "+<return type> <name>(" at column 0.
    if ! grep -qE "^\+[A-Za-z_][A-Za-z_0-9 *]*[ *]${sym}\(" "${P}"; then
        echo "::error::${P} does not define ${sym}()"
        missing=1
    fi
done

# Exported data symbol referenced from infra/file_wrapper.c.
checked=$((checked + 1))
if ! grep -qE '^\+u32 ksu_file_sid' "${P}"; then
    echo "::error::${P} does not define ksu_file_sid"
    missing=1
fi

if [ "${missing}" -eq 0 ]; then
    echo "ok: all ${checked} symbols are defined by ${P}"
fi

exit "${missing}"
