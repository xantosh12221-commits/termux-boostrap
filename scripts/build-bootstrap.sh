#!/usr/bin/env bash
# ==============================================================================
# Build Script: Custom Termux Bootstrap Generator for Android Apps
# Target: Full base + apt + pkg + git + zsh + proot + bash (aarch64)
# ==============================================================================
set -euo pipefail

TARGET_ARCH="${TARGET_ARCH:-aarch64}"
EXTRA_PACKAGES="${ADDITIONAL_PACKAGES:-git zsh proot}"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/dist}"

# Unset environment variable so generate-bootstraps.sh doesn't inherit a space-delimited string
unset ADDITIONAL_PACKAGES

echo "======================================================================"
echo " Starting Termux Bootstrap Generation"
echo " Target Architecture  : ${TARGET_ARCH}"
echo " Extra Packages       : ${EXTRA_PACKAGES}"
echo " Output Directory     : ${OUTPUT_DIR}"
echo "======================================================================"

# Configure Git to avoid ownership issues in container
git config --global --add safe.directory "*" || true

TERMUX_PACKAGES_DIR="/home/builder/termux-packages"

# ------------------------------------------------------------------------------
# 1. Clone/Setup termux-packages repository
# ------------------------------------------------------------------------------
echo "[*] Setting up termux-packages repository..."
cd /home/builder

if [ ! -f "${TERMUX_PACKAGES_DIR}/scripts/generate-bootstraps.sh" ] || [ ! -f "${TERMUX_PACKAGES_DIR}/scripts/properties.sh" ]; then
    echo "[*] Cloning fresh termux/termux-packages into ${TERMUX_PACKAGES_DIR}..."
    rm -rf "${TERMUX_PACKAGES_DIR}"
    git clone --depth=1 https://github.com/termux/termux-packages.git "${TERMUX_PACKAGES_DIR}"
fi

cd "${TERMUX_PACKAGES_DIR}"
mkdir -p "${OUTPUT_DIR}"

# ------------------------------------------------------------------------------
# 2. Generate Bootstrap Archive with generate-bootstraps.sh
# ------------------------------------------------------------------------------
# Format additional packages as comma-separated list
ADD_PKGS_CSV=$(echo "${EXTRA_PACKAGES}" | tr ' ' ',')

echo "----------------------------------------------------------------------"
echo "[*] Generating bootstrap for ${TARGET_ARCH} with extra packages: ${ADD_PKGS_CSV}..."
echo "----------------------------------------------------------------------"

./scripts/generate-bootstraps.sh --architectures "${TARGET_ARCH}" -a "${ADD_PKGS_CSV}"

# ------------------------------------------------------------------------------
# 3. Copy generated zip to output directory
# ------------------------------------------------------------------------------
if [ -f "bootstrap-${TARGET_ARCH}.zip" ]; then
    cp -f "bootstrap-${TARGET_ARCH}.zip" "${OUTPUT_DIR}/bootstrap-${TARGET_ARCH}.zip"
    echo "[+] Successfully created ${OUTPUT_DIR}/bootstrap-${TARGET_ARCH}.zip"
    ls -lh "${OUTPUT_DIR}/bootstrap-${TARGET_ARCH}.zip"
elif [ -f "${TERMUX_PACKAGES_DIR}/bootstrap-${TARGET_ARCH}.zip" ]; then
    cp -f "${TERMUX_PACKAGES_DIR}/bootstrap-${TARGET_ARCH}.zip" "${OUTPUT_DIR}/bootstrap-${TARGET_ARCH}.zip"
    echo "[+] Successfully created ${OUTPUT_DIR}/bootstrap-${TARGET_ARCH}.zip"
    ls -lh "${OUTPUT_DIR}/bootstrap-${TARGET_ARCH}.zip"
else
    echo "[!] Error: Could not find generated bootstrap-${TARGET_ARCH}.zip"
    exit 1
fi

echo "======================================================================"
echo "[+] Termux Bootstrap Build Complete!"
echo "======================================================================"
