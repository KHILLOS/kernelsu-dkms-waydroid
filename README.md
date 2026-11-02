# KernelSU DKMS for Waydroid

Build and install the latest official KernelSU (tiann/KernelSU v3.3.1) as an out-of-tree DKMS module on a regular Linux host kernel, enabling root (su) access in Waydroid containers.

## Quick Start

```bash
# 1. Run pre-flight checks
./preflight.sh

# 2. Install KernelSU DKMS module
sudo ./install.sh

# 3. Set up Waydroid integration
sudo ./waydroid-setup.sh

# 4. Test root in Waydroid
waydroid shell su -c "id"
```

## What This Project Provides

| Component | Description |
|-----------|-------------|
| `patches/0001-kconfig-add-waydroid-options.patch` | Adds `KSU_NON_ANDROID` and `KSU_SELINUX` to Kconfig |
| `patches/0002-kbuild-waydroid-flags-and-dkms-version.patch` | Passes Waydroid config flags, conditional SELinux objects, DKMS git-version fallback |
| `patches/0003-file-wrapper-selinux-guard.patch` | Guards SELinux code in `file_wrapper.c` for non-SELinux hosts |
| `patches/0004-selinux-objsec-guard.patch` | Guards `objsec.h` include in `selinux/selinux.c` |
| `dkms.conf` | DKMS configuration with version placeholders |
| `Makefile` | Simple DKMS Makefile wrapper |
| `fetch-kernelsu.sh` | Downloads v3.3.1 source, applies patches, prepares DKMS tree |
| `install.sh` | Full DKMS add/build/install + modprobe config + modloader |
| `uninstall.sh` | Clean removal from DKMS, restores Waydroid seccomp |
| `waydroid-setup.sh` | Configures Waydroid for KernelSU root access |
| `preflight.sh` | Comprehensive pre-installation checks |
| `load-kernelsu` | Module loader using modloader (bypasses secure boot) |
| `00-kernelsu.conf` | Modprobe alias (`ksu` → `kernelsu`) |

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
| 0001 | Adds `CONFIG_KSU_NON_ANDROID` (disables PID=1 check) and `CONFIG_KSU_SELINUX` (enables SELinux integration) |
| 0002 | Propagates config options to C compiler flags (`-DCONFIG_KSU_NON_ANDROID=1`) |
| 0003 | Disables git version detection (DKMS builds outside git repo) |
| 0004 | Adds fallback SELinux include paths for standard Linux kernels |

## Configuration Options

### DKMS Build Config (dkms.conf MAKE line)
```bash
CONFIG_KSU=m                           # Build as module
CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y  # x86_64 syscall hooking
CONFIG_KSU_NON_ANDROID=y               # Waydroid/non-Android support
CONFIG_KSU_SELINUX=n                   # Enable if host has SELinux (default n)
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
| Patch 0002 (Kbuild flags) | ✓ Applied | Compiler flags added |
| Patch 0003 (git version) | ✓ Applied | Disabled for DKMS |
| Patch 0004 (SELinux paths) | ✓ Applied | Fallback includes |
| DKMS add | ✓ Tested | Module added successfully |
| DKMS build | ✓ Tested | Built successfully on 7.1.5+kali-amd64 |
| DKMS install | ✓ Tested | Installed to /lib/modules/.../extra/ |
| Module load | ✓ Tested | Loads via modloader, LSM + syscall hooks work |
| Waydroid root | ⏳ Pending | Requires Waydroid installation |
| Secure Boot (modloader) | ⏳ Pending | Test system is Legacy BIOS |

## Known Limitations

1. **CONFIG_KSU_SELINUX defaults to n** - Enable in dkms.conf if your host kernel has SELinux
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