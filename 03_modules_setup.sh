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

# Security Tools-ന് .desktop ഫയലുകൾ നിർമ്മിക്കുന്നു
mkdir -p /usr/share/applications

make_tool_entry() {
    local name="$1"
    local cmd="$2"
    local icon="$3"
    cat << EOF > "/usr/share/applications/${name}.desktop"
[Desktop Entry]
Name=${name}
Exec=kitty -e ${cmd}
Icon=${icon}
Terminal=false
Type=Application
Categories=Utility;System;
EOF
}

make_tool_entry "Nmap Network Scanner" "nmap" "network-wired"
make_tool_entry "SQLMap" "sqlmap" "utilities-terminal"
make_tool_entry "Hydra" "hydra" "utilities-terminal"
make_tool_entry "John The Ripper" "john" "utilities-terminal"
make_tool_entry "Nikto" "nikto" "utilities-terminal"
make_tool_entry "Wifite" "wifite" "network-wireless"

retro_ok "=== Lite modules setup complete. ==="
