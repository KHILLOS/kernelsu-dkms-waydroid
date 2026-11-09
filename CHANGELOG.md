# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Upstream base: [tiann/KernelSU](https://github.com/tiann/KernelSU) `v3.3.1`
(commit `0c0fdb9`).

## [Unreleased]

### Fixed

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
