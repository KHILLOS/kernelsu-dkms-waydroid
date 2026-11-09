# Contributing

## What this project is

A DKMS package that builds [KernelSU](https://github.com/tiann/KernelSU) as an
**out-of-tree** kernel module for Waydroid hosts. That single constraint drives
almost every design decision here:

> A DKMS module may only reference `EXPORT_SYMBOL()`'d kernel symbols.
> KernelSU upstream is written to be compiled *inside* the kernel tree, where it
> may call internal helpers freely.

Any patch that introduces a direct reference to a non-exported kernel symbol
will produce a `.ko` that cannot be loaded. See `DECISIONS.md` for the list of
symbols already handled.

## Before opening a PR

```bash
sudo ./build.sh --clean      # fetch + patch + build + verify
sudo ./verify-build.sh       # re-check the finished artifact
```

`build.sh` fails if `verify-build.sh` fails, so a green local run means the
module links.

Also run:

```bash
shellcheck -S warning *.sh load-kernelsu
for f in *.sh load-kernelsu; do bash -n "$f"; done
```

## Changing the patch series

Patches are pinned to one upstream commit (`KERNELSU_COMMIT` in
`fetch-kernelsu.sh`). If upstream moves:

1. Update `KERNELSU_VERSION` / `KERNELSU_COMMIT` / `DATE_CHECKED`.
2. Regenerate the affected patch and renumber `patches/series` if needed.
3. Run `sudo ./build.sh --clean` on a real kernel and paste the verification
   output in the PR.

Rules for patches:

- One concern per patch. `0001` is configuration only; build-system changes,
  symbol resolution, and source guards stay separate.
- Keep hunks minimal and add a comment explaining *why* when a change exists
  only because of the out-of-tree constraint.
- Never add `KBUILD_MODPOST_WARN` to `dkms.conf`. It hides exactly the failure
  this project exists to avoid.

## Testing expectations

| Changed | Verify |
|---|---|
| Kbuild / `dkms.conf` | `sudo ./build.sh --clean` on at least one kernel ≥ 5.15 |
| A `.c` patch | same, plus `sudo ./verify-build.sh` |
| Scripts | `shellcheck` + `bash -n`, and a manual run of the affected path |
| Docs only | no build needed |

If you test on a kernel other than the one in the PR description, say which
(`uname -r`) in the PR.

## Reporting a problem

Include:

- `uname -r`, distro and version
- output of `sudo ./verify-build.sh`
- the DKMS build log: `/var/lib/dkms/kernelsu/*/*/log/make.log`
- `dkms status`

If the module fails to load, `dmesg | tail -30` and `modinfo kernelsu` are
usually enough to identify the missing symbol.

## License

Contributions are accepted under GPL-3.0, matching upstream KernelSU.
