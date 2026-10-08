#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/config.env"
require_root

trap 'retro_error "02_interface_setup.sh failed at line ${LINENO}."' ERR

retro_info "Configuring Retro OS Ultra-Lite BIOS GUI..."
export DEBIAN_FRONTEND=noninteractive

# 1. ആവശ്യമായ ടൂളുകൾ ഇൻസ്റ്റാൾ ചെയ്യൽ
apt-get update -qq
apt-get install -y -qq openbox tint2 rofi feh picom lightdm lightdm-gtk-greeter kitty fonts-jetbrains-mono papirus-icon-theme >/dev/null

# 2. LightDM ഓട്ടോലോഗിൻ സെറ്റപ്പ്
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/autologin.conf
[Seat:*]
autologin-user=retro
autologin-user-timeout=0
user-session=openbox
EOF

systemctl set-default graphical.target >/dev/null 2>&1 || true
if is_command systemctl; then
    systemctl enable lightdm.service >/dev/null 2>&1 || true
fi

# 3. വിഷ്വൽ എഫക്റ്റുകൾക്കായി Picom കോമ്പോസിറ്റർ
mkdir -p "${SKEL_DIR}/.config/picom"
cat << 'EOF' > "${SKEL_DIR}/.config/picom/picom.conf"
backend = "xrender";
fading = true;
fade-delta = 4;
corner-radius = 6;
inactive-opacity = 0.90;
active-opacity = 0.98;
EOF

# 4. ടാസ്ക്ബാർ പാനൽ (Tint2)
mkdir -p "${SKEL_DIR}/.config/tint2"
cat << 'EOF' > "${SKEL_DIR}/.config/tint2/tint2rc"
panel_position = bottom center horizontal
panel_size = 100% 32
panel_margin = 0 0
panel_padding = 4 2 4
panel_background_id = 1
font = JetBrainsMono Nerd Font 10
task_active_background_id = 2
clock_font_color = #00FF9C
background_color = #0D0F12 90
border_color = #00FF9C 40
EOF

# 5. ഓട്ടോസ്റ്റാർട്ട് സെറ്റിംഗ്സ്
mkdir -p "${SKEL_DIR}/.config/openbox"
cat << 'EOF' > "${SKEL_DIR}/.config/openbox/autostart"
feh --bg-color "#0D0F12" &
picom -b &
tint2 &
EOF

# 6. ഷോർട്ട്കട്ടുകൾ
cat << 'EOF' > "${SKEL_DIR}/.config/openbox/rc.xml"
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <keyboard>
    <keybind key="W-Return">
      <action name="Execute"><command>kitty</command></action>
    </keybind>
    <keybind key="W-space">
      <action name="Execute"><command>rofi -show drun -theme-str 'window {width: 400px; border: 2px; border-color: #00FF9C; background-color: #0D0F12; font: "JetBrainsMono Nerd Font 10";}'</command></action>
    </keybind>
  </keyboard>
</openbox_config>
EOF

# 7. യൂസർ പെർമിഷനുകൾ ശരിയാക്കൽ
if [[ -d "${SKEL_DIR}" ]]; then
    chmod -R u=rwX,go=rX "${SKEL_DIR}" 2>/dev/null || true
fi

retro_ok "=== Aesthetic Ultra-Lite GUI setup complete (RAM: ~120MB). ==="
