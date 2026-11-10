# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Upstream base: [tiann/KernelSU](https://github.com/tiann/KernelSU) `v3.3.1`
(commit `0c0fdb9`).

## [Unreleased]

### Fixed

- **CRITICAL: the module panicked the host on unload.** `kernelsu_init()` called
  `kobject_del(&THIS_MODULE->mkobj.kobj)` to hide the module from `/sys/module`
  on Android, where it is never removed. On a desktop host `mod_sysfs_teardown()`
  walks that same node during `rmmod`, so the kernel died with
  `kernelsu_init() -> kobject_del -> kernfs: can not remove 'uevent', no directory`
  followed by a NULL dereference in `kernfs_find_and_get_ns()`. `install.sh`
  performs exactly that load/unload cycle as its own install test, so installing
  could crash the machine. Now compiled out for non-Android builds.
- **Older-kernel compatibility (5.4 – 6.8)**: `__nocfi`, `linux/pgtable.h`, the `*_nofault` copy helpers,
  `linux/minmax.h`, `TWA_RESUME`/`task_work_add()`, `struct seccomp.filter_count`
  and the `struct action_cache` API all post-date 5.4 and are now guarded. These
  kernels are no longer in CI, so this range is best-effort.
- **`close_fd()` vs `__close_fd()`** is probed from `Module.symvers`. Debian's
  5.10 backported the rename, so a version check picked the wrong symbol and
  modpost failed with `"__close_fd" undefined`.
- **Boot tests**: the module now loads *and unloads* cleanly on a real running
  kernel for every claimed version, verified in QEMU by CI.
- **modloader download is pinned by SHA-256.** It is a third-party binary that
  runs as root and loads into the kernel; it was previously fetched over the
  network with no integrity check at all.
- **Six-kernel support.** The module now builds and passes linkage
  verification against Ubuntu 22.04 (5.15), Debian 12 (6.1), Ubuntu 24.04
  (6.8), Debian 13 (6.12), Ubuntu 25.10 (6.17) and Ubuntu 26.04 (7.0).  A
  container matrix in CI (`.github/workflows/build.yml`) keeps it that way.
- **`anon_inode_getfile_secure` is not exported on 6.1-6.7**, so referencing it
  left an unresolved symbol at modpost time.  Those kernels now use the
  portable local implementation; only 6.8+ uses `anon_inode_create_getfile`.
- **`security_inode_init_security_anon` is unavailable before 6.2.** The
  wrapper inode is created without a security context there instead of failing
  to compile.
- **`free_pids()` (6.15+) and `free_uid()` (exported only from 6.12)** are no
  longer linked against directly; both are resolved at runtime next to
  `change_pid()`, so 7.0 links and pre-6.12 kernels link.
- **LSM hook storage is feature-detected, not version-guessed.** Distributions
  backport the 6.12 static-call rework and its later removal independently, so
  `LINUX_VERSION_CODE` was the wrong discriminator: Ubuntu 5.15 already uses the
  6.8 hook-list layout, and Ubuntu 6.17 is already past the static-call table.
  `Kbuild` now probes the installed `linux/lsm_hooks.h` and selects the hook
  heads, static calls, or the no-op backend accordingly.
- **README badge** pointed at the pre-migration repository path.
- **The module built but could never load.** `dkms.conf` passed
  `KBUILD_MODPOST_WARN=1`, which downgrades modpost's "undefined symbol"
  errors to warnings. DKMS reported success while the `.ko` retained 10
  reported and 30+ suppressed unresolved symbols.
- `CONFIG_KSU_SELINUX=y` failed with `fatal error: objsec.h: No such file` —
  the SELinux headers are kernel-private and no distro ships them. The build
  now stops with an actionable message instead.
- `CONFIG_KSU_SELINUX=n` left `handle_sepolicy`, `getenforce`, `is_zygote`,
  `ksu_selinux_hide_*` and others undefined, because Kbuild skipped the objects
  while callers remained.
- Replaced the non-exported `kallsyms_lookup_name()`, `kallsyms_on_each_symbol()`,
  `kallsyms_on_each_match_symbol()` and `kallsyms_lookup_size_offset()` with a
  `register_kprobe()`-based resolver (`register_kprobe()` is exported and
  resolves by symbol name).
- Resolved the remaining non-exported helpers at runtime: `path_mount`,
  `path_umount`, `set_fs_pwd`, `ksys_unshare`, `ns_get_path`, `tasklist_lock`,
  `change_pid`, `find_task_by_vpid`, `alloc_uid`, `set_cred_ucounts`,
  `seccomp_filter_release`, `init_mm`, `mntns_operations`,
  `ext4_unregister_sysfs`, `__x64_sys_setns`, `__tracepoint_sys_enter`.
- Mapped non-exported helpers with exported equivalents onto those equivalents:
  `close_fd()` for `__x64_sys_close`, `strncpy_from_user()` for
  `strncpy_from_user_nofault()`, `copy_from_kernel_nofault()` for
  `copy_to_kernel_nofault()`.
- `KSU_VERSION` was invalid for DKMS builds because git detection always fails
  under `/usr/src`; `KSU_GIT_VERSION` is now required from `dkms.conf` and the
  bogus `KSU_VERSION=16` fallback became `30000`.
- `KSU_NEW_DCACHE_FLUSH` received a garbage value on non-arm64 architectures
  because it probed an arm64-only header.
- `ns_get_path()` returns `struct path *`, not `long`; the truncated result made
  the error check meaningless.
- `load-kernelsu` could not load the `.ko.xz` that DKMS actually installs, and
  did not verify that a decompressor exists.
- `install.sh` invoked `./fetch-kernelsu.sh` relative to the caller's working
  directory, used no-op `: VAR=1` assignments, and installed a failed
  `modloader` download without checking it.

### Added

- `verify-build.sh` — verifies the finished `.ko`: vermagic, unresolved internal
  symbols, modpost log cleanliness, and that `dkms.conf` does not suppress
  errors. Exits non-zero when the module is not loadable.
- `build.sh` — one-shot fetch → patch → dkms build → verify pipeline.
- `.github/workflows/build.yml` — patch-application check, shellcheck, a real
  DKMS compile with artifact upload, and a regression gate for the class of bug
  fixed above.
- `LICENSE` (GPL-3.0, matching upstream KernelSU), `CHANGELOG.md`,
  `CONTRIBUTING.md`, `SECURITY.md`, `.editorconfig`, `.gitattributes`.

### Changed

- `preflight.sh` reports SELinux state accurately: it is always disabled for
  DKMS builds rather than being treated as a failure path.
- `fetch-kernelsu.sh` hard-fails on a pinned-commit mismatch, verifies every
  patch applies before applying it, rejects `.rej` files, and always starts from
  a clean output directory.
- `README.md` and `DECISIONS.md` document the root cause, the measured symptoms,
  the verification performed, and the SELinux trade-off.

### Removed

- The duplicated `kernelsu-dkms/` subtree, which was a stale byte-identical copy
  of the entire project (including its own older patch series).

## [3.3.1] - 2026-10-12

### Added

- Initial DKMS packaging of KernelSU v3.3.1 for Waydroid on x86_64 hosts.
