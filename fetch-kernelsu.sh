#!/bin/bash
# fetch-kernelsu.sh - Download and prepare KernelSU v3.3.1 source for DKMS
# Usage: ./fetch-kernelsu.sh [output_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KERNELSU_VERSION="v3.3.1"
KERNELSU_REPO="https://github.com/tiann/KernelSU.git"
KERNELSU_COMMIT="0c0fdb960178fa12d80d6cbcfdcb6ad8be6a865d"
DATE_CHECKED="2026-11-02"

OUTPUT_DIR="${1:-/usr/src/kernelsu-${KERNELSU_VERSION#v}}"

echo "=== KernelSU DKMS Source Fetcher ==="
echo "Version: ${KERNELSU_VERSION}"
echo "Commit:  ${KERNELSU_COMMIT}"
echo "Date checked: ${DATE_CHECKED}"
echo "Output: ${OUTPUT_DIR}"
echo

# Create temporary directory
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"

echo "[+] Cloning KernelSU ${KERNELSU_VERSION} (shallow)..."
git clone --filter=blob:none --branch "${KERNELSU_VERSION}" "${KERNELSU_REPO}" kernelsu

echo "[+] Verifying commit..."
cd kernelsu
ACTUAL_COMMIT=$(git rev-parse HEAD)
if [ "$ACTUAL_COMMIT" != "$KERNELSU_COMMIT" ]; then
    echo "[!] ERROR: Commit mismatch!" >&2
    echo "    Expected: $KERNELSU_COMMIT" >&2
    echo "    Actual:   $ACTUAL_COMMIT" >&2
    echo "    The patch series is pinned to a specific commit; re-pin" >&2
    echo "    KERNELSU_COMMIT in this script or refresh the patches." >&2
    exit 1
fi

# Count commits for version
GIT_VERSION=$(git rev-list --count HEAD)
echo "[+] Git version (commit count): ${GIT_VERSION}"

echo "[+] Applying patches..."
if [ -f "${SCRIPT_DIR}/patches/series" ]; then
    while IFS= read -r patch_name; do
        # skip blank lines and comments in the series file
        case "${patch_name}" in ''|'#'*) continue ;; esac
        echo "    Applying ${patch_name}..."
        if ! patch -p1 --forward --dry-run < "${SCRIPT_DIR}/patches/${patch_name}" >/dev/null; then
            echo "[!] ERROR: ${patch_name} does not apply cleanly." >&2
            echo "    Upstream changed or the patch series is out of date." >&2
            exit 1
        fi
        patch -p1 --forward < "${SCRIPT_DIR}/patches/${patch_name}" >/dev/null
    done < "${SCRIPT_DIR}/patches/series"
else
    for patch_file in "${SCRIPT_DIR}"/patches/*.patch; do
        [ -e "$patch_file" ] || continue
        echo "    Applying $(basename "$patch_file")..."
        patch -p1 < "$patch_file"
    done
fi

if find . -name '*.rej' | grep -q .; then
    echo "[!] ERROR: rejected hunks left behind:" >&2
    find . -name '*.rej' >&2
    exit 1
fi
find . -name '*.orig' -delete

echo "[+] Copying kernel source to ${OUTPUT_DIR}..."
# Start from a clean tree: copying over a previous run would leave stale objects
# from the old source next to the new ones.
if [ -d "${OUTPUT_DIR}" ]; then
    echo "    Removing previous ${OUTPUT_DIR}"
    rm -rf "${OUTPUT_DIR}"
fi
mkdir -p "${OUTPUT_DIR}"
cp -r kernel/* "${OUTPUT_DIR}/"
# The kernel Makefile references headers outside kernel/ (e.g. uapi/) via
# KSU_KERNEL_DIR=$(srcroot), so copy the repo-root dirs it includes.
cp -r uapi "${OUTPUT_DIR}/"

echo "[+] Copying DKMS build files..."
cp "${SCRIPT_DIR}/dkms.conf" "${OUTPUT_DIR}/"
cp "${SCRIPT_DIR}/Makefile" "${OUTPUT_DIR}/"

echo "[+] Substituting version placeholders in dkms.conf..."
sed -i "s|@PKGVER@|${KERNELSU_VERSION#v}|g; s|@KSU_GIT_VERSION@|${GIT_VERSION}|g" "${OUTPUT_DIR}/dkms.conf"

echo "[+] Done!"
echo "    Source ready at: ${OUTPUT_DIR}"
echo "    Version: ${KERNELSU_VERSION#v}"
echo "    Git version: ${GIT_VERSION}"
echo
echo "Next steps:"
echo "  sudo dkms add -m kernelsu -v ${KERNELSU_VERSION#v}"
echo "  sudo dkms build -m kernelsu -v ${KERNELSU_VERSION#v}"
echo "  sudo dkms install -m kernelsu -v ${KERNELSU_VERSION#v}"