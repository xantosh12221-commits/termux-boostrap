#!/usr/bin/env bash
# ==============================================================================
# Build Script: Custom Termux Bootstrap Generator for Android Apps
# Target: com.antigem (aarch64) with Full base + apt + git + zsh
# ==============================================================================
set -euo pipefail

PACKAGE_NAME="${PACKAGE_NAME:-com.antigem}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
BOOTSTRAP_TYPE="${BOOTSTRAP_TYPE:-full}"
ADDITIONAL_PACKAGES="${ADDITIONAL_PACKAGES:-git zsh}"
OUTPUT_DIR="${OUTPUT_DIR:-/workspace/dist}"

echo "======================================================================"
echo " Starting Termux Bootstrap Build"
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

if [ ! -f "${TERMUX_PACKAGES_DIR}/build-package.sh" ] || [ ! -f "${TERMUX_PACKAGES_DIR}/scripts/properties.sh" ]; then
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
    # Replace default com.termux package name with custom package name
    sed -i "s/TERMUX_APP__PACKAGE_NAME=\"com.termux\"/TERMUX_APP__PACKAGE_NAME=\"${PACKAGE_NAME}\"/g" "${PROPERTIES_FILE}"
    sed -i "s/TERMUX__NAME=\"Termux\"/TERMUX__NAME=\"Antigem\"/g" "${PROPERTIES_FILE}"
    echo "[+] Updated properties.sh with TERMUX_APP__PACKAGE_NAME=\"${PACKAGE_NAME}\""
else
    echo "[!] Error: ${PROPERTIES_FILE} not found!"
    exit 1
fi

# Ensure clean build and output state
rm -rf output "${TERMUX_PACKAGES_DIR}/output"
mkdir -p "${TERMUX_PACKAGES_DIR}/output" "${OUTPUT_DIR}"

# ------------------------------------------------------------------------------
# 3. Define package list
# ------------------------------------------------------------------------------
declare -a CORE_PACKAGES=()

if [ "${BOOTSTRAP_TYPE}" = "full" ]; then
    # Full Termux Bootstrap package list including apt & dpkg
    CORE_PACKAGES=(
        "apt"
        "bash"
        "bzip2"
        "ca-certificates"
        "command-not-found"
        "coreutils"
        "curl"
        "dash"
        "debianutils"
        "diffutils"
        "dos2unix"
        "dpkg"
        "ed"
        "findutils"
        "gawk"
        "grep"
        "gzip"
        "inetutils"
        "less"
        "lsof"
        "nano"
        "net-tools"
        "patch"
        "procps"
        "psmisc"
        "sed"
        "tar"
        "termux-am"
        "termux-exec"
        "termux-keyring"
        "termux-licenses"
        "termux-tools"
        "unzip"
        "util-linux"
        "xz-utils"
        "zlib"
    )
else
    # Minimal bootstrap
    CORE_PACKAGES=(
        "bash"
        "coreutils"
        "termux-tools"
        "termux-exec"
        "ca-certificates"
        "curl"
        "tar"
        "gzip"
        "xz-utils"
    )
fi

# Append additional packages (e.g. git, zsh)
for extra in ${ADDITIONAL_PACKAGES}; do
    if [[ ! " ${CORE_PACKAGES[*]} " =~ " ${extra} " ]]; then
        CORE_PACKAGES+=("${extra}")
    fi
done

echo "[*] Total packages to build: ${#CORE_PACKAGES[@]}"
echo "    Packages: ${CORE_PACKAGES[*]}"

# ------------------------------------------------------------------------------
# 4. Build Packages
# ------------------------------------------------------------------------------
export TERMUX_APP_PACKAGE="${PACKAGE_NAME}"
export TERMUX_APP__PACKAGE_NAME="${PACKAGE_NAME}"

for pkg in "${CORE_PACKAGES[@]}"; do
    echo "----------------------------------------------------------------------"
    echo "[*] Building package: ${pkg} with dependencies (-I) for arch ${TARGET_ARCH}..."
    echo "----------------------------------------------------------------------"
    if ./build-package.sh -I -a "${TARGET_ARCH}" "${pkg}"; then
        echo "[+] Successfully built ${pkg}"
    else
        echo "[!] Warning/Notice building ${pkg}, checking if deb was generated..."
        if ls output/*"${pkg}"*_"${TARGET_ARCH}".deb 1> /dev/null 2>&1 || ls output/*"${pkg}"*_all.deb 1> /dev/null 2>&1; then
            echo "[+] Deb for ${pkg} exists in output directory."
        else
            echo "[!] Could not find generated deb for package ${pkg} (may be subpackage or meta-package)."
        fi
    fi
done

# ------------------------------------------------------------------------------
# 5. Extract debs and assemble rootfs
# ------------------------------------------------------------------------------
echo "======================================================================"
echo "[*] Assembling RootFS & Bootstrap Archive..."
echo "======================================================================"

BUILD_ROOTFS_TMP=$(mktemp -d /tmp/termux-bootstrap-build.XXXXXX)
BOOTSTRAP_STAGING="${BUILD_ROOTFS_TMP}/staging"
mkdir -p "${BOOTSTRAP_STAGING}"

cd "${TERMUX_PACKAGES_DIR}/output"
DEB_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l || true)
if [ "${DEB_COUNT}" -eq 0 ]; then
    echo "[!] Error: No deb files found in ${TERMUX_PACKAGES_DIR}/output!"
    exit 1
fi
echo "[*] Found ${DEB_COUNT} deb packages. Extracting..."

for deb in *.deb; do
    if [[ "$deb" =~ _(all|"${TARGET_ARCH}")\.deb$ ]]; then
        echo " -> Extracting ${deb}..."
        dpkg-deb -x "${deb}" "${BOOTSTRAP_STAGING}"
    else
        echo " -> Skipping non-target deb: ${deb}"
    fi
done

# In Termux .deb packages, files are placed in data/data/<PACKAGE_NAME>/files/usr
EXPECTED_USR_DIR="${BOOTSTRAP_STAGING}/data/data/${PACKAGE_NAME}/files/usr"
FINAL_ROOTFS="${BUILD_ROOTFS_TMP}/rootfs"
mkdir -p "${FINAL_ROOTFS}"

if [ -d "${EXPECTED_USR_DIR}" ]; then
    echo "[*] Moving usr directory to bootstrap root..."
    mv "${EXPECTED_USR_DIR}" "${FINAL_ROOTFS}/usr"
elif [ -d "${BOOTSTRAP_STAGING}/usr" ]; then
    echo "[*] Moving usr directory from staging root..."
    mv "${BOOTSTRAP_STAGING}/usr" "${FINAL_ROOTFS}/usr"
else
    echo "[!] Error: Could not locate extracted 'usr' directory!"
    find "${BOOTSTRAP_STAGING}" -maxdepth 4
    exit 1
fi

# Ensure essential directory hierarchy exists
mkdir -p "${FINAL_ROOTFS}/usr/tmp"
mkdir -p "${FINAL_ROOTFS}/usr/var/log"
mkdir -p "${FINAL_ROOTFS}/usr/var/run"
mkdir -p "${FINAL_ROOTFS}/usr/var/lib/dpkg/updates"
mkdir -p "${FINAL_ROOTFS}/usr/var/lib/dpkg/info"

# Initialize dpkg status and available files if missing
if [ ! -f "${FINAL_ROOTFS}/usr/var/lib/dpkg/status" ]; then
    touch "${FINAL_ROOTFS}/usr/var/lib/dpkg/status"
fi
if [ ! -f "${FINAL_ROOTFS}/usr/var/lib/dpkg/available" ]; then
    touch "${FINAL_ROOTFS}/usr/var/lib/dpkg/available"
fi

# Populate dpkg status with installed control info if apt/dpkg is installed
if [ -d "${FINAL_ROOTFS}/usr/var/lib/dpkg" ]; then
    echo "[*] Merging control information into dpkg/status..."
    for deb in "${TERMUX_PACKAGES_DIR}/output"/*.deb; do
        if [[ "$deb" =~ _(all|"${TARGET_ARCH}")\.deb$ ]]; then
            dpkg-deb -e "$deb" "${BUILD_ROOTFS_TMP}/control_tmp"
            if [ -f "${BUILD_ROOTFS_TMP}/control_tmp/control" ]; then
                cat "${BUILD_ROOTFS_TMP}/control_tmp/control" >> "${FINAL_ROOTFS}/usr/var/lib/dpkg/status"
                echo "Status: install ok installed" >> "${FINAL_ROOTFS}/usr/var/lib/dpkg/status"
                echo "" >> "${FINAL_ROOTFS}/usr/var/lib/dpkg/status"
            fi
            rm -rf "${BUILD_ROOTFS_TMP}/control_tmp"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 6. Generate SYMLINKS.txt and remove raw symlinks
# ------------------------------------------------------------------------------
echo "[*] Generating SYMLINKS.txt manifest..."
cd "${FINAL_ROOTFS}"

SYMLINKS_FILE="${FINAL_ROOTFS}/SYMLINKS.txt"
rm -f "${SYMLINKS_FILE}"
touch "${SYMLINKS_FILE}"

while IFS= read -r -d '' link; do
    target="$(readlink "$link")"
    echo "${target}←${link}" >> "${SYMLINKS_FILE}"
    rm -f "${link}"
done < <(find . -type l -print0)

echo "[*] Total symlinks registered: $(wc -l < "${SYMLINKS_FILE}")"

# ------------------------------------------------------------------------------
# 7. Create bootstrap-aarch64.zip
# ------------------------------------------------------------------------------
ZIP_NAME="bootstrap-${TARGET_ARCH}.zip"
FINAL_ZIP_PATH="${OUTPUT_DIR}/${ZIP_NAME}"

echo "[*] Compressing into ${FINAL_ZIP_PATH}..."
rm -f "${FINAL_ZIP_PATH}"
zip -r9 "${FINAL_ZIP_PATH}" ./*

# Package built debs into a single archive to avoid colon ':' filename issues in GitHub Actions upload-artifact v4
mkdir -p "${OUTPUT_DIR}"
if ls "${TERMUX_PACKAGES_DIR}/output"/*.deb 1> /dev/null 2>&1; then
    echo "[*] Archiving built deb packages into debs.tar.gz..."
    (cd "${TERMUX_PACKAGES_DIR}/output" && tar -czf "${OUTPUT_DIR}/debs.tar.gz" *.deb) || true
fi

# Generate SHA256 checksums
cd "${OUTPUT_DIR}"
sha256sum "${ZIP_NAME}" > "SHA256SUMS.txt"
if [ -f "debs.tar.gz" ]; then
    sha256sum "debs.tar.gz" >> "SHA256SUMS.txt"
fi

# Cleanup
rm -rf "${BUILD_ROOTFS_TMP}"

echo "======================================================================"
echo " BUILD SUCCESSFUL!"
echo " Bootstrap Archive : ${FINAL_ZIP_PATH} ($(du -h "${FINAL_ZIP_PATH}" | cut -f1))"
echo " SHA256 Checksum   : $(cat "${OUTPUT_DIR}/SHA256SUMS.txt")"
echo " Output files in   : ${OUTPUT_DIR}"
echo "======================================================================"
