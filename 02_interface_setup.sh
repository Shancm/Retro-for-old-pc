#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"
require_root

trap 'retro_error "02_interface_setup.sh failed at line ${LINENO}."' ERR

retro_info "Configuring Retro OS Desktop Interface & Native Desktop Controls..."
export DEBIAN_FRONTEND=noninteractive

SKEL_DIR="/etc/skel"
mkdir -p "${SKEL_DIR}/.config/openbox"
mkdir -p "${SKEL_DIR}/.config/tint2"
mkdir -p "${SKEL_DIR}/.config/kitty"
mkdir -p "${SKEL_DIR}/.config/picom"
mkdir -p "${SKEL_DIR}/.config/pcmanfm/default"
mkdir -p "${SKEL_DIR}/Desktop"
mkdir -p /usr/share/applications

# 1. ടൈംസോൺ ഡിഫോൾട്ടായി ഇന്ത്യയിലേക്ക് ക്രമീകരിക്കുന്നു
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
echo "Asia/Kolkata" > /etc/timezone

# 2. LightDM ഓട്ടോലോഗിൻ
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/autologin.conf
[Seat:*]
autologin-user=retro
autologin-user-timeout=0
user-session=openbox
EOF
systemctl set-default graphical.target >/dev/null 2>&1 || true

# 3. PCManFM ഡെസ്ക്ടോപ്പ് കോൺഫിഗറേഷൻ (Right-Click Context Menu, Wallpaper, Desktop Icons)
cat << 'EOF' > "${SKEL_DIR}/.config/pcmanfm/default/desktop-items-0.conf"
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

# 4. ഓപ്പൺബോക്സ് ആക്‌ഷൻ & കീബോർഡ് ക്രമീകരണങ്ങൾ (rc.xml)
cat << 'EOF' > "${SKEL_DIR}/.config/openbox/rc.xml"
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <keyboard>
    <keybind key="W-Return"><action name="Execute"><command>kitty</command></action></keybind>
    <keybind key="W-space"><action name="Execute"><command>rofi -show drun -theme-str 'window {width: 400px; border: 2px; border-color: #00FF9C; background-color: #0D0F12; font: "JetBrains Mono 10";}'</command></action></keybind>
    <keybind key="W-e"><action name="Execute"><command>pcmanfm</command></action></keybind>
  </keyboard>
  <mouse>
    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
  </mouse>
</openbox_config>
EOF

# 5. ഓപ്പൺബോക്സ് ആപ്പ് മെനു (menu.xml)
cat << 'EOF' > "${SKEL_DIR}/.config/openbox/menu.xml"
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
    <item label="Reconfigure Openbox"><action name="Reconfigure" /></item>
    <item label="Exit"><action name="Exit" /></item>
  </menu>
</openbox_menu>
EOF

# 6. ഓട്ടോസ്റ്റാർട്ട് സ്ക്രിപ്റ്റ് (autostart)
cat << 'EOF' > "${SKEL_DIR}/.config/openbox/autostart"
# 1. കോമ്പോസിറ്റർ, വോളിയം, നെറ്റ്‌വർക്ക്
picom -b &
nm-applet &
volumeicon &

# 2. ടാസ്ക്ബാർ
tint2 &

# 3. നേറ്റീവ് ഡെസ്ക്ടോപ്പ് (Right-click menu, Copy/Paste, Icons, Wallpaper)
pcmanfm --desktop &
EOF

# 7. ടാസ്ക്ബാർ പാനൽ (Tint2)
cat << 'EOF' > "${SKEL_DIR}/.config/tint2/tint2rc"
panel_position = bottom center horizontal
panel_size = 100% 32
panel_margin = 0 0
panel_padding = 4 2 4
panel_background_id = 1
font = JetBrains Mono 10
task_active_background_id = 2
clock_font_color = #00FF9C
background_color = #0D0F12 90
border_color = #00FF9C 40
time1_format = %H:%M:%S | %A %d %b
EOF

# 8. Kitty ടെർമിനൽ
cat << 'EOF' > "${SKEL_DIR}/.config/kitty/kitty.conf"
font_family      JetBrains Mono
font_size        11.0
background_opacity 0.85
background_image /usr/share/backgrounds/retro-os/term_bg.png
background_image_layout cscaled
copy_on_select yes
map ctrl+c copy_to_clipboard
map ctrl+v paste_from_clipboard
EOF

# 9. സെക്യൂരിറ്റി ടൂളുകൾക്കുള്ള .desktop ഫയലുകൾ നിർമ്മിക്കുന്നു
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

# 10. ഡെസ്ക്ടോപ്പിലേക്ക് പ്രധാനപ്പെട്ട ആപ്പുകളുടെ ഷോർട്ട്കട്ടുകൾ നൽകുന്നു
cp -a /usr/share/applications/firefox-esr.desktop "${SKEL_DIR}/Desktop/" 2>/dev/null || true
cp -a /usr/share/applications/brave-browser.desktop "${SKEL_DIR}/Desktop/" 2>/dev/null || true
cp -a /usr/share/applications/pcmanfm.desktop "${SKEL_DIR}/Desktop/" 2>/dev/null || true
chmod +x "${SKEL_DIR}/Desktop/"*.desktop 2>/dev/null || true

# 11. യൂസർ പെർമിഷനുകൾ സജ്ജമാക്കുന്നു
if [[ -d "${SKEL_DIR}" ]]; then
    chmod -R u=rwX,go=rX "${SKEL_DIR}" 2>/dev/null || true
fi

# -------------------------------------------------------------------------
# Windows 7 Style Start Menu + Direct Right-Click Menu Setup
# -------------------------------------------------------------------------

# 1. പാക്കേജുകൾ ഇൻസ്റ്റാൾ ചെയ്യുന്നു (jgmenu വിൻഡോസ് 7 ശൈലിയിലുള്ള മെനു നൽകും)
apt-get install -y -qq jgmenu xfce4-terminal papirus-icon-theme || true

# 2. PCManFM Right-Click ഓപ്പൺബോക്സ് മെനുവിലേക്ക് മാറ്റുന്നു
# (ഡെസ്ക്ടോപ്പിൽ സാധാരണ റൈറ്റ്-ക്ലിക്ക് ചെയ്യുമ്പോൾ തന്നെ Retro മെനു വരും)
mkdir -p "${SKEL_DIR}/.config/pcmanfm/default"
cat << 'EOF' > "${SKEL_DIR}/.config/pcmanfm/default/desktop-items-0.conf"
[*]
wallpaper_mode=stretch
wallpaper=/usr/share/backgrounds/retro-os/wallpaper.png
desktop_bg=#000000
desktop_fg=#ffffff
desktop_shadow=#000000
desktop_font=Sans 10
show_wm_menu=1
sort_by=2
sort_type=0
set_wallpaper_all=1
show_documents=0
show_trash=1
show_mounts=1
EOF

# 3. Windows 7 Style Tint2 Launcher Config
mkdir -p "${SKEL_DIR}/.config/tint2"
cat << 'EOF' > "${SKEL_DIR}/.config/tint2/tint2rc"
# Tint2 Panel with Win7 Start Button
panel_items = LTS
panel_position = bottom center horizontal
panel_size = 100% 36
panel_margin = 0 0
panel_padding = 4 2 4
panel_background_id = 1
wm_menu = 1

# Start Button (Launcher)
launcher_padding = 4 2
launcher_background_id = 0
launcher_icon_size = 28
launcher_item_app = /usr/share/applications/start-menu.desktop

# Taskbar & System Tray
taskbar_mode = single_desktop
taskbar_padding = 2 2 2
taskbar_background_id = 0
taskbar_active_background_id = 2
systray_padding = 4 2 4
clock_font_color = #ffffff 100
time1_format = %I:%M %p
time2_format = %A %d %B

# Background styles
rounded = 0
border_width = 1
border_color = #222222 100
background_color = #111111 90

rounded = 2
border_width = 1
border_color = #00aaff 100
background_color = #005588 80
EOF

# 4. Start Button Desktop Launcher ഉണ്ടാക്കുന്നു
cat << 'EOF' > /usr/share/applications/start-menu.desktop
[Desktop Entry]
Name=Start Menu
Comment=Windows 7 Style Application Menu
Exec=jgmenu_run || xdotool key super+space
Icon=distributor-logo-debian
Terminal=false
Type=Application
Categories=System;
EOF

# 5. റൈറ്റ്-ക്ലിക്ക് കോപ്പി പേസ്റ്റ് ഉള്ള ടെർമിനൽ ഡിഫോൾട്ട് ആക്കുന്നു
update-alternatives --set x-terminal-emulator /usr/bin/xfce4-terminal 2>/dev/null || true

retro_ok "=== Full-fledged Retro OS Desktop Environment configured successfully. ==="
