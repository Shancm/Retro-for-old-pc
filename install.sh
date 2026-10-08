#!/usr/bin/env bash
# =============================================================================
# Retro OS v1.0 - install.sh
# Master orchestrator: runs 01 -> 02 -> 03 -> setup_calamares, then installs
# the `retro` CLI to /usr/local/bin/retro and the project to /opt/retro-os.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./config.env
source "${SCRIPT_DIR}/config.env"

require_root

trap 'retro_error "install.sh aborted at line ${LINENO} (exit ${?}). See ${RETRO_LOG_FILE} for details."' ERR

retro_info "======================================================"
retro_info " ${RETRO_OS_NAME} v${RETRO_OS_VERSION} - Master Installer"
retro_info "======================================================"
retro_info "TARGET_USER=${TARGET_USER}  TARGET_HOME=${TARGET_HOME}"

STEPS=(
    "01_engine_setup.sh"
    "02_interface_setup.sh"
    "03_modules_setup.sh"
    "setup_calamares.sh"
)

for step in "${STEPS[@]}"; do
    step_path="${SCRIPT_DIR}/${step}"
    if [[ ! -f "${step_path}" ]]; then
        retro_die "Missing required script: ${step_path}"
    fi
    if [[ ! -x "${step_path}" ]]; then
        chmod +x "${step_path}"
    fi
    retro_info "------------------------------------------------------"
    retro_info "Running ${step} ..."
    retro_info "------------------------------------------------------"
    "${step_path}"
    retro_ok "${step} finished successfully."
done

# -----------------------------------------------------------------------------
# Install the project itself to /opt/retro-os (so `retro` can source
# config.env at runtime even outside the build environment)
# -----------------------------------------------------------------------------
retro_info "Installing project files to ${RETRO_ROOT} ..."
mkdir -p "${RETRO_ROOT}"
cp -a "${SCRIPT_DIR}/." "${RETRO_ROOT}/" 2>/dev/null || true
chmod +x "${RETRO_ROOT}"/*.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# Install the retro CLI
# -----------------------------------------------------------------------------
retro_info "Installing retro CLI to ${RETRO_BIN_DIR}/retro ..."
if [[ -f "${SCRIPT_DIR}/retro" ]]; then
    install -m 0755 "${SCRIPT_DIR}/retro" "${RETRO_BIN_DIR}/retro"
    retro_ok "retro CLI installed at ${RETRO_BIN_DIR}/retro"
else
    retro_die "retro CLI source file not found next to install.sh."
fi

retro_ok "======================================================"
retro_ok " ${RETRO_OS_NAME} installation complete."
retro_ok " Try:  retro help"
retro_ok "======================================================"
