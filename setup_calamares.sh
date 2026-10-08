#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - setup_calamares.sh
# Configures the Calamares installer for live-boot -> disk installation.
#
# IMPORTANT: This script runs INSIDE the live-build chroot as root (via
# config/hooks/live/*.chroot). There is NO sudo binary guaranteed to exist
# in a minimal debootstrap chroot, and even if it did, we are already root.
# Therefore this script contains ZERO occurrences of `sudo`.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

trap 'retro_error "setup_calamares.sh failed at line ${LINENO} (exit ${?})."' ERR

retro_info "=== Calamares Installer Setup (chroot-safe, no sudo) ==="

export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# 1. Install Calamares and required modules
# -----------------------------------------------------------------------------
retro_info "Installing Calamares and modules..."
apt-get update -qq
apt-get install -y -qq \
    calamares \
    calamares-settings-debian \
    squashfs-tools \
    parted \
    gdisk \
    grub-efi-amd64-signed \
    grub-efi-amd64-bin \
    os-prober \
    plymouth \
    >/dev/null || retro_warn "Some Calamares packages unavailable at build time - continuing."

mkdir -p /etc/calamares/modules
mkdir -p /etc/calamares/branding/retro-os

retro_ok "Calamares base packages installed."

# -----------------------------------------------------------------------------
# 2. /etc/calamares/settings.conf
# -----------------------------------------------------------------------------
retro_info "Writing /etc/calamares/settings.conf..."

cat > /etc/calamares/settings.conf << 'SETTINGSCONF'
# Retro OS - Calamares master settings
modules-search: [ local ]

instances:
- id:       rootfs
  module:   unpackfs
  config:   unpackfs.conf

sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - luksbootkeyfile
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - services-systemd
  - packages
  - initramfs
  - bootloader
  - umount
- show:
  - finished

branding: retro-os

prompt-install: true
dont-chroot: false
oem-setup: false
disable-cancel: false
disable-cancel-during-exec: true
quit-at-end: false
SETTINGSCONF

retro_ok "settings.conf written."

# -----------------------------------------------------------------------------
# 3. /etc/calamares/modules/unpackfs.conf
#    Maps the live squashfs dynamically onto the target root filesystem "/".
# -----------------------------------------------------------------------------
retro_info "Writing /etc/calamares/modules/unpackfs.conf..."

cat > /etc/calamares/modules/unpackfs.conf << 'UNPACKFSCONF'
# Retro OS - Calamares unpackfs module configuration
# Live-build mount path compatibility
unpack:
    - source: "/lib/live/mount/medium/live/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
UNPACKFSCONF

# Live medium symlink fix (both /run/live and /lib/live supported)
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/calamares-medium-fix.service << 'SERVICE'
[Unit]
Description=Fix Live Media Mount Path for Calamares
DefaultDependencies=no
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [ -d /lib/live/mount/medium ] && [ ! -d /run/live/medium ]; then mkdir -p /run/live && ln -sf /lib/live/mount/medium /run/live/medium; fi'

[Install]
WantedBy=multi-user.target
SERVICE

if is_command systemctl; then
    systemctl enable calamares-medium-fix.service >/dev/null 2>&1 || true
fi

retro_ok "unpackfs.conf and path compatibility service configured."

# -----------------------------------------------------------------------------
# 4. Branding: Retro OS identity + dark theme metadata
# -----------------------------------------------------------------------------
retro_info "Writing Calamares branding (Retro OS dark theme)..."

cat > /etc/calamares/branding/retro-os/branding.desc << BRANDINGDESC
# Retro OS - Calamares branding descriptor
componentName: retro-os

welcomeStyleCalamares: true
welcomeExpandingLogo: true

strings:
    productName:         "${RETRO_OS_NAME}"
    shortProductName:    "RetroOS"
    version:              "${RETRO_OS_VERSION}"
    shortVersion:         "${RETRO_OS_VERSION}"
    versionedName:        "${RETRO_OS_NAME} ${RETRO_OS_VERSION}"
    shortVersionedName:   "RetroOS ${RETRO_OS_VERSION}"
    bootloaderEntryName:  "${RETRO_OS_NAME}"
    productUrl:           "https://example.invalid/retro-os"
    supportUrl:           "https://example.invalid/retro-os/support"
    releaseNotesUrl:      "https://example.invalid/retro-os/notes"

# images:
#    productLogo:          "logo.png"
#    productIcon:           "logo.png"
#    productWelcome:        "welcome.png"
# slideshow:                "show.qml"

style:
   sidebarBackground:     "${RETRO_BG_COLOR}"
   sidebarText:            "${RETRO_FG_COLOR}"
   sidebarTextSelect:      "${RETRO_ACCENT_COLOR}"
   sidebarTextHighlight:   "${RETRO_ACCENT_COLOR}"
BRANDINGDESC

retro_ok "Calamares branding written."

# -----------------------------------------------------------------------------
# 5. Bootloader module sanity config (no sudo, chroot-safe defaults)
# -----------------------------------------------------------------------------
retro_info "Writing bootloader config for grub-efi hybrid boot..."

cat > /etc/calamares/modules/bootloader.conf << 'BOOTLOADERCONF'
efiBootLoader: "grub"
kernel: "/vmlinuz"
img: "/initrd.img"
efiBootloaderId: "retro-os"
installEFIFallback: true
timeout: "10"
BOOTLOADERCONF

retro_ok "bootloader.conf written."

retro_ok "=== Calamares setup complete (no sudo used, chroot-safe). ==="
