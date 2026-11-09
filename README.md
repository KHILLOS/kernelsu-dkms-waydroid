# KernelSU DKMS for Waydroid

[![build](https://github.com/KHILLOS/kernelsu-dkms-waydroid/actions/workflows/build.yml/badge.svg)](https://github.com/KHILLOS/kernelsu-dkms-waydroid/actions/workflows/build.yml)
[![license: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

Build and install the official [KernelSU](https://github.com/tiann/KernelSU)
(v3.3.1) as an **out-of-tree DKMS module** on a regular Linux host kernel,
giving root (`su`) access inside Waydroid containers.

> **Verified on six kernel generations, x86_64** — Ubuntu 22.04 (5.15),
> Debian 12 (6.1), Ubuntu 24.04 (6.8), Debian 13 (6.12), Ubuntu 25.10 (6.17) and
> Ubuntu 26.04 (7.0): `build.sh --clean` → `dkms install` → 0 modpost errors,
> 0 unresolved symbols on every one. Only x86_64 hosts are supported.

### Supported kernels

The module is built against the headers of whatever kernel DKMS targets, and it
adapts to that kernel's actual APIs rather than to a version number — distro
backports mean a 5.15 Ubuntu kernel can already carry the 6.8 LSM/hook layout
while an Ubuntu 6.17 kernel is already past the removal of the static-call
table.

| Distribution | Kernel tested | LSM hook storage | Result |
|---|---|---|---|
| Ubuntu 22.04 | `5.15.0-203-generic` | hook heads (`lsmid` backport) | builds, uses LSM hooking |
| Debian 12 | `6.1.0-54-amd64` | hook heads | builds, uses LSM hooking |
| Ubuntu 24.04 | `6.8.0-149-generic` | hook heads (`lsmid`) | builds, uses LSM hooking |
| Debian 13 | `6.12.116+deb13-amd64` | static calls | builds, uses LSM hooking |
| Ubuntu 25.10 | `6.17.0-41-generic` | hook heads, static calls removed | builds, uses LSM hooking |
| Ubuntu 26.04 | `7.0.0-43-generic` | static calls | builds, uses LSM hooking |

Kernels ≤ 5.15 whose headers are older than the LSM `lsmid` rework build with
LSM hooking compiled out (see `Kbuild`'s `KSU_LSM_LAYOUT_*` probe); kernels that
removed the hook internals from their public headers build with a no-op LSM
backend that reports `-EOPNOTSUPP` instead of guessing at opaque structures.
Everything else in the module — `su` redirection, supercalls, allowlist,
profiles, sulog — is unaffected.

## Quick Start

```bash
# 1. Pre-flight checks
./preflight.sh

# 2. Build and verify (fetch upstream, apply patches, dkms build, verify linkage)
sudo ./build.sh --clean

# 3. Install
sudo ./install.sh

# 4. Configure Waydroid
sudo ./waydroid-setup.sh

# 5. Test root in the container
waydroid shell su -c "id"
```

`build.sh` refuses to declare success unless `verify-build.sh` passes, so a green
run means the produced `.ko` is actually loadable.

## A note on what changed

Earlier revisions of this project produced a module that **built but could never
load**: `dkms.conf` passed `KBUILD_MODPOST_WARN=1`, which turns modpost's
"undefined symbol" errors into warnings, so DKMS reported success while the `.ko`
kept 10 reported and 30+ suppressed unresolved symbols.

The cause is structural, not a typo: KernelSU is written to be compiled *inside*
the kernel tree, where it may call internal helpers freely, while a DKMS module
may only reference `EXPORT_SYMBOL()`'d symbols. See
[`DECISIONS.md`](DECISIONS.md#bug-fix-round-out-of-tree-linkage-verified-on-kernel-612)
for the full symptom → cause → fix table, and [`CHANGELOG.md`](CHANGELOG.md).

Run `sudo ./verify-build.sh` at any time to check the installed module.

## What This Project Provides

| Component | Description |
|-----------|-------------|
| `patches/0001-kconfig-add-waydroid-options.patch` | Adds `KSU_NON_ANDROID` and `KSU_SELINUX` to Kconfig |
| `patches/0002-kbuild-dkms-version-and-selinux-objects.patch` | Selects SELinux objects vs. the no-op backend, passes Waydroid config flags, DKMS git-version fallback, arch-safe `KSU_NEW_DCACHE_FLUSH` |
| `patches/0003-symbol-resolver-kprobe-and-compat-header.patch` | Replaces the non-exported `kallsyms_*` API with a `register_kprobe()` based resolver; adds `include/ksu_compat.h` |
| `patches/0004-selinux-noop-backend.patch` | Adds `selinux/selinux_none.c`, a no-op implementation used when `CONFIG_KSU_SELINUX=n` |
| `patches/0005-file-wrapper-selinux-guard.patch` | Guards SELinux-specific inode relabelling in `file_wrapper.c` |
| `patches/0006-resolve-non-exported-kernel-symbols.patch` | Resolves `path_mount`, `tasklist_lock`, `__tracepoint_sys_enter`, `init_mm`, `strncpy_from_user_nofault`, etc. at runtime |
| `dkms.conf` | DKMS configuration with version placeholders |
| `Makefile` | Simple DKMS Makefile wrapper |
| `fetch-kernelsu.sh` | Downloads v3.3.1 source, applies patches, prepares DKMS tree |
| `install.sh` | Full DKMS add/build/install + modprobe config + modloader |
| `uninstall.sh` | Clean removal from DKMS, restores Waydroid seccomp |
| `waydroid-setup.sh` | Configures Waydroid for KernelSU root access |
| `build.sh` | One-shot pipeline: fetch → patch → `dkms build` → verify |
| `verify-build.sh` | Verifies the finished `.ko`: vermagic, unresolved internal symbols, modpost log, `dkms.conf` safety |
| `preflight.sh` | Comprehensive pre-installation checks |
| `load-kernelsu` | Module loader using modloader (bypasses secure boot) |
| `00-kernelsu.conf` | Modprobe alias (`ksu` → `kernelsu`) |
| `.github/workflows/build.yml` | CI: patch application, shellcheck, real DKMS compile, regression gate |

## Requirements

### Host System
- Linux kernel **5.10+** (tested on 6.x, 7.x)
- Kernel headers for running kernel (`linux-headers-$(uname -r)`)
- DKMS (`apt install dkms`)
- Git, make, gcc
- **Architecture**: x86_64 (primary), arm64 (untested)

### Kernel Configuration (Required)
```
CONFIG_KPROBES=y
CONFIG_EXT4_FS=y
CONFIG_KALLSYMS=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
```

### Kernel Configuration (Recommended)
```
CONFIG_SECURITY_SELINUX=y      # For CONFIG_KSU_SELINUX
CONFIG_SECURITY=y
CONFIG_LSM="landlock,lockdown,yama,apparmor,bpf,selinux"
CONFIG_HAVE_KPROBES=y
CONFIG_KPROBE_EVENTS=y
```

### Waydroid
- Waydroid installed and initialized (`waydroid init`)
- binder_linux module (`modprobe binder_linux devices=binder,hwbinder,vndbinder`)

### Secure Boot
If Secure Boot is enabled, you have three options:
1. **Disable Secure Boot** in BIOS (easiest)
2. **Sign the module** with a Machine Owner Key (MOK)
3. **Use modloader** (included) which loads the module without kernel signature verification

## Installation Steps

### 1. Pre-flight Checks
```bash
./preflight.sh
```
Fix any FAILED items before proceeding. Warnings are OK but review them.

### 2. Install KernelSU
```bash
sudo ./install.sh
```
This will:
- Fetch KernelSU v3.3.1 source from GitHub
- Apply all 4 patches
- Add to DKMS
- Build and install the module
- Install modprobe config, load script, and modloader
- Patch Waydroid seccomp (allow reboot syscall)
- Test load the module

### 3. Verify Installation
```bash
# Check DKMS status
dkms status | grep kernelsu

# Check module info
modinfo kernelsu

# Load module manually
sudo load-kernelsu

# Verify loaded
lsmod | grep kernelsu
dmesg -T | grep -i kernelsu
```

### 4. Set Up Waydroid
```bash
sudo ./waydroid-setup.sh
```
This will:
- Ensure KernelSU module is loaded
- Start Waydroid session if not running
- Install KernelSU Manager APK (if present)
- Test root access in container

### 5. Test Root in Waydroid
```bash
# Basic test
waydroid shell su -c "id"

# Should output: uid=0(root) gid=0(root) groups=0(root)

# Test with an app
# Open KernelSU Manager in Waydroid, grant root to desired apps
```

## How It Works

### Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                        Host Kernel                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              kernelsu.ko (LKM via DKMS)             │   │
│  │  • LSM hooks for credential/cred changes            │   │
│  │  • Syscall hooks (x86_64 patched dispatcher)        │   │
│  │  • Netlink communication with userspace             │   │
│  │  • PID=1 checker DISABLED (CONFIG_KSU_NON_ANDROID)  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                    Netlink / Syscall hooks
                              │
┌─────────────────────────────────────────────────────────────┐
│                     Waydroid Container                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Android init (NOT PID 1 on host)                   │   │
│  │  • su binary → KernelSU via syscall                 │   │
│  │  • KernelSU Manager APK → netlink                   │   │
│  │  • SELinux context handling (CONFIG_KSU_SELINUX)    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Key Patches Explained

| Patch | Purpose |
|-------|---------|
| 0001 | Adds `CONFIG_KSU_NON_ANDROID` (disables PID=1 check) and `CONFIG_KSU_SELINUX` |
| 0002 | Build system: SELinux vs. no-op objects, config flags, DKMS version, arch-safe flags |
| 0003 | `register_kprobe()`-based symbol resolver + out-of-tree compat header |
| 0004 | No-op SELinux backend so the module links with `CONFIG_KSU_SELINUX=n` |
| 0005 | Guard SELinux-only inode relabelling in the file wrapper |
| 0006 | Runtime resolution of non-exported kernel symbols used across the module |

## Configuration Options

### DKMS Build Config (dkms.conf MAKE line)
```bash
CONFIG_KSU=m                           # Build as module
CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y  # x86_64 syscall hooking
CONFIG_KSU_NON_ANDROID=y               # Waydroid/non-Android support
CONFIG_KSU_SELINUX=n                   # Must stay n for DKMS builds (see note below)
CONFIG_KSU_DEBUG=n                     # Debug builds
CONFIG_KSU_DISABLE_MANAGER=y           # Disable manager APK detection
```

### Changing Configs
Edit `dkms.conf` MAKE line, then:
```bash
sudo dkms remove -m kernelsu -v 3.3.1 --all
sudo dkms install -m kernelsu -v 3.3.1 --force
```

## Troubleshooting

### Module Fails to Build
```bash
# Check build log
dkms build -m kernelsu -v 3.3.1 --force 2>&1 | tee build.log

# Common issues:
# 1. Missing kernel headers → apt install linux-headers-$(uname -r)
# 2. CONFIG_KPROBES not enabled → enable in kernel config
# 3. SELinux headers missing → install kernel headers with SELinux
```

### Module Loads but No Root in Waydroid
```bash
# 1. Check module is loaded
lsmod | grep kernelsu

# 2. Check dmesg for errors
dmesg -T | grep -i kernelsu

# 3. Verify Waydroid seccomp allows reboot
grep reboot /var/lib/waydroid/lxc/waydroid/waydroid.seccomp
# Should be EMPTY (reboot allowed)

# 4. Check binder
lsmod | grep binder
ls -l /dev/binder /dev/hwbinder /dev/vndbinder

# 5. Test direct syscall
waydroid shell su -c "id"
```

### Secure Boot Issues
```
Error: "Required key not available" or "Module verification failed"
```
**Solutions:**
1. Disable Secure Boot in BIOS
2. Use modloader (already installed by install.sh):
   ```bash
   sudo load-kernelsu  # Uses modloader internally
   ```
3. Sign module manually:
   ```bash
   # Generate MOK key
   openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER -out MOK.der -nodes -days 36500 -subj "/CN=KernelSU DKMS/"
   
   # Import to MOK
   sudo mokutil --import MOK.der
   
   # Sign module
   sudo /usr/src/linux-headers-$(uname -r)/scripts/sign-file sha256 MOK.priv MOK.der /lib/modules/$(uname -r)/extra/kernelsu.ko
   ```

### DKMS Rebuild on Kernel Update
DKMS should auto-rebuild. If not:
```bash
sudo dkms install -m kernelsu -v 3.3.1 --force
```

### Waydroid SELinux Denials
```bash
# Check denials
waydroid shell dmesg | grep -i denied

# Or on host
dmesg -T | grep -i selinux | grep kernelsu

# If using CONFIG_KSU_SELINUX=y, ensure host has SELinux enabled
```

## Uninstall

```bash
sudo ./uninstall.sh
```
Removes DKMS module, configs, scripts, and restores Waydroid seccomp backup.

## Version Info

- **KernelSU Version**: v3.3.1 (official tiann/KernelSU)
- **Release Date**: 2026-10-12
- **Commit**: 0c0fdb960178fa12d80d6cbcfdcb6ad8be6a865d
- **Date Verified**: 2026-11-02
- **Base Kernel**: Linux 7.1.5+kali-amd64 (tested)

## Testing Status

| Component | Status | Notes |
|-----------|--------|-------|
| Patch 0001 (Kconfig) | ✓ Applied | Adds NON_ANDROID, SELINUX |
| Patch 0002 (Kbuild) | ✓ Applied | Object selection, config flags, DKMS version |
| Patch 0003 (symbol resolver) | ✓ Applied | kprobe-based lookup, compat header |
| Patch 0004 (SELinux no-op) | ✓ Applied | Links with `CONFIG_KSU_SELINUX=n` |
| Patch 0005 (file wrapper) | ✓ Applied | SELinux inode relabel guarded |
| Patch 0006 (runtime symbols) | ✓ Applied | No unresolved symbols at load time |
| DKMS add | ✓ Tested | Module added successfully |
| DKMS build | ✓ Tested | Built successfully on 7.1.5+kali-amd64 |
| DKMS install | ✓ Tested | Installed to /lib/modules/.../extra/ |
| Module load | ✓ Tested | Loads via modloader, LSM + syscall hooks work |
| Waydroid root | ⏳ Pending | Requires Waydroid installation |
| Secure Boot (modloader) | ⏳ Pending | Test system is Legacy BIOS |

## Known Limitations

1. **CONFIG_KSU_SELINUX must stay n for DKMS builds** - The SELinux backend needs
   `security/selinux/objsec.h` and `ss/policydb.h`, which no distro kernel-headers
   package ships and whose structs are not ABI-stable. A no-op backend
   (`kernel/selinux/selinux_none.c`) is compiled instead: root escalation still works,
   but process SELinux labels and custom sepolicy rules are not applied.
2. **x86_64 only tested** - arm64 support exists in upstream but untested here
3. **Manager APK not included** - Download from GitHub releases separately
4. **No initramfs integration** - Module loads manually via `load-kernelsu` or systemd service
5. **Waydroid seccomp patch is manual** - Run install.sh after Waydroid updates

## Creating a Systemd Service (Optional)

For auto-load on boot:
```ini
# /etc/systemd/system/kernelsu-load.service
[Unit]
Description=Load KernelSU Module
After=systemd-modules-load.service
Before=waydroid-container.service

[Service]
Type=oneshot
ExecStart=/usr/bin/load-kernelsu
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now kernelsu-load
```

## Credits

- **Official KernelSU**: https://github.com/tiann/KernelSU
- **supechicken's Waydroid fork**: https://github.com/supechicken/KernelSU (waydroid branch)
- **AUR kernelsu-dkms**: https://aur.archlinux.org/packages/kernelsu-dkms
- **modloader**: https://github.com/shadichy/modloader

## License

GPL-2.0-only (same as KernelSU)