#!/bin/bash
# tools/boottest/run.sh <image> <kernel-version>
#
# Boots <kernel-version> from <image> in QEMU and loads the module on the real
# running kernel.  A compile test cannot see a panic inside insmod(); this does.
#
# Output, one line per kernel, pipe-separated:
#   image|kernel|INSMOD=OK|RMMOD=OK|errors_before=0|errors_after=0|leftover=NO
#
# Requirements: qemu-system-x86_64, podman (rootful), busybox, cpio.
set -u
IMG=$1; KV=$2
PODMAN=${PODMAN:-sudo podman}
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MARKER=$(echo "$KV" | tr -c 'a-zA-Z0-9' '_')
WORK=${WORKDIR:-/tmp/boottest}/$KV
rm -rf "$WORK"; mkdir -p "$WORK"

# 1. Build the module against this kernel's real headers.
$PODMAN run --rm --network=host -v "$SRC:/src:ro" -v "$WORK:/out:z" "$IMG" bash -c "
  # EOL releases only serve their old packages from the archive hosts; without
  # this the headers 404 and the build fails with a misleading error.
  if grep -qsE 'bullseye|buster' /etc/os-release && [ -f /etc/apt/sources.list ]; then
    sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org/debian-security|g' /etc/apt/sources.list
    echo 'Acquire::Check-Valid-Until \"false\";' > /etc/apt/apt.conf.d/99no-check
  fi
  apt-get update -qq >/dev/null 2>&1
  # Debian packages the headers as *-amd64, Ubuntu as *-generic.  Try both, but
  # let the second apt run finish the job: a failing first attempt can leave apt's
  # lock/list state such that only a complete retry installs everything.
  apt-get install -y --no-install-recommends build-essential libelf-dev bc flex bison \
      kmod xz-utils zstd git ca-certificates linux-headers-generic linux-image-generic >/dev/null 2>&1 || \
  apt-get install -y --no-install-recommends build-essential libelf-dev bc flex bison \
      kmod xz-utils zstd git ca-certificates linux-headers-amd64 linux-image-amd64 >/dev/null 2>&1
  # Hard requirement: without these the build fails far from the real cause.
  for tool in make gcc git; do command -v \$tool >/dev/null || exit 15; done
  cp -r /src /work && cd /work || exit 11
  # The repository does not ship the KernelSU sources: fetch the pinned commit and
  # apply patches/series, exactly like build.sh does.
  # fetch-kernelsu.sh installs the patched tree into /usr/src/kernelsu-<ver>,
  # flattened: that directory is itself the kernel module directory.
  ./fetch-kernelsu.sh >/out/fetch.log 2>&1 || exit 14
  cd /usr/src/kernelsu-* || exit 11
  test -f Kbuild || exit 16
  make -C /usr/src/linux-headers-$KV M=\$PWD CONFIG_KSU=m KSU_GIT_VERSION=2680 \
        CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y CONFIG_KSU_NON_ANDROID=y \
        CONFIG_KSU_SELINUX=n CONFIG_KSU_DISABLE_MANAGER=y modules >/out/build.log 2>&1 || exit 12
  cp kernelsu.ko /out/kernelsu.ko
  cp /boot/vmlinuz-$KV /out/vmlinuz || exit 13
" >/dev/null 2>&1
RC=$?
chmod -R a+rX "$WORK" 2>/dev/null || sudo chmod -R a+rX "$WORK"
if [ $RC -ne 0 ]; then
  echo "$IMG|$KV|BUILD_FAIL($RC)|$(grep -E 'error:|ERROR: modpost' "$WORK/build.log" 2>/dev/null | head -2 | tr '\n' ' ')"
  exit 0
fi

# 2. Package it with a tiny init that loads and unloads the module.
IROOT=$WORK/initramfs
mkdir -p "$IROOT"/bin "$IROOT"/proc "$IROOT"/sys "$IROOT"/dev
cp /usr/bin/busybox "$IROOT/bin/busybox"
sed "s|@@TAG@@|$MARKER|g" "$(dirname "${BASH_SOURCE[0]}")/init.template" > "$IROOT/init"
chmod +x "$IROOT/init"
cp "$WORK/kernelsu.ko" "$IROOT/kernelsu.ko"
( cd "$IROOT" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$WORK/initramfs.cpio.gz" )

# 3. Boot it.  300s covers slow TCG emulation on CI runners without KVM.
# -cpu max: the host's busybox may be built for x86-64-v2/v3, while QEMU's
# default qemu64 model lacks those instructions and init dies with an invalid
# opcode before the module is ever touched.
timeout 300 qemu-system-x86_64 -cpu max -m 1024 -kernel "$WORK/vmlinuz" \
  -initrd "$WORK/initramfs.cpio.gz" \
  -append "console=ttyS0 panic=-1 rdinit=/init" -nographic -no-reboot \
  > "$WORK/boot.log" 2>&1

R=$(grep -a "^${MARKER} " "$WORK/boot.log" | sed "s/^[^ ]* //; s/\r$//")
g() { echo "$R" | grep -oP "$1=\K\w+"; }
echo "$IMG|$KV|INSMOD=$(g INSMOD || echo none)|RMMOD=$(g RMMOD || echo none)|\
errors_before=$(g ERROR_LINES || echo '?')|errors_after=$(g ERROR_LINES_AFTER_UNLOAD || echo '?')|\
leftover=$(g UNLOAD_LEFTOVER || echo '?')|listed=$(g MODULE_LISTED || echo '?')"
