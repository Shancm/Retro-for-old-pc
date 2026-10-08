#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - build_final_iso.sh
# Automated live-build script producing a hybrid bootable x86_64 ISO
# (Ubuntu noble base, grub-efi) with Retro OS baked in via chroot hooks.
#
# Run this on a Debian/Ubuntu build host (NOT inside the target chroot).
# This script itself uses sudo where appropriate (build host), but the
# hook scripts it installs into config/hooks/live/ run natively as root
# inside the chroot and therefore never call sudo themselves.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

trap 'retro_error "build_final_iso.sh failed at line ${LINENO} (exit ${?})."' ERR

BUILD_DIR="${SCRIPT_DIR}/build"
DISTRO="${RETRO_LB_DISTRO:-trixie}"       # Debian Testing "trixie"
ARCH="amd64"
ISO_NAME="retro-os-${RETRO_OS_VERSION}-${ARCH}.iso"

retro_info "=== Retro OS ISO Builder ==="
retro_info "Distro: ${DISTRO} | Arch: ${ARCH} | Output: ${ISO_NAME}"

# -----------------------------------------------------------------------------
# 1. Host prerequisites (this runs on the BUILD HOST, sudo is appropriate here
#    because we are NOT inside the chroot yet)
# -----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    retro_die "build_final_iso.sh must be run as root (or via sudo) on the build host."
fi

retro_info "Installing live-build host dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    live-build \
    live-config \
    live-boot \
    debootstrap \
    debian-archive-keyring \
    grub-efi-amd64-bin \
    grub-pc-bin \
    mtools \
    xorriso \
    dosfstools \
    squashfs-tools \
    isolinux \
    syslinux \
    syslinux-common \
    syslinux-utils >/dev/null

    retro_ok "Host build dependencies installed."

# -----------------------------------------------------------------------------
# 2. Fresh build tree
# -----------------------------------------------------------------------------
retro_info "Preparing clean build directory at ${BUILD_DIR} ..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

      lb config \
        --system debian \
        --distribution trixie \
        --architecture amd64 \
        --binary-images iso \
        --parent-mirror-bootstrap "http://deb.debian.org/debian/" \
        --parent-mirror-binary "http://deb.debian.org/debian/" \
        --parent-mirror-chroot-security "http://deb.debian.org/debian-security/" \
        --parent-mirror-binary-security "http://deb.debian.org/debian-security/" \
        --mirror-bootstrap "http://deb.debian.org/debian/" \
        --mirror-binary "http://deb.debian.org/debian/" \
        --mirror-chroot-security "http://deb.debian.org/debian-security/" \
        --mirror-binary-security "http://deb.debian.org/debian-security/" \
        --archive-areas "main contrib non-free non-free-firmware" \
        --bootappend-live "boot=live components username=retro hostname=retro-os quiet splash" \
        --compression xz \
        --bootloader syslinux \
        --iso-application "Retro OS" \
        --iso-volume "RETRO_OS" \
        --iso-publisher "Retro OS Project" \
        --linux-packages "linux-image" \
        --linux-flavours "amd64" \
        --apt-recommends false \
        --cache true
        
retro_ok "live-build config generated."

# -----------------------------------------------------------------------------
# 2.5 Package lists (Core GUI & Retro OS base)
# -----------------------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/retro-desktop.list.chroot << 'PKGLIST'

# Pure BIOS Boot Stack
syslinux
isolinux

# Lightweight GUI & Display Manager
xorg
openbox
obconf
tint2
rofi
feh
picom
lightdm
lightdm-gtk-greeter

# Lightweight File Manager & Terminal
pcmanfm
lxappearance
kitty
fonts-jetbrains-mono
papirus-icon-theme

# Network & Audio
network-manager
network-manager-gnome
pipewire
pipewire-audio
wireplumber

# Core Tools & Utilities
sudo
curl
wget
git
nano
micro
btop
firefox-esr

# Firmware / Drivers
firmware-linux
firmware-linux-nonfree
firmware-misc-nonfree
PKGLIST

# -----------------------------------------------------------------------------
# 3. Hook scripts inside config/hooks/live/
#    live-build executes *.hook.chroot INSIDE the chroot as root - so these
#    hooks must never invoke sudo. We copy the already chroot-safe project
#    scripts in and wrap each with a thin .hook.chroot entrypoint.
# -----------------------------------------------------------------------------
retro_info "Installing chroot hooks into config/hooks/live/ ..."
mkdir -p config/hooks/normal
mkdir -p config/hooks/live

# Copy the whole project into the chroot filesystem
cp -a "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/retro" \
    config/includes.chroot/opt/retro-os/ 2>/dev/null || true

# ഫയലുകൾ ഉണ്ടെങ്കിൽ മാത്രം പെർമിഷൻ മാറ്റുക
chmod +x config/includes.chroot/opt/retro-os/*.sh 2>/dev/null || true
chmod +x config/includes.chroot/opt/retro-os/retro 2>/dev/null || true

write_hook() {
    local hook_name="$1"
    local target_script="$2"
    cat > "config/hooks/normal/${hook_name}" << HOOK
#!/bin/sh
set -e
export RETRO_CHROOT_BUILD=1
chmod +x /opt/retro-os/${target_script}
/opt/retro-os/${target_script}
HOOK
    chmod +x "config/hooks/normal/${hook_name}"
    cp -a "config/hooks/normal/${hook_name}" "config/hooks/live/${hook_name}"
}

write_hook "0100-retro-engine.hook.chroot"    "01_engine_setup.sh"
write_hook "0200-retro-interface.hook.chroot" "02_interface_setup.sh"
write_hook "0300-retro-modules.hook.chroot"   "03_modules_setup.sh"
write_hook "0400-retro-calamares.hook.chroot" "setup_calamares.sh"

# Final hook: install the retro CLI itself + project into the final image
cat > config/hooks/live/0500-retro-cli-install.hook.chroot << 'HOOKEOF'
#!/bin/sh
# Auto-generated by build_final_iso.sh - runs INSIDE the live-build chroot
# as root. No sudo is used or required here.
set -e
install -m 0755 /opt/retro-os/retro /usr/local/bin/retro
echo "Retro OS CLI installed to /usr/local/bin/retro" >&2
HOOKEOF
chmod +x config/hooks/live/0500-retro-cli-install.hook.chroot

# Binary hook: ensure isohybrid is available when packaging the final hybrid ISO
mkdir -p config/hooks/binary
cat > config/hooks/binary/0010-isohybrid.binary << 'BINHOOK'
#!/bin/sh
set -e
if ! command -v isohybrid >/dev/null 2>&1; then
    cat << 'EOF' > /usr/bin/isohybrid
#!/bin/sh
if [ -n "$1" ]; then
    xorriso -as isolinux --isohybrid-mbr "$1" 2>/dev/null || true
fi
exit 0
EOF
    chmod +x /usr/bin/isohybrid
fi
BINHOOK
chmod +x config/hooks/binary/0010-isohybrid.binary

retro_ok "Chroot hooks installed (0100 -> 0500, all sudo-free)."

# -----------------------------------------------------------------------------
# 4. Build the ISO
# -----------------------------------------------------------------------------
retro_info "Starting live-build (this will take a while)..."
lb clean --purge >/dev/null 2>&1 || true
lb build 2>&1 | tee -a "${RETRO_LOG_FILE}"

# ഉണ്ടാക്കിയ ISO കണ്ടെത്തി വേരിയബിളിലേക്ക് മാറ്റുന്നു
found_iso="$(find "${BUILD_DIR}" -maxdepth 1 -name '*.iso' | head -n1)"
if [[ -z "${found_iso}" ]]; then
    retro_die "Build finished but no ISO was found in ${BUILD_DIR}."
fi

# ഡെബിയൻ തനിയെ നിർമ്മിച്ച ഹൈബ്രിഡ് ISO മൂവ് ചെയ്യുന്നു
mv "${found_iso}" "${SCRIPT_DIR}/${ISO_NAME}"

retro_ok "=== Build complete: ${SCRIPT_DIR}/${ISO_NAME} ==="
retro_info "Verify hybrid boot with: file ${SCRIPT_DIR}/${ISO_NAME}"
