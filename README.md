# Twingate Connector for Ubiquiti Gateways

Deploy a [Twingate](https://www.twingate.com/) Connector on Ubiquiti gateway devices using a lightweight systemd-nspawn container.

## :rocket: Overview

Ubiquiti gateways (UDM Pro, UDM SE, UXG-Pro, UXG-Max, etc.) run a customized Linux environment that doesn't include a native container runtime. This project uses **systemd-nspawn** to bootstrap a minimal Debian container directly on the gateway, install the Twingate Connector inside it, and configure it to start automatically on boot.

The container filesystem is stored under `/data/custom/machines/`, which persists across UniFi OS firmware upgrades.

## :sparkles: Features

- **Automated setup** -- single script handles everything from container creation to Connector installation
- **Persistent across reboots** -- container data lives on the gateway's persistent `/data` partition
- **Auto-start on boot** -- enabled via `machinectl enable`
- **Host networking** -- no NAT, the Connector has full LAN access
- **Kernel compatibility** -- includes a fix for gateways without user namespace support
- **Flexible credentials** -- pass tokens via environment variables or enter them interactively

## :clipboard: Prerequisites

- A **Ubiquiti gateway** (UDM Pro, UDM SE, UXG-Pro, UXG-Max, or similar) running UniFi OS 3.x or later
- **SSH access** to the gateway as root
- A **Twingate account** with a Connector provisioned
- **Internet connectivity** on the gateway (for downloading packages and Twingate binaries)

### Generating Connector Tokens

1. Log in to the [Twingate Admin Console](https://www.twingate.com/)
2. Navigate to **Network > Connectors**
3. Click **Deploy Connector** and select **Linux**
4. Copy the three values you'll need:
   - **Network name** (e.g., `mycompany`)
   - **Access token**
   - **Refresh token**

## :rocket: Quick Start

### Option 1: One-liner

```bash
curl -sSf https://raw.githubusercontent.com/Twingate-Community/ubiquiti-gateway-connector/main/setup.sh | sudo bash
```

This will prompt interactively for your Twingate credentials.

### Option 2: Clone and run

```bash
git clone https://github.com/Twingate-Community/ubiquiti-gateway-connector.git
cd ubiquiti-gateway-connector
sudo bash setup.sh
```

### Option 3: Non-interactive (environment variables)

```bash
export TWINGATE_NETWORK="mycompany"
export TWINGATE_ACCESS_TOKEN="your-access-token"
export TWINGATE_REFRESH_TOKEN="your-refresh-token"
sudo -E bash setup.sh
```

## :gear: What the Script Does

1. Checks for root privileges
2. Prompts for Twingate credentials (or reads them from environment variables)
3. Validates that no existing container is already running
4. Installs host dependencies (`systemd-container`, `debootstrap`)
5. Bootstraps a Debian Bookworm container (~10 minutes on gateway hardware)
6. Configures the container (root password, DNS resolvers, hostname, systemd-networkd)
7. Creates the nspawn configuration with host networking and all capabilities
8. Starts the container and enables auto-start on boot
9. Installs the Twingate Connector inside the container using the [official setup script](https://binaries.twingate.com/connector/setup.sh)
10. Applies a user namespace compatibility fix for kernels that don't support it
11. Verifies the Connector status and prints a summary

## :wrench: Container Management

| Command | Description |
|---------|-------------|
| `machinectl status twingate-connector` | View container status |
| `machinectl shell twingate-connector` | Open a shell inside the container |
| `machinectl login twingate-connector` | Login to the container (password: `twingate`) |
| `machinectl stop twingate-connector` | Stop the container |
| `machinectl start twingate-connector` | Start the container |
| `machinectl disable twingate-connector` | Disable auto-start on boot |

## :file_folder: Key Paths

| Path | Description |
|------|-------------|
| `/data/custom/machines/twingate-connector` | Container root filesystem (persists across reboots) |
| `/var/lib/machines/twingate-connector` | Symlink to above (required by machinectl) |
| `/etc/systemd/nspawn/twingate-connector.nspawn` | Container configuration |

## :wastebasket: Uninstall

To completely remove the Connector and container:

```bash
sudo machinectl disable twingate-connector
sudo machinectl stop twingate-connector
sudo rm -rf /data/custom/machines/twingate-connector
sudo rm -f /var/lib/machines/twingate-connector
sudo rm -f /etc/systemd/nspawn/twingate-connector.nspawn
```

## :lock: Security Considerations

- The container runs with **all capabilities** and **host networking**. This is required for the Connector to function as a network gateway.
- The container root password is set to `twingate`. The container is not network-accessible (no SSH server inside), so risk is minimal. Change it if desired via `machinectl shell`.
- Twingate tokens are stored inside the container at `/etc/twingate/connector.conf`, which is the standard Connector behavior.
- **User namespaces are disabled** (`PrivateUsers=off`) because most Ubiquiti gateway kernels lack user namespace support.
- The script uses `curl | bash` to run the official Twingate installer inside the container. This is the same installation method [documented by Twingate](https://www.twingate.com/docs/connectors).

## :mag: Troubleshooting

### Container fails to start

```bash
machinectl status twingate-connector
journalctl -M twingate-connector -xe --no-pager
```

### Connector not connecting

1. Verify your credentials were entered correctly
2. Check DNS resolution inside the container:
   ```bash
   machinectl shell twingate-connector /bin/bash -c "curl -s https://binaries.twingate.com"
   ```
3. Check Connector logs:
   ```bash
   machinectl shell twingate-connector /bin/bash -c "journalctl -u twingate-connector -n 50 --no-pager"
   ```

### Container missing after firmware upgrade

The container data in `/data/custom/machines/` persists across firmware upgrades, but the symlink at `/var/lib/machines/` and the nspawn config at `/etc/systemd/nspawn/` may need to be recreated. Re-running the script will detect the existing container directory and prompt you before proceeding.

### debootstrap takes a long time

This is normal on gateway hardware. Expect approximately 10 minutes depending on your internet connection and device.

## :file_folder: Repository Structure

```
ubiquiti-gateway-connector/
├── README.md
├── LICENSE
├── .gitignore
└── setup.sh
```

## :raised_hands: Need Help?

- [Twingate Documentation](https://docs.twingate.com/)
- [Twingate Community (Reddit)](https://www.reddit.com/r/twingate/)
- [Report an Issue](https://github.com/Twingate-Community/ubiquiti-gateway-connector/issues)

## :page_facing_up: License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
