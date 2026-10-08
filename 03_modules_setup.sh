#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - 03_modules_setup.sh
# Rootless Podman/Distrobox, UFW firewall, , WireGuard, modern CLI tools.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/config.env"
require_root

retro_info "Lite modules: minimal CLI tools only..."
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq btop micro nmap fzf curl wget pciutils usbutils >/dev/null

retro_ok "=== Lite modules setup complete. ==="
