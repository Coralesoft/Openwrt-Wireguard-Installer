# WireGuard Key Rotation Guide for OpenWrt

## What is Key Rotation?
Key rotation means replacing your WireGuard encryption keys with new ones. This is important for security - if someone gets your keys, they can't use old ones after rotation.

## The Key Rotation Script
The `wg-key-rotate.sh` script handles key rotation on your OpenWrt router. It:
- Generates new encryption keys
- Updates your router's configuration
- Creates new config files for your devices
- Backs up old keys (just in case)

## Installation
```bash
# SSH into your OpenWrt router
ssh root@your-router-ip

# Download the script
cd /root
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-key-rotate.sh
chmod +x wg-key-rotate.sh
```

## How to Use

### See Options
```bash
./wg-key-rotate.sh --help
```

### Rotate Server Keys
Changes the router's main keys. **All devices will need new configs.**
```bash
./wg-key-rotate.sh --server
```

### Rotate a Specific Device
Only changes keys for one device (e.g., if phone was stolen):
```bash
./wg-key-rotate.sh --peer=phone
```

### Rotate All Device Keys
Changes all device keys but keeps router keys the same:
```bash
./wg-key-rotate.sh --all-peers
```

### Rotate Everything
Maximum security - changes all keys:
```bash
./wg-key-rotate.sh --server --all-peers
```

## After Rotation

### 1. Find New Configs
New configuration files are saved on your router at:
```
/etc/wireguard/peers/
```

### 2. Get Configs to Users
View config as QR code (for phones):
```bash
qrencode -t ansiutf8 < /etc/wireguard/peers/phone.conf
```

Copy config from router (for computers):
```bash
# Run from your computer
scp root@router-ip:/etc/wireguard/peers/laptop.conf ./
```

### 3. Users Update Their Devices
Users must:
1. Delete old WireGuard connection
2. Add new connection using the new config file
3. Connect to test

### 4. Verify It Works
Check connections on your router:
```bash
wg show wg0
```

## Important Notes

- **Server rotation** = ALL devices need new configs
- **Peer rotation** = Only that device needs new config  
- **Backups** are saved in `/etc/wireguard/backup/` with timestamp
- **Test** before deleting backups

## When to Rotate Keys

- Device lost or stolen → Rotate that peer immediately
- Employee leaves → Rotate affected peers
- Regular security → Every 3-6 months
- Suspected compromise → Rotate everything

## Troubleshooting

Can't connect after rotation?
```bash
# Check if WireGuard is running
wg show wg0

# Restart WireGuard
/etc/init.d/network restart

# Check logs
logread | grep -i wireguard
```

Need to undo rotation?
```bash
# Backups are in timestamped folders
ls /etc/wireguard/backup/
# Copy back the files you need
```

## Quick Reference

| What You Want | Command |
|--------------|---------|
| Rotate everything | `./wg-key-rotate.sh --server --all-peers` |
| Rotate server only | `./wg-key-rotate.sh --server` |
| Rotate one device | `./wg-key-rotate.sh --peer=laptop` |
| Rotate all devices | `./wg-key-rotate.sh --all-peers` |
| See all options | `./wg-key-rotate.sh --help` |

Remember: After any rotation, affected devices need their new config files!
