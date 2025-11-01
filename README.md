# OpenWrt WireGuard Interactive Installer

A comprehensive set of scripts for automated WireGuard VPN setup, management, and maintenance on OpenWrt routers.

## 🚀 Features

- **Automated Installation** - Complete WireGuard setup with interactive prompts
- **Auto Package Installation** - Detects and installs missing packages automatically
- **Interactive Peer Management** - User-friendly menu interface for managing peers
- **QR Code Generation** - Instant mobile device setup with QR codes
- **Key Rotation** - Security-focused key rotation with backup
- **Backup & Rollback** - Automatic configuration backups with rollback option
- **System Backup Integration** - Adds WireGuard to OpenWrt backup configuration
- **Clean Uninstall** - Complete removal tool with dry-run preview

## 📦 Scripts Included

| Script | Purpose | Version |
|--------|---------|---------|
| `wg-openwrt-installer.sh` | Main installer and initial peer setup | 2025.11.2 |
| `wg-peer-manage.sh` | Interactive peer management | 2025.11.2 |
| `wg-key-rotate.sh` | Key rotation for security | 2025.9.1 |
| `wg-uninstall.sh` | Clean removal of WireGuard | 2025.11.2 |

## 🔧 Prerequisites

### OpenWrt Router Requirements
- OpenWrt 23.05 or later
- Internet connectivity for package installation

### Required Packages
The installer will automatically detect and offer to install:
- `wireguard-tools` - WireGuard command-line utilities
- `kmod-wireguard` - WireGuard kernel module
- `luci-app-wireguard` - LuCI web interface integration

### Optional Packages
- `qrencode` - QR code generation for mobile devices

**Note:** You no longer need to manually install packages! The installer will handle this for you.

## 📖 Quick Start

### 1. Download the Scripts
```bash
cd /root
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-openwrt-installer.sh
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-peer-manage.sh
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-key-rotate.sh
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-uninstall.sh
chmod +x wg-*.sh
```

### 2. Run the Installer
```bash
./wg-openwrt-installer.sh
```

The installer will:
1. Check for missing packages and offer to install them
2. Guide you through configuration with helpful prompts
3. Generate server and peer keys
4. Configure network and firewall
5. Generate QR codes for easy mobile setup
6. Add `/etc/wireguard` to backup configuration

**Interactive Prompts:**
- WireGuard interface name (default: `wg0`)
- UDP port (default: `51820`)
- VPN subnet (default: `192.168.20.1/24`)
- Public endpoint (your router's public IP/domain)
- LAN/WAN zone names
- DNS server for peers
- Number of initial peers to create

### 3. Manage Peers (New!)

Use the interactive peer management tool:

```bash
./wg-peer-manage.sh
```

**Interactive Menu:**
```
WireGuard Peer Management
════════════════════════════════════════
Interface: wg0

1. List all peers
2. Add new peer
3. Manage existing peer
4. Show traffic statistics
5. Show active connections
6. Restart WireGuard interface
7. Exit

Select option [1-7]: _
```

**Features:**
- 📋 List peers with numbers and status
- ➕ Add new peers with auto-IP allocation
- 🔧 Enable/disable peers without removing them
- 🗑️ Remove peers with automatic archiving
- 📊 View traffic statistics
- 🔍 Show peer details and regenerate QR codes
- 🔄 Restart interface when needed

**Command-Line Mode (Scriptable):**
```bash
./wg-peer-manage.sh --list              # List all peers
./wg-peer-manage.sh --add               # Add new peer
./wg-peer-manage.sh --show=laptop       # Show peer details + QR
./wg-peer-manage.sh --remove=old-phone  # Remove peer
./wg-peer-manage.sh --disable=tablet    # Temporarily disable
./wg-peer-manage.sh --enable=tablet     # Re-enable
./wg-peer-manage.sh --traffic           # Show bandwidth usage
./wg-peer-manage.sh --active            # Show connected peers
./wg-peer-manage.sh --no-clear          # Disable screen clearing
```

### 4. Configure Peer Devices

After adding peers, configurations are available in:
```
/etc/wireguard/peers/
```

Each peer gets:
- `.conf` file - WireGuard configuration
- `-privatekey` - Peer's private key
- `-publickey` - Peer's public key
- `.png` - QR code (if qrencode installed)

#### On Mobile Devices:
1. Install WireGuard app
2. Tap "+" → "Scan from QR code"
3. Scan the displayed QR code
4. Activate tunnel

#### On Desktop/Laptop:
```bash
# Copy the .conf file to the peer device, then:
sudo cp peer.conf /etc/wireguard/wg0.conf
sudo wg-quick up wg0

# Enable at boot (optional):
sudo systemctl enable wg-quick@wg0
```

## 🔑 Key Rotation

Regular key rotation is essential for security. Use the included rotation script:

### Rotate Everything (Maximum Security)
```bash
./wg-key-rotate.sh --server --all-peers
```

### Rotate Specific Peer
```bash
./wg-key-rotate.sh --peer=laptop --peer=phone
```

### Rotate Server Key Only
```bash
./wg-key-rotate.sh --server
```

**Important Notes:**
- After rotating server keys, ALL peers must update their configurations!
- Old keys are backed up to `/etc/wireguard/backup/`
- New peer configs and QR codes are automatically generated
- The script will prompt to restart the interface

**Options:**
```bash
--server           Rotate server keypair
--peer=NAME        Rotate specific peer (can use multiple times)
--all-peers        Rotate all peer keypairs
--no-backup        Skip creating backups
--interface=NAME   Specify interface (default: wg0)
```

## 🗑️ Uninstallation

To completely remove WireGuard configuration:

```bash
# Preview what will be removed (recommended first step)
./wg-uninstall.sh --dry-run

# Full uninstall
./wg-uninstall.sh

# Uninstall specific interface
./wg-uninstall.sh --interface=wg1
```

The uninstaller removes:
- ✅ Network interface configuration (UCI)
- ✅ All peer configurations
- ✅ Firewall rules and zones
- ✅ WireGuard keys and configs (`/etc/wireguard/`)
- ✅ Live network interface
- ✅ `/etc/wireguard` from backup configuration

**Note:** The uninstaller will ask for confirmation before making changes.

## 📁 File Structure

After installation, WireGuard files are organized as:

```
/etc/wireguard/
├── privatekey              # Server private key
├── publickey               # Server public key
├── peers/                  # Peer configurations
│   ├── laptop.conf         # Peer config file
│   ├── laptop-privatekey   # Peer private key
│   ├── laptop-publickey    # Peer public key
│   └── laptop.png          # QR code
├── backup/                 # Key rotation backups
│   └── 20251101-120000/    # Timestamped backup directory
└── removed/                # Archived removed peers
    └── 20251101-130000-old-device/

/etc/config/
├── network                 # UCI network config
├── firewall                # UCI firewall config
├── network.bak.*           # Automatic backups
└── firewall.bak.*          # Automatic backups

/etc/sysupgrade.conf        # Contains /etc/wireguard for backups
```

## 🛡️ Security Best Practices

1. **Regular Key Rotation**: Rotate keys every 3-6 months
2. **Secure Key Distribution**: Never send configs over unencrypted channels
3. **Firewall Configuration**: Ensure only necessary ports are open
4. **Peer Management**: Remove unused peers promptly using `wg-peer-manage.sh`
5. **Backup Keys**: System backups now include `/etc/wireguard` automatically
6. **Monitor Connections**: Use `--active` to check connected peers regularly

## 💾 Backup & Restore

### Automatic Backup Integration
The installer automatically adds `/etc/wireguard/` to OpenWrt's backup configuration (`/etc/sysupgrade.conf`).

**This means:**
- ✅ Your WireGuard keys are included in system backups
- ✅ Configurations persist across system upgrades
- ✅ Backups created via LuCI include WireGuard

### Create Manual Backup
```bash
# Create backup archive
sysupgrade -b /tmp/backup-$(date +%Y%m%d).tar.gz

# Verify WireGuard is included
tar -tzf /tmp/backup-*.tar.gz | grep wireguard
```

### Restore from Backup
```bash
# After fresh install or upgrade:
sysupgrade -r /tmp/backup-20251101.tar.gz
# Router will reboot and restore WireGuard configuration
```

## 🔧 Advanced Configuration

### Custom Interface Name
During installation, simply enter a different interface name when prompted:
```bash
./wg-openwrt-installer.sh
# When prompted: Enter WireGuard interface name [wg0]: wg1
```

### Multiple WireGuard Interfaces
Run the installer multiple times with different interface names:
```bash
# First VPN
./wg-openwrt-installer.sh  # Use wg0

# Second VPN
./wg-openwrt-installer.sh  # Use wg1

# Manage each separately
./wg-peer-manage.sh --interface=wg0
./wg-peer-manage.sh --interface=wg1
```

### Manual UCI Configuration
After installation, you can manually edit:
```bash
# Show current configuration
uci show network.wg0

# Change port
uci set network.wg0.listen_port='51821'
uci commit network
/etc/init.d/network restart

# Add manual peer
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].description='manual-peer'
uci set network.@wireguard_wg0[-1].public_key='<PUBLIC_KEY>'
uci set network.@wireguard_wg0[-1].allowed_ips='192.168.20.10/32'
uci commit network
```

## 📊 Monitoring

### Using Peer Management Script
```bash
./wg-peer-manage.sh --active    # Show currently connected peers
./wg-peer-manage.sh --traffic   # Show bandwidth usage per peer
./wg-peer-manage.sh --list      # List all configured peers
```

### Command Line
```bash
# Show interface status
wg show wg0

# Show all connected peers with details
wg show wg0 peers

# Check latest handshakes (indicates active connections)
wg show wg0 latest-handshakes

# Show transfer statistics
wg show wg0 transfer

# Compact view of all info
wg show wg0 dump
```

### Using LuCI Web Interface
If `luci-app-wireguard` is installed:
1. Navigate to: `Status` → `WireGuard`
2. View connected peers and traffic statistics
3. Or: `Network` → `Interfaces` → `wg0` → `Edit`

## 🐛 Troubleshooting

### Peers Can't Connect
```bash
# 1. Check if WireGuard is running
wg show wg0

# 2. Verify interface has correct IP
ip addr show wg0

# 3. Check firewall rules
uci show firewall | grep wg0

# 4. Verify port is listening
netstat -ulnp | grep 51820

# 5. Check logs
logread | grep -i wireguard

# 6. Test from peer device
ping 192.168.20.1  # Should work if connected
```

### No Handshake
- Verify endpoint in peer config matches your public IP/domain
- Check that UDP port is open/forwarded on router
- Ensure time is synchronized on both devices (WireGuard requires this)
- Verify keys match between server and peer configs
- Check if peer is enabled: `./wg-peer-manage.sh --list`

### DNS Issues
- Check DNS server in peer configs: `cat /etc/wireguard/peers/device.conf`
- Verify DNS forwarding is enabled on OpenWrt
- Test with IP addresses first: `ping 192.168.1.1`
- Check LAN firewall accepts DNS requests from VPN

### After System Restore
If WireGuard doesn't work after restoring backup:
```bash
# 1. Verify files were restored
ls -la /etc/wireguard/

# 2. Check UCI configuration
uci show network.wg0

# 3. Restart network
/etc/init.d/network restart

# 4. Check interface
wg show wg0
```

### Peer Management Script Issues
```bash
# If you see "Server public key not found":
# WireGuard server not installed yet
./wg-openwrt-installer.sh

# Clear screen issues on some terminals:
./wg-peer-manage.sh --no-clear
```

## 📝 Complete Script Reference

### wg-openwrt-installer.sh
**Purpose:** Initial WireGuard server setup

**Features:**
- Auto-detects and installs missing packages
- Interactive configuration with helpful prompts
- Creates initial peers with QR codes
- Configures network, firewall, and UCI
- Adds WireGuard to backup configuration
- Rollback option if something goes wrong

**Usage:**
```bash
./wg-openwrt-installer.sh
# Follow interactive prompts
```

### wg-peer-manage.sh
**Purpose:** Day-to-day peer management

**Interactive Mode:**
```bash
./wg-peer-manage.sh              # Full interactive menu
./wg-peer-manage.sh --no-clear   # Without screen clearing
```

**Command-Line Mode:**
```bash
./wg-peer-manage.sh --list
./wg-peer-manage.sh --add
./wg-peer-manage.sh --show=NAME
./wg-peer-manage.sh --remove=NAME
./wg-peer-manage.sh --enable=NAME
./wg-peer-manage.sh --disable=NAME
./wg-peer-manage.sh --traffic
./wg-peer-manage.sh --active
./wg-peer-manage.sh --interface=wg1
./wg-peer-manage.sh --help
```

### wg-key-rotate.sh
**Purpose:** Security key rotation

**Usage:**
```bash
./wg-key-rotate.sh --server                    # Rotate server only
./wg-key-rotate.sh --peer=laptop               # Rotate one peer
./wg-key-rotate.sh --peer=laptop --peer=phone  # Multiple peers
./wg-key-rotate.sh --all-peers                 # All peers
./wg-key-rotate.sh --server --all-peers        # Everything
./wg-key-rotate.sh --no-backup                 # Skip backup
./wg-key-rotate.sh --interface=wg1             # Specific interface
./wg-key-rotate.sh --help
```

### wg-uninstall.sh
**Purpose:** Complete removal of WireGuard

**Usage:**
```bash
./wg-uninstall.sh --dry-run        # Preview only
./wg-uninstall.sh                  # Full removal
./wg-uninstall.sh --interface=wg1  # Specific interface
./wg-uninstall.sh --help
```


## 📄 License

This project is open source and available under the [MIT License](LICENSE).

**Copyright:** C.Brown CoraleSoft, 2025

## 📮 Support

For issues, questions, or suggestions:
- Open an issue on [GitHub](https://github.com/Coralesoft/Openwrt-Wireguard-Installer/issues)
- Check existing issues for solutions
- Provide router model and OpenWrt version when reporting issues

## 🔗 Links

- [WireGuard Official Site](https://www.wireguard.com/)
- [OpenWrt Documentation](https://openwrt.org/docs/guide-user/services/vpn/wireguard/start)
- [WireGuard on OpenWrt Wiki](https://openwrt.org/docs/guide-user/services/vpn/wireguard/basics)

## 🎯 Version History

### 2025.11.2 (Current)
- ✨ Added automatic package installation
- ✨ Added interactive peer management tool (`wg-peer-manage.sh`)
- ✨ Added backup configuration integration (`/etc/sysupgrade.conf`)
- ✨ Improved uninstaller with dry-run and interface options
- 🐛 Fixed sed delimiter bug in key rotation
- 🐛 Fixed IP allocation detection in peer manager

### 2025.9.1
- ✨ Initial key rotation script
- 🔒 Secure key backup functionality

### 2025.8.1
- ✨ Initial public release
- 🚀 Basic installer with QR code support

---

**Note:** Always test in a safe environment before deploying to production. Keep backups of working configurations!

**Tested on:** OpenWrt 23.05.x with various routers including Flint 2 (MT6000)
