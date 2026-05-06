#!/bin/bash
set -euo pipefail

# --- Constants ---
PERSISTENT_BASE="/data/custom"
PERSISTENT_NSPAWN_DIR="${PERSISTENT_BASE}/nspawn"
PERSISTENT_DPKG_DIR="${PERSISTENT_BASE}/dpkg"
PERSISTENT_META_DIR="${PERSISTENT_BASE}/twingate"
BOOT_SCRIPT_DIR="/data/on_boot.d"
NSPAWN_CONF_DIR="/etc/systemd/nspawn"

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Container name ---
DEFAULT_CONTAINER_NAME="twingate-connector"
if [[ -n "${CONTAINER_NAME:-}" ]]; then
    true
elif [[ -t 0 ]]; then
    echo ""
    echo "Existing containers on this host:"
    machinectl list --no-legend 2>/dev/null || echo "  (none)"
    echo ""
    if ls "${PERSISTENT_META_DIR}"/*.conf &>/dev/null; then
        echo "Known Twingate connector configs:"
        for f in "${PERSISTENT_META_DIR}"/*.conf; do
            echo "  $(basename "$f" .conf)"
        done
        echo ""
    fi
    read -rp "Enter the container name to uninstall [${DEFAULT_CONTAINER_NAME}]: " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
else
    CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
fi

if [[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Container name may only contain letters, numbers, hyphens, and underscores." >&2
    exit 1
fi

MACHINE_DIR="${PERSISTENT_BASE}/machines/${CONTAINER_NAME}"
MACHINES_LINK="/var/lib/machines/${CONTAINER_NAME}"
NSPAWN_CONF="${NSPAWN_CONF_DIR}/${CONTAINER_NAME}.nspawn"
PERSISTENT_NSPAWN_CONF="${PERSISTENT_NSPAWN_DIR}/${CONTAINER_NAME}.nspawn"
BOOT_SCRIPT="${BOOT_SCRIPT_DIR}/05-nspawn-${CONTAINER_NAME}.sh"
META_FILE="${PERSISTENT_META_DIR}/${CONTAINER_NAME}.conf"

echo "==> Uninstalling Twingate connector: ${CONTAINER_NAME}"

# --- Confirmation ---
if [[ -t 0 ]]; then
    echo ""
    echo "This will remove:"
    echo "  - Container filesystem: ${MACHINE_DIR}"
    echo "  - Boot script:          ${BOOT_SCRIPT}"
    echo "  - Cached packages:      ${PERSISTENT_DPKG_DIR}"
    echo "  - nspawn configs:       ${NSPAWN_CONF}"
    echo "                          ${PERSISTENT_NSPAWN_CONF}"
    echo "  - Metadata:             ${META_FILE}"
    echo ""
    read -rp "Continue? [y/N]: " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# --- Stop and disable container ---
if machinectl list --no-legend 2>/dev/null | grep -q "^${CONTAINER_NAME} "; then
    echo "==> Stopping container..."
    machinectl stop "$CONTAINER_NAME" 2>/dev/null || true
fi
machinectl disable "$CONTAINER_NAME" 2>/dev/null || true

# --- Remove boot script ---
echo "==> Removing boot script..."
rm -f "$BOOT_SCRIPT"

# --- Remove container filesystem ---
echo "==> Removing container filesystem..."
rm -rf "$MACHINE_DIR"

# --- Remove ephemeral paths ---
echo "==> Removing ephemeral paths..."
rm -f "$MACHINES_LINK"
rm -f "$NSPAWN_CONF"

# --- Remove persistent nspawn config ---
echo "==> Removing persistent nspawn config..."
rm -f "$PERSISTENT_NSPAWN_CONF"
rmdir "$PERSISTENT_NSPAWN_DIR" 2>/dev/null || true

# --- Remove cached packages ---
echo "==> Removing cached packages..."
rm -rf "$PERSISTENT_DPKG_DIR"

# --- Remove metadata ---
echo "==> Removing metadata..."
rm -f "$META_FILE"
rm -f "${PERSISTENT_META_DIR}/boot.log"
rm -f "${PERSISTENT_META_DIR}/boot.log.old"
rmdir "$PERSISTENT_META_DIR" 2>/dev/null || true

echo ""
echo "Twingate connector '${CONTAINER_NAME}' has been completely removed."
echo "Note: udm-boot.service (unifi-common) was left in place."
