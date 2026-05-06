# Twingate Connector for Ubiquiti Gateways

Deploy a [Twingate](https://www.twingate.com/) Connector on Ubiquiti Gateway devices using a lightweight systemd-nspawn container.

## Overview

Ubiquiti gateways (UDM Pro, UDM SE, UXG-Pro, UXG-Max, etc.) run a customized Linux environment that doesn't include a native container runtime. This project uses **systemd-nspawn** to bootstrap a minimal Debian container directly on the gateway, install the Twingate Connector inside it, and configure it to start automatically on boot.

The container filesystem is stored under `/data/custom/machines/`, which persists across UniFi OS firmware upgrades. A boot hook ensures the container is automatically restored and started after firmware updates.

## Features

- **Automated setup** -- single script handles everything from container creation to Connector installation
- **Survives firmware updates** -- boot hook automatically restores container configuration after UniFi OS upgrades
- **Persistent across reboots** -- container data lives on the gateway's persistent `/data` partition
- **Auto-start on boot** -- container starts automatically via the unifi-common boot service
- **Automatic updates (opt-in)** -- optionally enable unattended-upgrades to keep Debian and the Twingate Connector up to date
- **Offline recovery** -- cached host packages allow boot restoration without internet access
- **Host networking** -- no NAT, the Connector has full LAN access
- **Kernel compatibility** -- includes a fix for gateways without user namespace support
- **Flexible credentials** -- pass tokens via environment variables or enter them interactively
- **Retrofit support** -- can add boot persistence to containers deployed with older versions of this script

## Prerequisites

- A **Ubiquiti Gateway** (UDM Pro, UDM SE, UXG-Pro, UXG-Max, or similar) running UniFi OS 3.x or later
- **SSH access** to the gateway as root
- A **Twingate account** with access to the Admin Console
- **Internet connectivity** on the Gateway (for downloading packages and Twingate binaries)

### Generating Connector Tokens

1. Log in to the [Twingate Admin Console](https://www.twingate.com/)
2. Navigate to **Network > Connectors**
3. Click **Deploy Connector** and select **Manual**
4. Click **Generate New Tokens**
5. Copy the three values you'll need:
   - **Network name** (e.g., `mycompany` from `https://mycompany.twingate.com`)
   - **Access token**
   - **Refresh token**

## Quick Start

### Option 1: Interactive

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/setup.sh | sudo bash
```

The script will prompt for your container name, Twingate network name, access token, and refresh token.

### Option 2: Non-interactive

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/setup.sh | sudo TWINGATE_NETWORK="mycompany" TWINGATE_ACCESS_TOKEN="your-access-token" TWINGATE_REFRESH_TOKEN="your-refresh-token" bash
```

All three environment variables are required for non-interactive mode. You can also set `CONTAINER_NAME` to override the default (`twingate-connector`) and `AUTO_UPDATE=1` to enable automatic updates.

## What the Script Does

1. Checks for root privileges
2. Prompts for a container name (defaults to `twingate-connector`) and Twingate credentials
3. Installs the [unifi-common](https://github.com/unifi-utilities/unifi-common) boot service for firmware update persistence
4. Installs host dependencies (`systemd-container`, `debootstrap`) and caches them for offline recovery
5. Bootstraps a Debian Bookworm container (~10 minutes on gateway hardware)
6. Configures the container (root password, DNS resolvers, hostname, systemd-networkd)
7. Creates the nspawn configuration with host networking and all capabilities, and persists a copy to `/data`
8. Starts the container and enables auto-start on boot
9. Installs the Twingate Connector inside the container using the [official Linux setup script](https://binaries.twingate.com/connector/setup.sh)
10. Applies a user namespace compatibility fix for kernels that don't support it
11. Optionally configures automatic security and connector updates via unattended-upgrades
12. Generates a boot script that restores container state after firmware updates
13. Verifies the Connector status and prints a summary

### Retrofitting Existing Installations

If you already deployed a container using an older version of this script, you can run the new version to add boot persistence without reinstalling. The script detects the running container and only adds the persistence layer (boot hook, package cache, automatic updates).

## How Boot Persistence Works

UniFi OS firmware updates wipe `/var/` and `/etc/`, which destroys the machinectl symlinks, nspawn configuration, and auto-start state. The container filesystem in `/data/custom/machines/` survives, but nothing will start it.

This project uses [unifi-common](https://github.com/unifi-utilities/unifi-common), which installs a systemd service that runs scripts from `/data/on_boot.d/` on every boot. The setup script generates a boot hook that:

1. Reinstalls `systemd-container` if missing (from cached packages or via apt)
2. Recreates the `/var/lib/machines/` symlink
3. Restores the nspawn configuration from the persistent copy in `/data/custom/nspawn/`
4. Starts the container and re-enables auto-start
5. Health-checks the Twingate Connector and attempts to start it if needed

This runs on every boot, so the container is restored automatically after firmware updates with no manual intervention.

## Updating

### Automatic Updates

During setup, you can opt in to [unattended-upgrades](https://wiki.debian.org/UnattendedUpgrades) inside the container. When enabled, this automatically installs security patches and Twingate Connector updates on a daily schedule. In interactive mode, the script will prompt you. In non-interactive mode, set `AUTO_UPDATE=1` to enable it.

### Manual Updates

To trigger an update immediately:

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/update.sh | sudo bash
```

Or with a specific container:

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/update.sh | sudo CONTAINER_NAME="my-connector" bash
```

This updates all packages inside the container (including the Twingate Connector), restarts the connector service, and refreshes the host package cache.

## Container Management

| Command | Description |
|---------|-------------|
| `machinectl status twingate-connector` | View container status |
| `machinectl shell twingate-connector` | Open a shell inside the container |
| `machinectl login twingate-connector` | Login to the container (password: `twingate`) |
| `machinectl stop twingate-connector` | Stop the container |
| `machinectl start twingate-connector` | Start the container |
| `machinectl disable twingate-connector` | Disable auto-start on boot |

## Key Paths

| Path | Description |
|------|-------------|
| `/data/custom/machines/twingate-connector` | Container root filesystem (persists across reboots and firmware updates) |
| `/data/custom/nspawn/twingate-connector.nspawn` | Persistent copy of the nspawn configuration |
| `/data/custom/dpkg/` | Cached host packages for offline boot recovery |
| `/data/custom/twingate/twingate-connector.conf` | Container metadata |
| `/data/custom/twingate/boot.log` | Boot script log (rotated at 1MB) |
| `/data/on_boot.d/05-nspawn-twingate-connector.sh` | Boot hook script (runs on every boot) |
| `/var/lib/machines/twingate-connector` | Symlink to container (recreated on boot if missing) |
| `/etc/systemd/nspawn/twingate-connector.nspawn` | Active nspawn configuration (recreated on boot if missing) |

## Uninstall

To completely remove the Connector, container, and all associated persistence artifacts:

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/uninstall.sh | sudo bash
```

Or with a specific container:

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/uninstall.sh | sudo CONTAINER_NAME="my-connector" bash
```

The uninstall script removes the container filesystem, boot script, cached packages, and all configuration. It does not remove the unifi-common boot service, as other tools may depend on it.

### Manual Uninstall

If you prefer to remove everything manually (swap `twingate-connector` for your container name):

```bash
sudo machinectl disable twingate-connector
sudo machinectl stop twingate-connector
sudo rm -rf /data/custom/machines/twingate-connector
sudo rm -f /var/lib/machines/twingate-connector
sudo rm -f /etc/systemd/nspawn/twingate-connector.nspawn
sudo rm -f /data/custom/nspawn/twingate-connector.nspawn
sudo rm -f /data/on_boot.d/05-nspawn-twingate-connector.sh
sudo rm -f /data/custom/twingate/twingate-connector.conf
sudo rm -f /data/custom/twingate/boot.log
sudo rm -rf /data/custom/dpkg/
```

## Security Considerations

- The container runs with **all capabilities** and **host networking**. This is required for the Connector to function as a network gateway.
- The container root password is set to `twingate`. The container is not network-accessible (no SSH server inside), so risk is minimal. Change it if desired via `machinectl shell`.
- Twingate tokens are stored inside the container at `/etc/twingate/connector.conf`, which is the standard Connector behavior.
- **User namespaces are disabled** (`PrivateUsers=off`) because most Ubiquiti gateway kernels lack user namespace support.
- The script uses `curl | bash` to run the official Twingate installer inside the container. This is the same installation method [documented by Twingate](https://www.twingate.com/docs/connectors-on-linux).
- Automatic updates via unattended-upgrades are available as an opt-in during setup. When enabled, this keeps the container patched against known vulnerabilities.

## Troubleshooting

### Container fails to start

```bash
machinectl status twingate-connector
journalctl -M twingate-connector -xe --no-pager
```

### Connector not connecting

1. Verify your credentials were entered correctly
2. Check DNS resolution inside the container:
   ```bash
   nsenter -t $(machinectl show twingate-connector -p Leader --value) -m -u -i -n -p -- curl -s https://binaries.twingate.com
   ```
3. Check Connector logs:
   ```bash
   nsenter -t $(machinectl show twingate-connector -p Leader --value) -m -u -i -n -p -- journalctl -u twingate-connector -n 50 --no-pager
   ```

### Container not recovering after firmware update

Check the boot log for errors:

```bash
cat /data/custom/twingate/boot.log
```

Verify the boot service is installed and enabled:

```bash
systemctl status udm-boot.service
```

Verify the boot script exists and is executable:

```bash
ls -la /data/on_boot.d/05-nspawn-twingate-connector.sh
```

### debootstrap takes a long time

This is normal on Gateway hardware. Expect approximately 5-10 minutes depending on your internet connection and device.

## Repository Structure

```
ubiquiti-gateway-connector/
├── README.md
├── LICENSE
├── .gitignore
├── setup.sh
├── uninstall.sh
└── update.sh
```

## Need Help?

- [Twingate Documentation](https://docs.twingate.com/)
- [Twingate Community (Reddit)](https://www.reddit.com/r/twingate/)
- [Report an Issue](https://github.com/Twingate-Community/ubiquiti-gateway-connector/issues)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
