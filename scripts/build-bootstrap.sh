#!/usr/bin/env bash
# ==============================================================================
# Build Script: Custom Termux Bootstrap Generator for Android Apps
# Target: com.antigem (aarch64) with Full base + apt + pkg + git + zsh + bash
# ==============================================================================
set -euo pipefail

PACKAGE_NAME="${PACKAGE_NAME:-com.antigem}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
BOOTSTRAP_TYPE="${BOOTSTRAP_TYPE:-full}"
ADDITIONAL_PACKAGES="${ADDITIONAL_PACKAGES:-git zsh}"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/dist}"

echo "======================================================================"
echo " Starting Termux Bootstrap Generation"
echo " Package Name         : ${PACKAGE_NAME}"
echo " Target Architecture  : ${TARGET_ARCH}"
echo " Bootstrap Type       : ${BOOTSTRAP_TYPE}"
echo " Additional Packages  : ${ADDITIONAL_PACKAGES}"
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

# ------------------------------------------------------------------------------
# 2. Configure properties.sh with custom package name
# ------------------------------------------------------------------------------
echo "[*] Configuring scripts/properties.sh for ${PACKAGE_NAME}..."

PROPERTIES_FILE="${TERMUX_PACKAGES_DIR}/scripts/properties.sh"

if [ -f "${PROPERTIES_FILE}" ]; then
    sed -i "s/TERMUX_APP__PACKAGE_NAME=\"com.termux\"/TERMUX_APP__PACKAGE_NAME=\"${PACKAGE_NAME}\"/g" "${PROPERTIES_FILE}"
    sed -i "s/TERMUX__NAME=\"Termux\"/TERMUX__NAME=\"Antigem\"/g" "${PROPERTIES_FILE}"
    echo "[+] Updated properties.sh with TERMUX_APP__PACKAGE_NAME=\"${PACKAGE_NAME}\""
fi

mkdir -p "${OUTPUT_DIR}"

# ------------------------------------------------------------------------------
# 3. Generate Bootstrap Archive with generate-bootstraps.sh
# ------------------------------------------------------------------------------
# Format additional packages as comma-separated list
ADD_PKGS_CSV=$(echo "${ADDITIONAL_PACKAGES}" | tr ' ' ',')

echo "----------------------------------------------------------------------"
echo "[*] Generating bootstrap for ${TARGET_ARCH} with extra packages: ${ADD_PKGS_CSV}..."
echo "----------------------------------------------------------------------"

./scripts/generate-bootstraps.sh --architectures "${TARGET_ARCH}" -a "${ADD_PKGS_CSV}"

# ------------------------------------------------------------------------------
# 4. Copy generated zip to output directory
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
