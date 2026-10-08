#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - 02_interface_setup.sh
# Minimal KDE Plasma (Wayland) desktop, Kitty, fonts, icons, keybindings.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/config.env"
require_root

export DEBIAN_FRONTEND=noninteractive

retro_info "Configuring Retro OS Ultra-Lite BIOS GUI..."

# 1. LightDM ഡിസ്‌പ്ലേ മാനേജർ ഓട്ടോലോഗിൻ സെറ്റപ്പ്
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'EOF' > /etc/lightdm/lightdm.conf.d/autologin.conf
[Seat:*]
autologin-user=retro
autologin-user-timeout=0
user-session=openbox
EOF

systemctl set-default graphical.target >/dev/null 2>&1 || true

# 2. കിടിലൻ വിഷ്വൽ എഫക്റ്റുകൾക്കായി Picom കോമ്പോസിറ്റർ കോൺഫിഗറേഷൻ
mkdir -p "${SKEL_DIR}/.config/picom"
cat << 'EOF' > "${SKEL_DIR}/.config/picom/picom.conf"
backend = "xrender";
fading = true;
fade-delta = 4;
corner-radius = 6;
inactive-opacity = 0.90;
active-opacity = 0.98;
EOF

# 3. ടാസ്ക്ബാർ (Tint2 Cyber Panel)
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

# 4. ഓട്ടോസ്റ്റാർട്ട് സെറ്റിംഗ്സ്
mkdir -p "${SKEL_DIR}/.config/openbox"
cat << 'EOF' > "${SKEL_DIR}/.config/openbox/autostart"
feh --bg-color "#0D0F12" &
picom -b &
tint2 &
EOF

# 5. ഷോർട്ട്കട്ടുകൾ (Super+Return അടിച്ചാൽ Kitty, Super+Space അടിച്ചാൽ അടിപൊളി Rofi മെനു)
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

if [[ -d "${SKEL_DIR}" ]]; then
    chmod -R u=rwX,go=rX "${SKEL_DIR}" 2>/dev/null || true
fi

retro_ok "Aesthetic Ultra-Lite GUI setup complete (RAM: ~120MB)."

# -----------------------------------------------------------------------------
# 1. Minimal KDE Plasma (Wayland) + KWin + SDDM
# -----------------------------------------------------------------------------
retro_info "Installing minimal KDE Plasma (Wayland session)..."
apt-get update -qq
apt-get install -y -qq \
    plasma-desktop \
    plasma-workspace-wayland \
    kwin-wayland \
    sddm \
    sddm-theme-breeze \
    konsole \
    dolphin \
    plasma-nm \
    kscreen \
    fonts-noto \
    firefox \
    ubuntu-drivers-common \
    linux-firmware >/dev/null

systemctl set-default graphical.target >/dev/null 2>&1 || true
if is_command systemctl; then
    systemctl enable sddm.service >/dev/null 2>&1 || true
fi

retro_ok "KDE Plasma (Wayland) + SDDM installed."

# -----------------------------------------------------------------------------
# 2. Kitty terminal, JetBrains Mono, Papirus icons
# -----------------------------------------------------------------------------
retro_info "Installing Kitty, JetBrains Mono Nerd Font, Papirus icons..."
apt-get install -y -qq \
    kitty \
    fonts-jetbrains-mono \
    papirus-icon-theme \
    fontconfig \
    >/dev/null

fc-cache -f >/dev/null 2>&1 || true

retro_ok "Kitty / fonts / icons installed."

# -----------------------------------------------------------------------------
# 3. Deploy configs to BOTH /etc/skel (future users) AND $TARGET_HOME
# -----------------------------------------------------------------------------
deploy_config() {
    local rel_path="$1"
    local skel_target="${SKEL_DIR}/${rel_path}"
    local user_target="${TARGET_HOME}/${rel_path}"

    mkdir -p "$(dirname "${skel_target}")"
    cat > "${skel_target}"

    mkdir -p "$(dirname "${user_target}")"
    cp -a "${skel_target}" "${user_target}"

    # Assign immediate ownership to the specific file
    if [[ "${EUID}" -eq 0 && "${TARGET_USER}" != "root" ]] && id "${TARGET_USER}" &>/dev/null; then
        chown "${TARGET_USER}:${TARGET_USER}" "${user_target}" 2>/dev/null || true
    fi
}

retro_info "Deploying Kitty dark theme to /etc/skel and ${TARGET_HOME}..."

deploy_config ".config/kitty/kitty.conf" << KITTYCONF
# Retro OS default Kitty configuration
font_family      ${RETRO_FONT_NAME}
font_size        12.0
background       ${RETRO_BG_COLOR}
foreground       ${RETRO_FG_COLOR}
cursor           ${RETRO_ACCENT_COLOR}
selection_background ${RETRO_ACCENT_COLOR}
background_opacity 0.92
confirm_os_window_close 0

# Retro OS palette
color0  #0D0F12
color8  #4D4D4D
color1  #FF5555
color9  #FF6E6E
color2  #00FF9C
color10 #5CFFC1
color3  #F1FA8C
color11 #FFFFA5
color4  #6272A4
color12 #82AAFF
color5  #BD93F9
color13 #D6ACFF
color6  #8BE9FD
color14 #A4FFFF
color7  #E0E0E0
color15 #FFFFFF
KITTYCONF

retro_ok "Kitty theme deployed."

# -----------------------------------------------------------------------------
# 4. System-wide keybindings via KGlobalShortcuts
# -----------------------------------------------------------------------------
retro_info "Deploying system-wide keybindings..."

deploy_config ".config/kglobalshortcutsrc" << 'KEYBINDS'
[kwin]
RetroTerm=Meta+Return,none,Launch Retro Terminal
RetroMon=Meta+M,none,Launch Retro System Monitor
RetroKali=Meta+K,none,Launch Retro Kali Container
KEYBINDS

deploy_config ".local/share/applications/retro-term.desktop" << DESK1
[Desktop Entry]
Type=Application
Name=Retro Terminal
Exec=/usr/local/bin/retro term
Icon=utilities-terminal
Terminal=false
NoDisplay=false
X-KDE-GlobalShortcut=Meta+Return
DESK1

deploy_config ".local/share/applications/retro-mon.desktop" << DESK2
[Desktop Entry]
Type=Application
Name=Retro Monitor
Exec=/usr/local/bin/retro mon
Icon=utilities-system-monitor
Terminal=false
NoDisplay=false
X-KDE-GlobalShortcut=Meta+M
DESK2

deploy_config ".local/share/applications/retro-kali.desktop" << DESK3
[Desktop Entry]
Type=Application
Name=Retro Kali
Exec=/usr/local/bin/retro kali
Icon=utilities-terminal
Terminal=false
NoDisplay=false
X-KDE-GlobalShortcut=Meta+K
DESK3

# Refresh Desktop App Database
if is_command update-desktop-database; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    if [[ -d "${TARGET_HOME}/.local/share/applications" ]]; then
        update-desktop-database "${TARGET_HOME}/.local/share/applications" >/dev/null 2>&1 || true
    fi
fi

# Refresh KDE Sycoca application cache cleanly if running live as target user
if [[ "${TARGET_USER}" != "root" ]] && id "${TARGET_USER}" &>/dev/null; then
    if is_command kbuildsycoca6; then
        su - "${TARGET_USER}" -c "kbuildsycoca6 --noincremental" >/dev/null 2>&1 || true
    elif is_command kbuildsycoca5; then
        su - "${TARGET_USER}" -c "kbuildsycoca5 --noincremental" >/dev/null 2>&1 || true
    fi
fi

retro_ok "Keybindings and launchers deployed."

# -----------------------------------------------------------------------------
# 5. Default look-and-feel
# -----------------------------------------------------------------------------
retro_info "Deploying Plasma theme defaults..."

deploy_config ".config/kdeglobals" << KDEG
[General]
ColorScheme=BreezeDark
Name=BreezeDark
widgetStyle=Breeze

[Icons]
Theme=${RETRO_ICON_THEME}

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
SingleClick=false
KDEG

retro_ok "Plasma theme defaults deployed."

# -----------------------------------------------------------------------------
# 6. Default terminal emulator & permissions
# -----------------------------------------------------------------------------
retro_info "Setting Kitty as default system terminal..."
if is_command update-alternatives && is_command kitty; then
    update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/kitty 50 >/dev/null 2>&1 || true
    update-alternatives --set x-terminal-emulator /usr/bin/kitty >/dev/null 2>&1 || true
fi

if [[ -n "${TARGET_HOME:-}" && -d "${TARGET_HOME}" ]]; then
    mkdir -p "${TARGET_HOME}/.config" "${SKEL_DIR}/.config"
    for target in "${TARGET_HOME}/.config/kdeglobals" "${SKEL_DIR}/.config/kdeglobals"; do
        if [[ -f "${target}" ]]; then
            sed -i '/^\[General\]/a TerminalApplication=kitty\nTerminalService=kitty.desktop' "${target}" 2>/dev/null || true
        else
            cat >> "${target}" << 'KDECONF'
[General]
TerminalApplication=kitty
TerminalService=kitty.desktop
KDECONF
        fi
    done
fi

# Ensure standard readable permissions for future users in skeleton
if [[ -d "${SKEL_DIR}" ]]; then
    chmod -R u=rwX,go=rX "${SKEL_DIR}" 2>/dev/null || true
fi

# Final single-pass recursive ownership fix for the target user directory
if [[ "${EUID}" -eq 0 && -n "${TARGET_USER:-}" && "${TARGET_USER}" != "root" ]] && id "${TARGET_USER}" &>/dev/null; then
    if [[ -d "${TARGET_HOME}/.config" ]]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" 2>/dev/null || true
    fi
    if [[ -d "${TARGET_HOME}/.local" ]]; then
        chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" 2>/dev/null || true
    fi
fi

retro_info "Configuring hardware and audio permissions for user..."
USERS_TO_CONFIGURE=()
[[ -n "${TARGET_USER:-}" && "${TARGET_USER}" != "root" ]] && USERS_TO_CONFIGURE+=("${TARGET_USER}")
[[ "${TARGET_USER}" != "retro" ]] && USERS_TO_CONFIGURE+=("retro")

TARGET_GROUPS=(sudo video audio input render netdev plugdev)

for u in "${USERS_TO_CONFIGURE[@]}"; do
    if id "${u}" &>/dev/null; then
        for grp in "${TARGET_GROUPS[@]}"; do
            if getent group "${grp}" &>/dev/null; then
                usermod -aG "${grp}" "${u}" 2>/dev/null || true
            fi
        done
        retro_ok "Configured permissions and groups for user: ${u}"
    fi
done

retro_info "Configuring secure sudo permissions for live session..."
# Eliminates passwordless full root access.
rm -f /etc/sudoers.d/retro-live 2>/dev/null || true
retro_ok "Live user secure sudo configured."

retro_ok "=== Interface setup complete. ==="
