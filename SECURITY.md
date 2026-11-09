# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository ("Security" tab → "Report a vulnerability"). If that is
unavailable, contact the maintainer listed on the GitHub profile.

Include steps to reproduce, kernel version (`uname -r`), and the output of
`verify-build.sh`. Expect an initial response within a week.

Vulnerabilities in KernelSU itself should be reported upstream to
[tiann/KernelSU](https://github.com/tiann/KernelSU/security).

## Threat model — read this before deploying

This project builds a kernel module that **grants root** inside a Waydroid
container. Understand what it does to your host:

- **The module runs in host kernel context.** A bug here can crash or compromise
  the host, not just the container.
- **The module is unsigned** and is loaded with
  [modloader](https://github.com/shadichy/modloader), which bypasses the kernel's
  module signature check. This is why Secure Boot offers no protection against a
  tampered module — the module loader is the trust boundary.
- **`install.sh` edits `/var/lib/waydroid/lxc/waydroid/waydroid.seccomp`**,
  removing the `reboot` filter (a timestamped backup is written first, and
  `uninstall.sh` restores it). This is required for KernelSU, but it does widen
  what processes inside the container may call.
- **SELinux integration is disabled** for DKMS builds. KernelSU does not label
  its own processes, and `ksud`'s custom sepolicy rules are ignored. Root
  escalation therefore produces processes carrying the caller's existing
  SELinux context. On an enforcing host this may either be blocked or, if the
  caller was already unconfined, be less contained than a properly labelled
  `ksu` domain would be. Do not treat this build as providing SELinux-level
  isolation.
- **Secure Boot:** with `modloader` in use, the usual guarantee that only signed
  kernel code runs does not apply. Only load modules you built from a commit you
  trust.

## Recommended posture

- Build from a tagged commit, not from a moving branch.
- Keep the host kernel updated; the module rebuilds via DKMS on kernel updates,
  and `verify-build.sh` should be re-run after a kernel change.
- Treat the Waydroid container as untrusted input, but assume compromise of the
  host kernel is possible.
- `uninstall.sh` removes the module, `modloader`, the modprobe alias, and
  restores the seccomp profile.

## Supported versions

Only the latest commit on `master` is supported. This package tracks a single
pinned KernelSU version (`3.3.1`); older branches are not patched.
