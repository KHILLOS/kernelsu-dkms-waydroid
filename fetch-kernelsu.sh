#!/bin/bash
# fetch-kernelsu.sh - Download and prepare KernelSU v3.3.1 source for DKMS
# Usage: ./fetch-kernelsu.sh [output_dir]

set -euo pipefail

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

# Count commits for version
GIT_VERSION=$(git rev-list --count HEAD)
echo "[+] Git version (commit count): ${GIT_VERSION}"

echo "[+] Applying patches..."
for patch in /home/yash/Pictures/patches/*.patch; do
    if [ -f "$patch" ]; then
        echo "    Applying $(basename "$patch")..."
        git apply "$patch"
    fi
done

echo "[+] Copying kernel source to ${OUTPUT_DIR}..."
mkdir -p "${OUTPUT_DIR}"
cp -r kernel/* "${OUTPUT_DIR}/"

echo "[+] Copying DKMS build files..."
cp /home/yash/Pictures/dkms.conf "${OUTPUT_DIR}/"
cp /home/yash/Pictures/Makefile "${OUTPUT_DIR}/"

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