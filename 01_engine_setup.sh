#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - 01_engine_setup.sh
# Kernel/system engine layer: ZRAM, EarlyOOM, sysctl tuning, Btrfs/Snapper.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

require_root

trap 'retro_error "01_engine_setup.sh failed at line ${LINENO} (exit ${?})."' ERR

retro_info "=== [1/3] Engine Setup: ZRAM / EarlyOOM / sysctl / Btrfs-Snapper ==="

# -----------------------------------------------------------------------------
# 1. Package prerequisites
# -----------------------------------------------------------------------------
retro_info "Installing engine dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    zram-tools \
    earlyoom \
    util-linux \
    procps \
    firmware-linux \
    firmware-linux-nonfree \
    firmware-misc-nonfree >/dev/null

retro_ok "Base engine packages installed."

# -----------------------------------------------------------------------------
# 2. ZRAM with ZSTD compression, sized to 50% of RAM (idempotent)
# -----------------------------------------------------------------------------
retro_info "Configuring ZRAM (zstd, 50% RAM)..."

ZRAM_CONF="/etc/default/zramswap"
if [[ -f "${ZRAM_CONF}" ]]; then
    cp -a "${ZRAM_CONF}" "${ZRAM_CONF}.bak.$(date +%s)" 2>/dev/null || true
fi

cat > "${ZRAM_CONF}" << 'ZCONF'
# Managed by Retro OS - 01_engine_setup.sh
ALGO=zstd
ALGORITHM=zstd
PERCENT=100
PERCENTAGE=100
PRIORITY=100
ZCONF

# Chroot-safe service enablement:
if is_command systemctl; then
    systemctl enable zramswap.service >/dev/null 2>&1 || true
    
    # Check if booted under active systemd and not inside a chroot
    if [[ -d /run/systemd/system ]] && ! systemd-detect-virt --chroot >/dev/null 2>&1; then
        systemctl start zramswap.service >/dev/null 2>&1 || true
    else
        retro_info "Chroot build detected: zramswap enabled and will initialize on first boot."
    fi
else
    retro_warn "systemctl not available; zramswap will activate on first real boot."
fi

retro_ok "ZRAM configured."

# -----------------------------------------------------------------------------
# 3. EarlyOOM anti-freeze daemon (idempotent config)
# -----------------------------------------------------------------------------
retro_info "Configuring EarlyOOM anti-freeze daemon..."

EARLYOOM_CONF="/etc/default/earlyoom"
if [[ -f "${EARLYOOM_CONF}" ]]; then
    cp -a "${EARLYOOM_CONF}" "${EARLYOOM_CONF}.bak.$(date +%s)" 2>/dev/null || true
fi

cat > "${EARLYOOM_CONF}" << 'EOOM'
# Managed by Retro OS - 01_engine_setup.sh
# Kill the biggest offending process before the system fully freezes.
EARLYOOM_ARGS="-r 60 -m 8 -s 8 --avoid '(^|/)(sshd|systemd|dbus-daemon|Xorg|kwin_wayland|plasmashell|gnome-shell|pipewire)$' -g"
EOOM

# Chroot-safe service enablement
if is_command systemctl; then
    systemctl enable earlyoom.service >/dev/null 2>&1 || true

    if [[ -d /run/systemd/system ]] && ! systemd-detect-virt --chroot >/dev/null 2>&1; then
        systemctl start earlyoom.service >/dev/null 2>&1 || true
    else
        retro_info "Chroot build detected: earlyoom enabled and will initialize on first boot."
    fi
else
    retro_warn "systemctl not available; earlyoom will activate on first real boot."
fi

retro_ok "EarlyOOM configured."

# -----------------------------------------------------------------------------
# 4. Low-latency sysctl performance tweaks (idempotent - single managed block)
# -----------------------------------------------------------------------------
retro_info "Applying low-latency sysctl tweaks..."

# 1. Ensure BBR and Fair Queueing modules load on boot
mkdir -p /etc/modules-load.d
cat > /etc/modules-load.d/bbr.conf << 'EOF'
tcp_bbr
sch_fq
EOF

# Load them live if on a running kernel (skip failures inside chroot)
modprobe tcp_bbr 2>/dev/null || true
modprobe sch_fq 2>/dev/null || true

# 2. Write sysctl parameters
SYSCTL_FILE="/etc/sysctl.d/99-retro-os-performance.conf"
cat > "${SYSCTL_FILE}" << 'SYSCTL'
# Managed by Retro OS - 01_engine_setup.sh
# Low-latency / desktop-responsiveness tuning

# Increase swappiness to aggressively prioritize ZRAM over RAM exhaustion
vm.swappiness=100
vm.page-cluster=0
vm.vfs_cache_pressure=50

# Reduce write-back latency spikes on desktop/storage
vm.dirty_ratio=10
vm.dirty_background_ratio=5

# Scheduler responsiveness (autogroup helps desktop interactivity)
kernel.sched_autogroup_enabled=1

# Network snappiness and bufferbloat mitigation (BBR + FQ)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
SYSCTL

# Apply live only if running on a real booted host (skip in chroot)
if is_command sysctl; then
    if [[ -d /run/systemd/system ]] && ! systemd-detect-virt --chroot >/dev/null 2>&1; then
        sysctl --system >/dev/null 2>&1 || retro_warn "Failed to apply sysctl parameters live."
    else
        retro_info "Chroot detected: sysctl settings written and will apply automatically on first boot."
    fi
fi

retro_ok "sysctl tuning written to ${SYSCTL_FILE}."

# -----------------------------------------------------------------------------
# 5. Btrfs + Snapper rollback support (GUARDED - packages always baked in)
# -----------------------------------------------------------------------------
retro_info "Installing Btrfs and Snapper tools into base image..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq snapper btrfs-progs grub-btrfs inotify-tools >/dev/null

retro_info "Checking root filesystem type for Snapper configuration..."

if is_btrfs_root; then
    retro_ok "Root filesystem is Btrfs - configuring Snapper rollback support."

        if [[ ! -e /etc/snapper/configs/root ]]; then
        umount /.snapshots 2>/dev/null || true
        rm -rf /.snapshots 2>/dev/null || true
        if snapper -c root create-config / 2>/dev/null; then
            retro_ok "Snapper 'root' config created."
        else
            retro_warn "Snapper create-config skipped (already configured or unsupported layout)."
        fi
    else
        retro_info "Snapper 'root' config already exists - skipping."
    fi

    if [[ -f /etc/snapper/configs/root ]]; then
        sed -i \
            -e 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="yes"/' \
            -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' \
            -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
            -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' \
            -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' \
            /etc/snapper/configs/root 2>/dev/null || true
    fi

    # Chroot-safe timer enablement
    if is_command systemctl; then
        systemctl enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service >/dev/null 2>&1 || true

        if [[ -d /run/systemd/system ]] && ! systemd-detect-virt --chroot >/dev/null 2>&1; then
            systemctl start snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service >/dev/null 2>&1 || true
        else
            retro_info "Chroot build detected: Snapper timers enabled and will initialize on first boot."
        fi
    fi

    if is_command update-grub && dpkg-query -W -f='${Status}' grub-btrfs 2>/dev/null | grep -q "install ok installed"; then
        update-grub >/dev/null 2>&1 || retro_warn "update-grub failed (normal in a chroot build)."
    fi

    retro_ok "Btrfs/Snapper rollback support configured."
else
    retro_warn "Root filesystem is NOT Btrfs at build time - packages installed successfully; setup deferred to runtime."
fi

# -----------------------------------------------------------------------------
# 6. Update system-wide OS identity and dynamic version (/etc/os-release)
# -----------------------------------------------------------------------------
retro_info "Writing system identity to /etc/os-release..."

TARGET_OS_RELEASE="/usr/lib/os-release"
[[ ! -d /usr/lib ]] && TARGET_OS_RELEASE="/etc/os-release"

cat > "${TARGET_OS_RELEASE}" << OSREL
NAME="${RETRO_OS_NAME}"
VERSION="${RETRO_OS_VERSION}"
ID=retro-os
ID_LIKE="ubuntu debian"
PRETTY_NAME="${RETRO_OS_NAME} v${RETRO_OS_VERSION}"
VERSION_ID="${RETRO_OS_VERSION}"
HOME_URL="https://github.com/Shancm/retro-os"
SUPPORT_URL="https://github.com/Shancm/retro-os/issues"
BUG_REPORT_URL="https://github.com/Shancm/retro-os/issues"
OSREL

if [[ "${TARGET_OS_RELEASE}" == "/usr/lib/os-release" ]]; then
    ln -sfn /usr/lib/os-release /etc/os-release
fi

echo -e "${RETRO_OS_NAME} v${RETRO_OS_VERSION} \\n \\l" > /etc/issue
echo "${RETRO_OS_NAME} v${RETRO_OS_VERSION}" > /etc/issue.net

retro_ok "System identity updated with version ${RETRO_OS_VERSION}."

retro_ok "=== Engine setup complete. ==="
