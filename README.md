# OpenWrt WireGuard Interactive Installer

A comprehensive set of scripts for automated WireGuard VPN setup, management, and maintenance on OpenWrt routers.

## 🚀 Features

- **Automated Installation** - Complete WireGuard setup with a single script
- **Peer Management** - Easy creation and management of VPN peers
- **QR Code Generation** - Instant mobile device setup with QR codes
- **Key Rotation** - Security-focused key rotation capabilities
- **Backup & Rollback** - Automatic configuration backups with rollback option
- **Clean Uninstall** - Complete removal tool with verification

## 📦 Scripts Included

| Script | Purpose | Version |
|--------|---------|---------|
| `wg-openwrt-installer.sh` | Main installer and peer setup | 2025.8.1 |
| `wg-key-rotate.sh` | Key rotation for security | 2025.9.1 |
| `wg-uninstall.sh` | Clean removal of WireGuard | 2025.8.2 |

## 🔧 Prerequisites

### OpenWrt Router Requirements
- OpenWrt 23.05 or later
- WireGuard kernel module and tools

### Install WireGuard packages:
```bash
opkg update
opkg install wireguard-tools luci-app-wireguard kmod-wireguard
```

### Optional: Install QR code generator
```bash
opkg install qrencode
```

## 📖 Quick Start

### 1. Download the Scripts
```bash
cd /root
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-openwrt-installer.sh
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-key-rotate.sh
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-uninstall.sh
chmod +x *.sh
```

### 2. Run the Installer
```bash
./wg-openwrt-installer.sh
```

The installer will prompt for:
- WireGuard interface name (default: wg0)
- UDP port (default: 51820)
- VPN subnet (default: 192.168.20.1/24)
- Public endpoint (your router's public IP/domain)
- Number of peers to create

### 3. Configure Peer Devices

After installation, peer configurations are available in:
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
2. Scan QR code or import .conf file
3. Activate tunnel

#### On Desktop/Laptop:
```bash
# Copy the .conf file to the peer device, then:
sudo cp peer.conf /etc/wireguard/wg0.conf
sudo wg-quick up wg0
```

## 🔑 Key Rotation

Regular key rotation is essential for security. Use the included rotation script:

### Rotate Everything (Maximum Security)
```bash
./wg-key-rotate.sh --server --all-peers
```

### Rotate Specific Peer
```bash
./wg-key-rotate.sh --peer=laptop
```

### Rotate Server Key Only
```bash
./wg-key-rotate.sh --server
```

**Note:** After rotating server keys, ALL peers must update their configurations!

## 🗑️ Uninstallation

To completely remove WireGuard configuration:

```bash
# Dry run (preview what will be removed)
./wg-uninstall.sh --dry-run

# Full uninstall
./wg-uninstall.sh
```

The uninstaller removes:
- Network interface configuration
- All peer configurations
- Firewall rules
- WireGuard keys and configs
- Live network interface

## 📁 File Structure

After installation, WireGuard files are organized as:

```
/etc/wireguard/
├── privatekey          # Server private key
├── publickey           # Server public key
├── peers/              # Peer configurations
│   ├── laptop.conf     # Peer config file
│   ├── laptop-privatekey
│   ├── laptop-publickey
│   └── laptop.png      # QR code
└── backup/             # Key rotation backups (when applicable)

/etc/config/
├── network             # UCI network config
├── firewall            # UCI firewall config
├── network.bak.*       # Automatic backups
└── firewall.bak.*      # Automatic backups
```

## 🛡️ Security Best Practices

1. **Regular Key Rotation**: Rotate keys every 3-6 months
2. **Secure Key Distribution**: Never send configs over unencrypted channels
3. **Firewall Configuration**: Ensure only necessary ports are open
4. **Peer Management**: Remove unused peers promptly
5. **Backup Keys**: Keep secure backups of your configurations

## 🔧 Advanced Configuration

### Custom Interface Name
```bash
./wg-openwrt-installer.sh
# When prompted, enter custom interface name (e.g., wg1)
```

### Multiple WireGuard Interfaces
Run the installer multiple times with different interface names:
```bash
# First VPN
./wg-openwrt-installer.sh  # Use wg0

# Second VPN
./wg-openwrt-installer.sh  # Use wg1
```

### Manual Configuration
After installation, you can manually edit:
```bash
# UCI configuration
uci show network.wg0
uci set network.wg0.listen_port='51821'
uci commit network
/etc/init.d/network restart

# Direct WireGuard commands
wg show wg0
wg set wg0 peer [PUBLIC_KEY] allowed-ips 192.168.20.5/32
```

## 📊 Monitoring

### Check WireGuard Status
```bash
# Show interface status
wg show wg0

# Show connected peers
wg show wg0 peers

# Check latest handshakes
wg show wg0 latest-handshakes
```

### Using LuCI Web Interface
If `luci-app-wireguard` is installed:
1. Navigate to: `Status` → `WireGuard`
2. View connected peers and traffic statistics

## 🐛 Troubleshooting

### Peers Can't Connect
```bash
# Check if WireGuard is running
wg show wg0

# Verify firewall rules
uci show firewall | grep wg0

# Check port forwarding
netstat -ulnp | grep 51820

# View logs
logread | grep -i wireguard
```

### No Handshake
- Verify endpoint is correct in peer config
- Check that UDP port is open/forwarded
- Ensure time is synchronized on both devices
- Verify keys match between server and peer

### DNS Issues
- Check DNS server in peer configs
- Verify DNS forwarding is enabled on OpenWrt
- Test with IP addresses instead of hostnames

## 📝 Script Options

### Installer Options
The installer uses interactive prompts for all configuration.

### Key Rotation Options
```bash
./wg-key-rotate.sh --help

Options:
  --server           Rotate server keypair
  --peer=NAME        Rotate specific peer
  --all-peers        Rotate all peers
  --no-backup        Skip key backup
  --interface=NAME   Specify interface (default: wg0)
```

### Uninstall Options
```bash
./wg-uninstall.sh --help

Options:
  --dry-run          Preview without changes
  --interface=NAME   Specify interface (default: wg0)
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

### Development
- Scripts follow POSIX shell standards
- Compatible with OpenWrt's ash shell
- Extensive error checking and validation
- User-friendly colored output

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- WireGuard® is a registered trademark of Jason A. Donenfeld
- OpenWrt Project for the excellent router firmware
- Community contributors and testers

## 📮 Support

For issues, questions, or suggestions:
- Open an issue on [GitHub](https://github.com/Coralesoft/Openwrt-Wireguard-Installer/issues)
- Check existing issues for solutions
- Provide router model and OpenWrt version when reporting issues

## 🔗 Links

- [WireGuard Official Site](https://www.wireguard.com/)
- [OpenWrt Documentation](https://openwrt.org/docs/guide-user/services/vpn/wireguard/start)
- [WireGuard on OpenWrt Wiki](https://openwrt.org/docs/guide-user/services/vpn/wireguard/basics)

---

**Note:** Always test changes in a safe environment before deploying to production routers. Keep backups of working configurations!