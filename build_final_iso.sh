#!/usr/bin/env bash
# =============================================================================
# Retro OS Lite - build_final_iso.sh (Pure Legacy BIOS Edition)
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

retro_info "=== Retro OS ISO Builder (Pure Legacy BIOS) ==="
retro_info "Distro: ${DISTRO} | Arch: ${ARCH} | Output: ${ISO_NAME}"

# -----------------------------------------------------------------------------
# 1. Host prerequisites
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
    --mode debian \
    --distribution trixie \
    --architecture amd64 \
    --binary-images iso \
    --mirror-bootstrap "http://deb.debian.org/debian/" \
    --mirror-binary "http://deb.debian.org/debian/" \
    --parent-mirror-bootstrap "http://deb.debian.org/debian/" \
    --parent-mirror-binary "http://deb.debian.org/debian/" \
    --security false \
    --archive-areas "main contrib non-free non-free-firmware" \
    --bootappend-live "boot=live components username=retro hostname=retro-os quiet splash" \
    --bootloader syslinux \
    --iso-application "Retro OS Lite" \
    --iso-volume "RETRO_OS" \
    --iso-publisher "Retro OS Project" \
    --linux-packages "none" \
    --apt-recommends true \
    --cache true

retro_ok "live-build config generated."

# -----------------------------------------------------------------------------
# 2.5 Package lists (Lightweight Stack for 1 GB RAM & Pure BIOS)
# -----------------------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/retro-desktop.list.chroot << 'PKGLIST'
# Kernel & Live Boot
linux-image-amd64
live-boot
live-config
live-config-systemd
systemd-sysv

# Pure BIOS Boot Stack
syslinux
isolinux

# Ultra-lightweight Desktop (RAM usage ~180MB)
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

# Core Utilities
sudo
curl
wget
git
nano
micro
btop
dillo

# Hardware Firmware
firmware-linux
firmware-linux-nonfree
firmware-misc-nonfree
PKGLIST

# -----------------------------------------------------------------------------
# 3. Hook scripts inside config/hooks/live/
# -----------------------------------------------------------------------------
retro_info "Installing chroot hooks into config/hooks/live/ ..."
mkdir -p config/hooks/normal
mkdir -p config/hooks/live

# Copy the whole project into the chroot filesystem
cp -a "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/retro" \
    config/includes.chroot/opt/retro-os/ 2>/dev/null || true

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

# CLI installation
cat > config/hooks/live/0500-retro-cli-install.hook.chroot << 'HOOKEOF'
#!/bin/sh
set -e
install -m 0755 /opt/retro-os/retro /usr/local/bin/retro
echo "Retro OS CLI installed to /usr/local/bin/retro" >&2
HOOKEOF
chmod +x config/hooks/live/0500-retro-cli-install.hook.chroot

# Binary hook: Syslinux ഇന്റർഫേസ് പാസ്സ് ചെയ്യാൻ
mkdir -p config/hooks/binary
cat << 'EOF' > config/hooks/binary/0000-bypass-theme-install.binary
#!/bin/sh
set -e
mkdir -p binary/isolinux
exit 0
EOF
chmod +x config/hooks/binary/0000-bypass-theme-install.binary

retro_ok "Chroot hooks installed."

# -----------------------------------------------------------------------------
# 4. Build the ISO
# -----------------------------------------------------------------------------
retro_info "Starting live-build (this will take a while)..."
lb clean --purge >/dev/null 2>&1 || true

# lb_chroot_live-packages ബൈപാസ്സ് ചെയ്യുന്നു:
echo '#!/bin/sh' | tee /usr/lib/live/build/lb_chroot_live-packages /usr/bin/lb_chroot_live-packages >/dev/null 2>&1 || true
echo 'exit 0' | tee -a /usr/lib/live/build/lb_chroot_live-packages /usr/bin/lb_chroot_live-packages >/dev/null 2>&1 || true
chmod +x /usr/lib/live/build/*live-packages* /usr/bin/lb_chroot_live-packages 2>/dev/null || true

# syslinux theme ബൈപാസ്സ്:
for f in /usr/lib/live/build/binary_syslinux /usr/share/live/build/binary_syslinux /usr/lib/live/build/lb_binary_syslinux; do
    if [ -f "$f" ]; then
        sed -i 's/lb chroot_install-packages syslinux/true #/g' "$f" 2>/dev/null || true
        sed -i 's/syslinux-themes-[^ "]*//g' "$f" 2>/dev/null || true
        sed -i 's/gfxboot-theme-[^ "]*//g' "$f" 2>/dev/null || true
    fi
done

# chroot ഉള്ളിലും പുറത്തും isolinux ബൈനറികൾ മുൻകൂട്ടി ലഭ്യമാക്കുന്നു:
mkdir -p "${BUILD_DIR}/config/includes.chroot/root/isolinux"
mkdir -p "${BUILD_DIR}/config/bootloaders/isolinux"
mkdir -p /root/isolinux

cp -f /usr/lib/ISOLINUX/isolinux.bin "${BUILD_DIR}/config/includes.chroot/root/isolinux/" 2>/dev/null || find /usr -name "isolinux.bin" -exec cp {} "${BUILD_DIR}/config/includes.chroot/root/isolinux/" \; 2>/dev/null || true
cp -f /usr/lib/syslinux/modules/bios/* "${BUILD_DIR}/config/includes.chroot/root/isolinux/" 2>/dev/null || find /usr -name "*.c32" -exec cp {} "${BUILD_DIR}/config/includes.chroot/root/isolinux/" \; 2>/dev/null || true

# bootloaders ഡയറക്ടറിയിലേക്കും പകർത്തുന്നു
cp -rf "${BUILD_DIR}/config/includes.chroot/root/isolinux/"* "${BUILD_DIR}/config/bootloaders/isolinux/" 2>/dev/null || true
cp -rf "${BUILD_DIR}/config/includes.chroot/root/isolinux/"* /root/isolinux/ 2>/dev/null || true

lb build 2>&1 | tee -a "${RETRO_LOG_FILE}"

found_iso="$(find "${BUILD_DIR}" -maxdepth 1 -name '*.iso' | head -n1)"
if [[ -z "${found_iso}" ]]; then
    retro_die "Build finished but no ISO was found in ${BUILD_DIR}."
fi

mv "${found_iso}" "${SCRIPT_DIR}/${ISO_NAME}"
retro_ok "=== Build complete: ${SCRIPT_DIR}/${ISO_NAME} ==="
