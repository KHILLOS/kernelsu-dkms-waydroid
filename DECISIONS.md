# DECISIONS.md - KernelSU DKMS for Waydroid

## Project Overview
Build KernelSU v3.3.1 as DKMS module for Waydroid root access on regular Linux hosts.

---

## Key Decisions

### 1. Base Version: Official tiann/KernelSU v3.3.1
**Decision**: Use official upstream v3.3.1 (tag v3.3.1, commit 0c0fdb9, 2026-10-12) instead of supechicken's fork.

**Reasoning**:
- Official upstream is actively maintained
- v3.3.1 has modern architecture (modular Kbuild, LSM hooks, per-arch syscall hooking)
- supechicken's fork is based on ancient pre-1.0 codebase
- We port only the necessary Waydroid configs as patches

### 2. Patch Strategy: Minimal Focused Patches
**Decision**: Create 4 minimal patches (see `patches/series`) rather than one large patch or forking.

| Patch | Scope | Why Separate |
|-------|-------|--------------|
| 0001 | Kconfig additions | Config options only, reviewable independently |
| 0002 | Kbuild compiler flags | Build system flags only |
| 0003 | Git version disable | DKMS-specific, may not be needed if upstream fixes |
| 0004 | SELinux include paths | Build fix, separate concern |

**Benefits**:
- Each patch is independently reviewable
- Easier to upstream individual changes
- Clear separation of concerns
- Easier to maintain when upstream updates

### 3. CONFIG_KSU_NON_ANDROID Default: n (opt-in)
**Decision**: Default `CONFIG_KSU_NON_ANDROID=n` in Kconfig, enable via dkms.conf MAKE line.

**Reasoning**:
- This is a behavior-changing option (disables PID=1 check)
- Should be explicit opt-in for non-Android use
- Default n maintains Android compatibility
- Enabled in our dkms.conf for Waydroid use case

### 4. CONFIG_KSU_SELINUX Default: n (opt-in)
**Decision**: Default `CONFIG_KSU_SELINUX=n` in Kconfig (changed from supechicken's default y).

**Reasoning**:
- Not all host kernels have SELinux enabled
- Building with SELinux when host lacks it causes build errors
- User should explicitly enable if their distro uses SELinux (Fedora, RHEL, etc.)
- Debian/Ubuntu/Kali typically use AppArmor, not SELinux

### 5. CONFIG_KSU_DISABLE_MANAGER: y (enabled)
**Decision**: Enable `CONFIG_KSU_DISABLE_MANAGER=y` in dkms.conf.

**Reasoning**:
- Waydroid doesn't use KernelSU Manager APK in the traditional way
- Manager APK detection adds code size and complexity
- Root is granted via kernel module directly
- Reduces attack surface and build dependencies

### 6. Module Loading: modloader (not insmod)
**Decision**: Use `modloader` userspace tool instead of `insmod`.

**Reasoning**:
- modloader loads modules without kernel signature verification
- Works with Secure Boot enabled (no MOK enrollment needed)
- Simpler for users - no signing workflow required
- shadichy's modloader is well-tested with KernelSU

### 7. DKMS Version Placeholders
**Decision**: Use `@PKGVER@` and `@KSU_GIT_VERSION@` placeholders substituted by fetch script.

**Reasoning**:
- Single source of truth (fetch script)
- Git version (commit count) embedded for version tracking
- Avoids hardcoding versions in multiple files
- Matches AUR package approach

### 8. Waydroid Seccomp Patch: Allow reboot syscall
**Decision**: Remove `reboot` from Waydroid's seccomp profile.

**Reasoning**:
- KernelSU uses reboot syscall for certain operations
- Waydroid's default seccomp blocks it
- Minimal security impact (reboot in container doesn't reboot host)
- Standard practice in KernelSU Waydroid setups

### 9. No initramfs Integration
**Decision**: Don't add module to initramfs; use manual/systemd loading.

**Reasoning**:
- Simpler - no initramfs regeneration needed
- Module only needed when Waydroid runs
- Can use systemd service for auto-load
- Avoids boot issues if module has bugs

### 10. No Kernel Config Modification
**Decision**: Don't modify host kernel config; check and warn only.

**Reasoning**:
- Modifying kernel config requires rebuild/reboot
- Most modern distros have required configs enabled
- Preflight script checks and reports missing configs
- User can rebuild kernel if absolutely necessary

### 11. Secure Boot: Document Options, Use modloader
**Decision**: Don't implement automatic MOK signing; document three options.

**Reasoning**:
- MOK signing is distro-specific and complex
- modloader works universally
- Users who want signed modules can follow documented process
- Keeps install.sh simple and robust

### 12. KernelSU Manager APK: Not Bundled
**Decision**: Don't bundle Manager APK; document download URL.

**Reasoning**:
- APK updates independently of kernel module
- Legal/licensing clarity (APK is separate release)
- Users can choose version (stable/beta/debug)
- Reduces repo size and maintenance

### 13. Architecture: x86_64 Primary
**Decision**: Test and optimize for x86_64; arm64 untested but patches are arch-agnostic.

**Reasoning**:
- Most Waydroid hosts are x86_64
- Upstream has arm64 support but different hook implementation
- CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER only for x86_64
- Can add arm64 testing later if needed

### 14. Fetch Script: Shallow Clone + Verification
**Decision**: Use shallow clone with commit verification.

**Reasoning**:
- Faster download (no full history)
- Verifies expected commit matches tag
- Records git version (commit count) for DKMS
- Applies patches after clone, before DKMS copy

### 15. Backup Before Modifying System Files
**Decision**: Backup Waydroid seccomp before patching.

**Reasoning**:
- uninstall.sh restores from backup
- Timestamped backups allow multiple install/uninstall cycles
- Safe rollback if something breaks
- Follows "backup before edit" principle


---

## Bug-fix round: out-of-tree linkage (verified on kernel 6.12)

The original series produced a module that **built** but could never **load**.
Root cause: a DKMS module may only reference `EXPORT_SYMBOL()`'d symbols, while
KernelSU is written to be compiled *inside* the kernel tree and uses internal
helpers freely. `KBUILD_MODPOST_WARN=1` in `dkms.conf` turned the resulting
"undefined symbol" errors into warnings, so DKMS reported success.

Measured against `linux-headers-6.12.115` (Debian 13):

| Symptom | Cause | Fix |
|---------|-------|-----|
| `fatal error: objsec.h: No such file or directory` when `CONFIG_KSU_SELINUX=y` | `objsec.h` / `ss/policydb.h` are kernel-private and not shipped by any distro | `selinux_none.c` no-op backend; build now aborts with an actionable message if `CONFIG_KSU_SELINUX=y` |
| `undefined! kallsyms_lookup_name`, `kallsyms_on_each_symbol`, `kallsyms_on_each_match_symbol`, `kallsyms_lookup_size_offset` | Not `EXPORT_SYMBOL`'d (none of `kallsyms.c` is) | Resolver rewritten on top of `register_kprobe()`, which *is* exported and resolves by name |
| `undefined! path_mount, path_umount, set_fs_pwd, ksys_unshare, ns_get_path, tasklist_lock, change_pid, find_task_by_vpid, alloc_uid, set_cred_ucounts, seccomp_filter_release, init_mm, mntns_operations, ext4_unregister_sysfs, __x64_sys_close, __x64_sys_setns, __tracepoint_sys_enter, strncpy_from_user_nofault, copy_to_kernel_nofault` | Internal helpers | Runtime resolution via the resolver; `close_fd()` / `strncpy_from_user()` / `copy_from_kernel_nofault()` where an exported equivalent exists |
| `CONFIG_KSU_SELINUX=n` left `handle_sepolicy`, `getenforce`, `is_zygote`, `ksu_selinux_hide_*` etc. undefined | Kbuild skipped the objects but callers remained | `selinux_none.c` supplies every symbol |
| `KSU_VERSION` became invalid | Git detection always fails in `/usr/src`, leaving `KSU_GIT_VERSION` empty | Out-of-tree builds require `KSU_GIT_VERSION` from `dkms.conf`; fallback fixed to `30000` |
| `KSU_NEW_DCACHE_FLUSH` got a garbage value on non-arm64 | Probed an arm64-only header | Arch-guarded, defaults to `0` |
| `ns_get_path()` result stored in a `long` | It returns `struct path *`, not `int` | Pointer + `IS_ERR_OR_NULL()` |
| `load-kernelsu` could not load the `.ko.xz` DKMS installs | Decompression chosen from a glob that did not match | Suffix-based decompressor + dependency check |

Verification performed:
- `fetch-kernelsu.sh` → `dkms add` → `dkms build` → **0 modpost errors/warnings**, `kernelsu.ko` produced
- `nm -u kernelsu.ko` contains **no** `ksu_*`/`selinux*`/`kallsyms*`/`tasklist_lock` references
- `CONFIG_KSU_SELINUX=y` on distro headers now fails immediately with an explanatory message instead of a header-not-found error

Trade-off introduced by patch 0004: with the no-op SELinux backend, KernelSU no
longer moves its own processes into the `ksu` domain, `ksud`'s custom sepolicy
rules are ignored (`handle_sepolicy()` returns `-EOPNOTSUPP`), and SELinux hiding
is unavailable. Root escalation (uid/gid/capabilities) is unaffected. This is the
only option for a DKMS module on a stock distro kernel.

---

## Rejected Alternatives

### ❌ Fork KernelSU Repository
**Rejected**: Too much maintenance burden; upstream moves fast.

### ❌ Single Large Patch
**Rejected**: Hard to review, hard to upstream, hard to maintain.

### ❌ Enable All Configs by Default
**Rejected**: Breaks Android builds, increases attack surface, build failures on non-SELinux kernels.

### ❌ Automatically Sign Modules for Secure Boot
**Rejected**: Complex, requires user interaction (MOK enrollment), distro-specific.

### ❌ Bundle KernelSU Manager APK
**Rejected**: Separate release cycle, licensing, increases repo size.

### ❌ Modify GRUB/Initramfs
**Rejected**: High risk, unnecessary for Waydroid use case.

### ❌ Use supechicken's Fork Directly
**Rejected**: Ancient codebase (pre-1.0), missing 3+ years of features/fixes.

---

## Future Considerations

1. **Upstream Patches**: Submit 0001 and 0002 to tiann/KernelSU for official Waydroid support
2. **arm64 Testing**: Add CI for arm64 hosts (Apple Silicon, ARM servers)
3. **DKMS Auto-rebuild**: Verify DKMS triggers on kernel update
4. **Systemd Service**: Provide optional systemd service file
5. **KernelSU Next**: Monitor upstream for "KernelSU Next" architecture changes
6. **Android Version Compatibility**: Test with Waydroid's Android 13/14/15 images