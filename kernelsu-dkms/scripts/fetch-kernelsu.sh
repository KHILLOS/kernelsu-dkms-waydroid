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
    echo "[!] Warning: Commit mismatch!"
    echo "    Expected: $KERNELSU_COMMIT"
    echo "    Actual:   $ACTUAL_COMMIT"
    echo "    This may be due to tag moving. Continuing anyway..."
fi

# Count commits for version
GIT_VERSION=$(git rev-list --count HEAD)
echo "[+] Git version (commit count): ${GIT_VERSION}"

echo "[+] Applying patches..."
if [ -f "${SCRIPT_DIR}/patches/series" ]; then
    while IFS= read -r patch_name; do
        echo "    Applying ${patch_name}..."
        patch -p1 < "${SCRIPT_DIR}/patches/${patch_name}"
    done < "${SCRIPT_DIR}/patches/series"
else
    for patch_file in "${SCRIPT_DIR}"/patches/*.patch; do
        [ -e "$patch_file" ] || continue
        echo "    Applying $(basename "$patch_file")..."
        patch -p1 < "$patch_file"
    done
fi

echo "[+] Copying kernel source to ${OUTPUT_DIR}..."
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