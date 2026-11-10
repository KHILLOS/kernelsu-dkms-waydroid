# Boot tests

Compiling and even modpost-verifying a kernel module proves it **links**. It does
not prove it can be **loaded**: KernelSU patches syscall tables and kernel text
at init time, so a bug there is a panic inside `insmod`, not a compile error.
This directory closes that gap.

`run.sh <image> <kernel-version>`:

1. builds the module inside the distribution container against that kernel's
   real headers,
2. boots the distribution's own `vmlinuz-<version>` in QEMU (TCG, no KVM needed),
3. runs a small initramfs that does `insmod kernelsu.ko`, checks the module is
   live, dumps its init messages, counts kernel error lines, then `rmmod`s it and
   checks again that the kernel is still healthy and the module is gone.

## Reading the output

```
ubuntu:24.04|6.8.0-149-generic|INSMOD=OK|RMMOD=OK|errors_before=0|errors_after=0|leftover=NO|listed=YES
```

* `INSMOD` / `RMMOD` — the module loaded / unloaded without an error return.
* `errors_before` — kernel `BUG:`/`Oops`/`call trace` lines after loading. Must be 0.
* `errors_after` — the same counter after unloading. Must equal `errors_before`
  or unloading damaged something.
* `leftover` — whether the module is still in `/proc/modules` after `rmmod`.
* `listed` — whether the module appeared in `/proc/modules` at all.

A clean checkout works: the script runs `fetch-kernelsu.sh` itself, so the
KernelSU sources do not need to exist beforehand.

This is the test that found the `kobject_del(&THIS_MODULE->mkobj.kobj)` panic:
the module loaded fine and panicked the kernel on `rmmod`, which is exactly what
`install.sh` does during its own load test.

## Requirements

`qemu-system-x86_64`, rootful `podman`, `busybox`, `cpio`.
