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
    liblzo2-2 \
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
    --bootappend-live "boot=live components username=retro hostname=retro-os persistence quiet splash" \
    --bootloader syslinux \
    --iso-application "Retro OS Lite" \
    --iso-volume "RETRO_OS" \
    --iso-publisher "Retro OS Project" \
    --linux-packages "none" \
    --apt-recommends false \
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

# -----------------------------------------------------------------------------
# Clean LightDM Autologin Hook (live-config safe)
# -----------------------------------------------------------------------------
cat > config/hooks/live/0050-setup-autologin.hook.chroot << 'AUTOHOOK'
#!/bin/sh
set -e

# ലൈറ്റ്ഡിഎം കോൺഫിഗറേഷനിൽ നേരിട്ട് ആക്സസ് നൽകുന്നു
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'AUTOCONF' > /etc/lightdm/lightdm.conf.d/autologin.conf
[Seat:*]
autologin-user=retro
autologin-user-timeout=0
user-session=openbox
pam-service=lightdm-autologin
pam-autologin-service=lightdm-autologin
AUTOCONF

# udevadm ലോക്കപ്പ് ആവാതിരിക്കാൻ സിസ്റ്റംഡ് വർക്കർമാർക്ക് നിയന്ത്രണം നൽകുന്നു
mkdir -p /etc/systemd/system/systemd-udevd.service.d
cat << 'UDEVCONF' > /etc/systemd/system/systemd-udevd.service.d/override.conf
[Service]
TimeoutSec=60
UDEVCONF

# sudo-യ്ക്ക് പാസ്‌വേഡ് ഒഴിവാക്കുന്നു
mkdir -p /etc/sudoers.d
echo "ALL ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/retro-nopasswd
chmod 0440 /etc/sudoers.d/retro-nopasswd

AUTOHOOK
chmod +x config/hooks/live/0050-setup-autologin.hook.chroot

# Pure BIOS Dummy Theme & Isolinux binary hook
mkdir -p config/hooks/binary
cat << 'EOF' > config/hooks/binary/0000-bypass-theme-install.binary
#!/bin/sh
set -e
mkdir -p binary/isolinux
# isolinux ബൈനറികൾ നേരിട്ട് binary/isolinux-ലേക്ക് പകർന്നു നൽകുന്നു
cp -f /usr/lib/ISOLINUX/isolinux.bin binary/isolinux/ 2>/dev/null || find /usr -name "isolinux.bin" -exec cp {} binary/isolinux/ \; 2>/dev/null || true
cp -f /usr/lib/syslinux/modules/bios/* binary/isolinux/ 2>/dev/null || find /usr -name "*.c32" -exec cp {} binary/isolinux/ \; 2>/dev/null || true
touch binary/isolinux/bootlogo
exit 0
EOF
chmod +x config/hooks/binary/0000-bypass-theme-install.binary

retro_ok "Chroot hooks installed."

# -----------------------------------------------------------------------------
# 4. Bootloader setup & Build
# -----------------------------------------------------------------------------
# lb_chroot_live-packages തകരാർ ഒഴിവാക്കാൻ dummy സ്ക്രിപ്റ്റ് നൽകുന്നു
echo '#!/bin/sh' | tee /usr/lib/live/build/lb_chroot_live-packages /usr/bin/lb_chroot_live-packages >/dev/null 2>&1 || true
echo 'exit 0' | tee -a /usr/lib/live/build/lb_chroot_live-packages /usr/bin/lb_chroot_live-packages >/dev/null 2>&1 || true
chmod +x /usr/lib/live/build/*live-packages* /usr/bin/lb_chroot_live-packages 2>/dev/null || true

# lb_binary_syslinux ക്രാഷ് ആകുന്നത് തടയാൻ dummy സ്ക്രിപ്റ്റ് നൽകുന്നു
echo '#!/bin/sh' | tee /usr/lib/live/build/lb_binary_syslinux /usr/bin/lb_binary_syslinux >/dev/null 2>&1 || true
echo 'exit 0' | tee -a /usr/lib/live/build/lb_binary_syslinux /usr/bin/lb_binary_syslinux >/dev/null 2>&1 || true
chmod +x /usr/lib/live/build/*syslinux* /usr/bin/lb_binary_syslinux 2>/dev/null || true

# ആവശ്യമായ ഡയറക്ടറികൾ നിർമ്മിക്കുന്നു
mkdir -p "${BUILD_DIR}/config/bootloaders/isolinux"
mkdir -p "${BUILD_DIR}/binary/isolinux"
mkdir -p "${BUILD_DIR}/binary/boot/isolinux"

# ISOLINUX ബൈനറികളും എല്ലാ COM32 മൊഡ്യൂളുകളും കോപ്പി ചെയ്യുന്നു
cp -f /usr/lib/ISOLINUX/isolinux.bin "${BUILD_DIR}/binary/isolinux/" 2>/dev/null || true
cp -f /usr/lib/syslinux/modules/bios/* "${BUILD_DIR}/binary/isolinux/" 2>/dev/null || true
cp -f /usr/lib/ISOLINUX/isolinux.bin "${BUILD_DIR}/config/bootloaders/isolinux/" 2>/dev/null || true
cp -f /usr/lib/syslinux/modules/bios/* "${BUILD_DIR}/config/bootloaders/isolinux/" 2>/dev/null || true
touch "${BUILD_DIR}/binary/isolinux/bootlogo"

# isolinux.cfg കോൺഫിഗറേഷൻ നിർമ്മിക്കുന്നു
cat << 'EOF' > "${BUILD_DIR}/binary/isolinux/isolinux.cfg"
UI vesamenu.c32
PROMPT 0
TIMEOUT 50

MENU TITLE Retro OS Lite (Legacy BIOS)

LABEL live
  MENU LABEL Boot Retro OS Lite
  MENU DEFAULT
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components username=retro user-default-groups=sudo,audio,video,input,plugdev,netdev autologin persistence quiet splash nowatchdog udev.children_max=1

LABEL failsafe
  MENU LABEL Boot Retro OS Lite (Fail-safe)
  LINUX /live/vmlinuz
  INITRD /live/initrd.img
  APPEND boot=live components username=retro autologin memtest noapic noapm nodma nomce nolapic nomodeset nosmp nospectre_v2 nospec_store_bypass_disable nowatchdog
EOF

# എല്ലാ പാത്തുകളിലേക്കും കോൺഫിഗറേഷൻ ഉറപ്പാക്കുന്നു
cp -f "${BUILD_DIR}/binary/isolinux/isolinux.cfg" "${BUILD_DIR}/config/bootloaders/isolinux/isolinux.cfg"
cp -f "${BUILD_DIR}/binary/isolinux/isolinux.cfg" "${BUILD_DIR}/binary/boot/isolinux/isolinux.cfg"

# ISO ബിൽഡ് ഘട്ടങ്ങൾ ക്രമമായി റൺ ചെയ്യുന്നു
retro_info "Starting live-build bootstrap & chroot..."
lb bootstrap 2>&1 | tee -a "${RETRO_LOG_FILE}"
lb chroot 2>&1 | tee -a "${RETRO_LOG_FILE}"

# -----------------------------------------------------------------------------
# Kernel & Initrd live/ ഫോൾഡറിലേക്ക് കോപ്പി ചെയ്യുന്നു
# -----------------------------------------------------------------------------
retro_info "Extracting kernel and initrd from chroot..."
mkdir -p "${BUILD_DIR}/binary/live"

if ls "${BUILD_DIR}"/chroot/boot/vmlinuz-* 1> /dev/null 2>&1; then
    latest_kernel="$(ls -t "${BUILD_DIR}"/chroot/boot/vmlinuz-* | head -n1)"
    latest_initrd="$(ls -t "${BUILD_DIR}"/chroot/boot/initrd.img-* | head -n1)"
    cp -vf "${latest_kernel}" "${BUILD_DIR}/binary/live/vmlinuz"
    cp -vf "${latest_initrd}" "${BUILD_DIR}/binary/live/initrd.img"
    retro_ok "Kernel and initrd copied successfully to binary/live/"
else
    retro_die "Could not find kernel in chroot/boot!"
fi

# ISOLINUX കോൺഫിഗറേഷൻ ഉറപ്പാക്കുന്നു
mkdir -p "${BUILD_DIR}/binary/isolinux" "${BUILD_DIR}/binary/boot/isolinux"
cp -f /usr/lib/ISOLINUX/isolinux.bin "${BUILD_DIR}/binary/isolinux/" 2>/dev/null || true
cp -f /usr/lib/syslinux/modules/bios/* "${BUILD_DIR}/binary/isolinux/" 2>/dev/null || true
touch "${BUILD_DIR}/binary/isolinux/bootlogo"
cp -f "${BUILD_DIR}/binary/isolinux/isolinux.cfg" "${BUILD_DIR}/binary/boot/isolinux/isolinux.cfg"

# ബൈനറി ഘട്ടങ്ങളും ISO നിർമ്മാണവും പൂർത്തിയാക്കുന്നു
retro_info "Building live system and generating final ISO..."
lb binary 2>&1 | tee -a "${RETRO_LOG_FILE}"

found_iso="$(find "${BUILD_DIR}" -maxdepth 1 -name '*.iso' | head -n1)"
if [[ -z "${found_iso}" ]]; then
    retro_die "Build finished but no ISO was found in ${BUILD_DIR}."
fi

# Puppy Linux മോഡൽ MBR ടേബിൾ ഇൻജക്റ്റ് ചെയ്യുന്നു (Hybrid Boot)
retro_info "Injecting MBR partition table (isohybrid)..."
isohybrid "${found_iso}" || true

mv "${found_iso}" "${SCRIPT_DIR}/${ISO_NAME}"
retro_ok "=== Build complete: ${SCRIPT_DIR}/${ISO_NAME} ==="
