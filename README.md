# DN-Subscription HAProxy Manager

A Docker-based HAProxy manager for routing traffic based on hostname (SNI) to different backend services. Designed for managing multiple subdomains on ports 443 and 2096.

## Features

- **Hostname-based routing** - Route `dash.subdigital.network` and `panel.subdigital.network` to different backend ports
- **Dual port support** - Listens on both 443 (HTTPS) and 2096
- **SSL termination** - HAProxy handles SSL with configurable certificates
- **Health checks** - Automatic backend health monitoring
- **Stats dashboard** - Built-in monitoring at port 8404
- **Cross-platform** - Supports Debian/Ubuntu, RHEL/Fedora, Arch Linux
- **Simple CLI** - One command to install, manage, and uninstall

## Quick Install

```bash
sudo bash -c "$(curl -sL https://github.com/erfanask-dev/dn-subscription/raw/main/dnsubscription.sh)" @ install
```

This will:
1. Detect your OS and install Docker + Docker Compose if needed
2. Download configuration files to `/opt/dn-subscription/`
3. Prompt for backend ports (dash, panel, default)
4. Prompt for monitoring password
4. Configure HAProxy with your settings

## Manual Install

```bash
# Download the script
curl -sL -o dnsubscription.sh https://github.com/erfanask-dev/dn-subscription/raw/main/dnsubscription.sh
chmod +x dnsubscription.sh

# Run install (requires sudo)
sudo ./dnsubscription.sh install

# Optionally install CLI globally
sudo ./dnsubscription.sh install-script

# Then use from anywhere
dnsubscription menu
```

## Usage

After installation, manage the service with:

```bash
# Interactive menu
dnsubscription menu

# Or direct commands
dnsubscription up        # Start services
dnsubscription down      # Stop services
dnsubscription restart   # Restart services
dnsubscription status    # Show container status
dnsubscription logs      # Follow logs (Ctrl+C to exit)
dnsubscription help      # Show help
```

## Uninstall

```bash
# Via installed CLI
sudo dnsubscription uninstall

# Or via script directly
sudo ./dnsubscription.sh uninstall
```

This will:
- Stop and remove Docker containers
- Remove `/opt/dn-subscription/` directory
- Optionally remove the CLI command from `/usr/local/bin/dnsubscription`

## Configuration

### Directory Structure

```
/opt/dn-subscription/
├── docker-compose.yaml    # Docker Compose configuration
├── haproxy.cfg           # HAProxy configuration (auto-generated)
└── certs/                # SSL certificates (you provide)
    ├── dash.subdigital.network.pem
    ├── panel.subdigital.network.pem
    └── ...
```

### SSL Certificates

Place your SSL certificates (`.pem` format containing both cert and private key) in `/opt/dn-subscription/certs/`.

```bash
# Example: Generate self-signed for testing
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout dash.subdigital.network.key \
  -out dash.subdigital.network.crt

# Combine into .pem (cert + key)
cat dash.subdigital.network.crt dash.subdigital.network.key > dash.subdigital.network.pem
cp dash.subdigital.network.pem /opt/dn-subscription/certs/
```

### HAProxy Configuration

The `haproxy.cfg` is generated during install with your chosen ports:

| Placeholder | Description | Default |
|-------------|-------------|---------|
| `DASH_TARGET_PORT` | Backend port for `dash.subdigital.network` | 8080 |
| `PANEL_TARGET_PORT` | Backend port for `panel.subdigital.network` | 3000 |
| `DEFAULT_TARGET_PORT` | Fallback backend port | 80 |
| `CHANGE_THIS_PASSWORD` | Stats dashboard password | (prompted) |

To reconfigure, run `sudo dnsubscription install` again (will prompt to overwrite).

## Monitoring

Access HAProxy stats dashboard at:
```
http://your-server-ip:8404/stats
```
- Username: `admin`
- Password: (what you set during install)

## Requirements

- Linux (Debian/Ubuntu, RHEL/CentOS/Fedora, Arch)
- Root/sudo access
- Internet access (for downloading Docker images and packages)
- Ports 443, 2096, 8404 available

## Supported Distributions

| Distribution | Package Manager | Docker Install Method |
|--------------|-----------------|----------------------|
| Ubuntu/Debian | apt | Official Docker repo |
| Fedora/CentOS/RHEL | dnf/yum | Official Docker repo |
| Arch/Manjaro | pacman | Official repos |

## Files

| File | Description |
|------|-------------|
| `dnsubscription.sh` | Main CLI script |
| `docker-compose.yaml` | Docker Compose template |
| `haproxy.cfg` | HAProxy config template |
| `.gitignore` | Git ignore rules |

## License

MIT License