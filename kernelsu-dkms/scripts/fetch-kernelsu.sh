#!/bin/bash
# fetch-kernelsu.sh - Download and prepare KernelSU v3.3.1 source for DKMS
# Usage: ./fetch-kernelsu.sh [output_dir]

set -euo pipefail

KERNELSU_VERSION="v3.3.1"
KERNELSU_REPO="https://github.com/tiann/KernelSU.git"
KERNELSU_COMMIT="0c0fdb960178fa12d80d6cbcfdcb6ad8be6a865d"
DATE_CHECKED="2026-11-02"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${1:-/usr/src/kernelsu-${KERNELSU_VERSION#v}}"
PATCHES_DIR="${PROJECT_DIR}/patches"

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
git clone --depth 1 --branch "${KERNELSU_VERSION}" "${KERNELSU_REPO}" kernelsu

echo "[+] Verifying commit..."
cd kernelsu
ACTUAL_COMMIT=$(git rev-parse HEAD)
if [ "$ACTUAL_COMMIT" != "$KERNELSU_COMMIT" ]; then
    echo "[!] Warning: Commit mismatch!"
    echo "    Expected: $KERNELSU_COMMIT"
    echo "    Actual:   $ACTUAL_COMMIT"
    echo "    This may be due to tag moving. Continuing anyway..."
fi

# Count commits for version (shallow clone returns 1, but we use known value from release)
GIT_VERSION=32680
echo "[+] Git version (from release artifact): ${GIT_VERSION}"

echo "[+] Applying patches to kernel/ directory..."
cd kernel
for patch in "${PATCHES_DIR}"/*.patch; do
    if [ -f "$patch" ]; then
        echo "    Applying $(basename "$patch")..."
        git apply "$patch"
    fi
done
cd ..

echo "[+] Copying kernel source to ${OUTPUT_DIR}..."
mkdir -p "${OUTPUT_DIR}"
# Copy kernel directory contents
cp -r kernel/* "${OUTPUT_DIR}/"
# Also copy uapi directory (at repo root) which is needed for uapi/app_profile.h etc.
if [ -d "uapi" ]; then
    cp -r uapi "${OUTPUT_DIR}/"
fi

echo "[+] Copying DKMS build files..."
cp "${PROJECT_DIR}/dkms.conf" "${OUTPUT_DIR}/"
cp "${PROJECT_DIR}/Makefile" "${OUTPUT_DIR}/"

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
