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

# Brave Browser GPG Key & Repository setup
mkdir -p config/archives
curl -fsSLo config/archives/brave-browser-release.key https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
cat << 'EOF' > config/archives/brave-browser-release.list.chroot
deb [signed-by=/etc/apt/trusted.gpg.d/brave-browser-release.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main
EOF

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

# Security & Network Auditing Stack
hydra
john
nikto
sqlmap
wifite
aircrack-ng
wireless-tools

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

# Clipboard, Archive, File Management Utilities
xclip
xsel
gvfs
gvfs-backends
gvfs-fuse
xarchiver
unzip
p7zip-full
tzdata
volumeicon-alsa

# Core Utilities
sudo
curl
wget
git
nano
micro
btop
python3
python3-pip
nodejs
geany
firefox-esr
brave-browser
mpv
yt-dlp

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

# includes.chroot ഡയറക്ടറികൾ ഉണ്ടാക്കുന്നു
mkdir -p config/includes.chroot/opt/retro-os
mkdir -p config/includes.chroot/usr/share/backgrounds/retro-os

# പ്രൊജക്റ്റ് ഫയലുകൾ പകർന്നു നൽകുന്നു
cp -a "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/retro" \
    config/includes.chroot/opt/retro-os/

# ഇമേജുകൾ assets ഫോൾഡറിൽ നിന്നോ റൂട്ട് ഫോൾഡറിൽ നിന്നോ പൂർണ്ണമായി പകർത്തുന്നു
if [ -d "${SCRIPT_DIR}/assets" ]; then
    cp -a "${SCRIPT_DIR}/assets"/* config/includes.chroot/usr/share/backgrounds/retro-os/
fi
# -----------------------------------------------------------------------------
# Chroot Includes: Wallpapers, Themes & Skel configs
# -----------------------------------------------------------------------------
mkdir -p config/includes.chroot/opt/retro-os
mkdir -p config/includes.chroot/usr/share/backgrounds/retro-os
mkdir -p config/includes.chroot/etc/skel/.config/openbox
mkdir -p config/includes.chroot/etc/skel/.config/pcmanfm/default
mkdir -p config/includes.chroot/etc/skel/.config/tint2
mkdir -p config/includes.chroot/etc/skel/.config/kitty
mkdir -p config/includes.chroot/etc/skel/Desktop

# പ്രൊജക്റ്റ് ഫയലുകൾ പകർന്നു നൽകുന്നു
cp -a "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/retro" \
    config/includes.chroot/opt/retro-os/

# ഇമേജുകൾ എവിടെയാണെങ്കിലും കണ്ടെത്തി പകർത്തുന്നു
find "${SCRIPT_DIR}" -maxdepth 2 -type f \( -name "*.png" -o -name "*.jpg" \) -exec cp -f {} config/includes.chroot/usr/share/backgrounds/retro-os/ \; 2>/dev/null || true

# 1. PCManFM Wallpaper & Desktop Right-Click Settings
cat << 'EOF' > config/includes.chroot/etc/skel/.config/pcmanfm/default/desktop-items-0.conf
[*]
wallpaper_mode=fit
wallpaper=/usr/share/backgrounds/retro-os/wallpaper.png
desktop_bg=#0D0F12
desktop_fg=#E0E0E0
desktop_shadow=#000000
desktop_font=JetBrains Mono 10
show_wm_menu=0
sort_by=2
sort_type=0
show_documents=0
show_trash=1
show_mounts=1
EOF

# 2. Openbox Menu (Right-click fallback)
cat << 'EOF' > config/includes.chroot/etc/skel/.config/openbox/menu.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Retro OS">
    <item label="Terminal"><action name="Execute"><command>kitty</command></action></item>
    <item label="Web Browser"><action name="Execute"><command>firefox-esr</command></action></item>
    <item label="File Manager"><action name="Execute"><command>pcmanfm</command></action></item>
    <separator />
    <menu id="cyber-tools" label="Security Tools">
      <item label="Nmap Scanner"><action name="Execute"><command>kitty -e nmap</command></action></item>
      <item label="SQLMap"><action name="Execute"><command>kitty -e sqlmap</command></action></item>
      <item label="Hydra"><action name="Execute"><command>kitty -e hydra</command></action></item>
      <item label="John The Ripper"><action name="Execute"><command>kitty -e john</command></action></item>
      <item label="Nikto"><action name="Execute"><command>kitty -e nikto</command></action></item>
      <item label="Wifite"><action name="Execute"><command>kitty -e sudo wifite</command></action></item>
    </menu>
    <separator />
    <item label="Exit"><action name="Exit" /></item>
  </menu>
</openbox_menu>
EOF

# 3. Openbox Autostart (വാൾപേപ്പർ, പാനൽ, ഡെസ്ക്ടോപ്പ്)
cat << 'EOF' > config/includes.chroot/etc/skel/.config/openbox/autostart
picom -b &
tint2 &
pcmanfm --desktop &
EOF

# 4. ടൈംസോൺ ഇന്ത്യയിലേക്ക് സെറ്റ് ചെയ്യുന്നു
mkdir -p config/includes.chroot/etc
ln -sf /usr/share/zoneinfo/Asia/Kolkata config/includes.chroot/etc/localtime
echo "Asia/Kolkata" > config/includes.chroot/etc/timezone

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
# 3.1Clean LightDM Autologin Hook (live-config safe)
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

# യൂസറുടെ ഫോൾഡറിലേക്ക് കോൺഫിഗറേഷനുകൾ പകർന്നു നൽകുന്നു
cp -rT /etc/skel /home/retro/ 2>/dev/null || true
chown -R retro:retro /home/retro 2>/dev/null || true

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
PROMPT 1
TIMEOUT 100

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

retro_info "Injecting permanent password bypass into rootfs..."

# 1. retro യൂസറെ ഉണ്ടാക്കുന്നു
chroot "${BUILD_DIR}/chroot" useradd -m -s /bin/bash -u 1000 retro 2>/dev/null || true

# 2. ഷാഡോ ഫയലിലെ ലോക്ക് (!) നേരിട്ട് മായ്ച്ചു കളയുന്നു (Password Blank ആക്കുന്നു)
sed -i 's/^retro:[^:]*:/retro::/' "${BUILD_DIR}/chroot/etc/shadow"
sed -i 's/^root:[^:]*:/root::/' "${BUILD_DIR}/chroot/etc/shadow"

# 3. 'retro' എന്ന പാസ്‌വേഡ് സെറ്റ് ചെയ്യുന്നു
chroot "${BUILD_DIR}/chroot" sh -c "echo 'retro:retro' | chpasswd"
chroot "${BUILD_DIR}/chroot" sh -c "echo 'root:retro' | chpasswd"

# 4. LightDM-ൽ PAM പാസ്‌വേഡ് പരിശോധന പൂർണ്ണമായി ഒഴിവാക്കുന്നു (Autologin Bypass)
mkdir -p "${BUILD_DIR}/chroot/etc/pam.d"
cat << 'PAMEOF' > "${BUILD_DIR}/chroot/etc/pam.d/lightdm-autologin"
#%PAM-1.0
auth        sufficient  pam_permit.so
account     sufficient  pam_permit.so
password    sufficient  pam_permit.so
session     sufficient  pam_permit.so
PAMEOF

# 5. Sudo-യ്ക്ക് പൂർണ്ണ അനുമതി നൽകുന്നു
mkdir -p "${BUILD_DIR}/chroot/etc/sudoers.d"
echo "ALL ALL=(ALL) NOPASSWD: ALL" > "${BUILD_DIR}/chroot/etc/sudoers.d/00-retro-nopasswd"
chmod 0440 "${BUILD_DIR}/chroot/etc/sudoers.d/00-retro-nopasswd"

retro_ok "Rootfs shadow file unlocked and PAM bypass configured."

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
