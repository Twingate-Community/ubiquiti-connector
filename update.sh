#!/bin/bash
set -euo pipefail

# --- Constants ---
PERSISTENT_DPKG_DIR="/data/custom/dpkg"

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# --- Helper: run a command inside the running container via nsenter ---
container_exec() {
    local pid
    pid=$(machinectl show "$CONTAINER_NAME" -p Leader --value)
    nsenter -t "$pid" -m -u -i -n -p -- "$@"
}

# --- Container name ---
DEFAULT_CONTAINER_NAME="twingate-connector"
if [[ -n "${CONTAINER_NAME:-}" ]]; then
    true
elif [[ -t 0 ]]; then
    echo ""
    echo "Existing containers on this host:"
    machinectl list --no-legend 2>/dev/null || echo "  (none)"
    echo ""
    read -rp "Enter the container name to update [${DEFAULT_CONTAINER_NAME}]: " CONTAINER_NAME
    CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
else
    CONTAINER_NAME="$DEFAULT_CONTAINER_NAME"
fi

if [[ ! "$CONTAINER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Container name may only contain letters, numbers, hyphens, and underscores." >&2
    exit 1
fi

# --- Verify container is running ---
if ! machinectl list --no-legend 2>/dev/null | grep -q "^${CONTAINER_NAME} "; then
    echo "Error: Container '${CONTAINER_NAME}' is not running." >&2
    echo "Start it with: machinectl start ${CONTAINER_NAME}" >&2
    exit 1
fi

echo "==> Updating container: ${CONTAINER_NAME}"

# --- Current version ---
echo "==> Current Twingate connector version:"
container_exec twingate-connector --version 2>/dev/null || echo "  (unknown)"

# --- Update container packages ---
echo "==> Updating packages inside container..."
container_exec /bin/bash -c "\
    export DEBIAN_FRONTEND=noninteractive && \
    apt-get update -qq && \
    apt-get dist-upgrade -y -qq"

# --- Restart connector ---
echo "==> Restarting Twingate connector..."
container_exec systemctl restart twingate-connector

sleep 3
if container_exec systemctl is-active twingate-connector &>/dev/null; then
    echo "==> Twingate connector is running."
else
    echo "Warning: Twingate connector may not have started correctly."
    container_exec systemctl status twingate-connector --no-pager || true
fi

# --- New version ---
echo "==> Updated Twingate connector version:"
container_exec twingate-connector --version 2>/dev/null || echo "  (unknown)"

# --- Refresh host package cache ---
echo "==> Refreshing host package cache..."
apt-get update -qq
apt-get install -y -qq systemd-container debootstrap
mkdir -p "$PERSISTENT_DPKG_DIR"
cp /var/cache/apt/archives/*.deb "$PERSISTENT_DPKG_DIR/" 2>/dev/null || true

echo ""
echo "Update complete."
