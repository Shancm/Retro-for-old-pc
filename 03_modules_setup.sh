#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - 03_modules_setup.sh
# Rootless Podman/Distrobox, UFW firewall, Tor, WireGuard, modern CLI tools.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/config.env"
require_root

retro_info "Lite modules: minimal CLI tools only..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq btop micro nmap fzf curl wget pciutils usbutils >/dev/null

retro_ok "Lite modules installed."

# -----------------------------------------------------------------------------
# 1. UFW firewall - default deny incoming, allow outgoing
# -----------------------------------------------------------------------------
retro_info "Configuring UFW firewall (default-deny incoming)..."
apt-get install -y -qq ufw >/dev/null

ufw --force reset >/dev/null 2>&1 || true
if [[ "${RETRO_CHROOT_BUILD:-0}" != "1" ]]; then
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw allow ssh >/dev/null 2>&1 || true
else
    retro_warn "Chroot build: UFW rule configuration skipped until first boot."
fi

if is_command systemctl; then
    systemctl enable ufw.service >/dev/null 2>&1 || true
fi
# Do not force-enable ufw inside a chroot (no netfilter available at build time)
if [[ -d /run/systemd/system ]] && [[ "${RETRO_CHROOT_BUILD:-0}" != "1" ]]; then
    ufw --force enable >/dev/null 2>&1 || retro_warn "ufw enable deferred to first real boot."
else
    retro_warn "Chroot/build environment detected - UFW will enable on first real boot."
fi

retro_ok "UFW firewall configured."

# -----------------------------------------------------------------------------
# 2. Modern CLI tools
# -----------------------------------------------------------------------------
retro_info "Installing modern CLI toolkit (btop, ripgrep, micro, nmap, etc)..."
apt-get install -y -qq \
    btop \
    ripgrep \
    micro \
    nmap \
    fzf \
    fd-find \
    bat \
    htop \
    tmux \
    jq \
    net-tools \
    rsync \
    unzip \
    >/dev/null

retro_ok "Modern CLI toolkit installed."

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/config.env"
require_root

retro_info "Lite modules: minimal CLI tools only..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq btop micro nmap fzf curl wget pciutils usbutils >/dev/null

retro_ok "=== Lite modules setup complete. ==="
