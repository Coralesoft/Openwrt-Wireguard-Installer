# WireGuard Key Rotation Guide for OpenWrt

## Overview
Key rotation is a critical security practice that helps protect your VPN even if keys are compromised. This guide explains how to rotate WireGuard keys after using the [OpenWrt WireGuard Installer](https://github.com/Coralesoft/Openwrt-Wireguard-Installer).

## Quick Start

### Download the Key Rotation Script
```bash
# Download from the Coralesoft repository
wget https://raw.githubusercontent.com/Coralesoft/Openwrt-Wireguard-Installer/main/wg-key-rotate.sh
chmod +x wg-key-rotate.sh

# Or clone the entire repository
git clone https://github.com/Coralesoft/Openwrt-Wireguard-Installer.git
cd Openwrt-Wireguard-Installer
chmod +x *.sh
```

## Common Rotation Scenarios

### 1. Rotate Everything (Full Rotation)
Rotate both server and all peer keys - maximum security but requires updating all devices:
```bash
./wg-key-rotate.sh --server --all-peers
```

### 2. Rotate Only Server Keys
When you suspect the server might be compromised:
```bash
./wg-key-rotate.sh --server
```
**Note:** ALL peers must update their configurations with the new server public key!

### 3. Rotate Specific Peer Keys
When a specific device is lost or compromised:
```bash
./wg-key-rotate.sh --peer=laptop
# Or multiple peers:
./wg-key-rotate.sh --peer=laptop --peer=phone
```

### 4. Rotate All Peer Keys (Keep Server)
When you want to invalidate all client configs but keep the server key:
```bash
./wg-key-rotate.sh --all-peers
```

## Step-by-Step Process

### Before Rotation
1. **Notify users** - Inform all VPN users about the upcoming change
2. **Schedule maintenance** - Pick a time with minimal usage
3. **Have access** - Ensure you can distribute new configs to users

### During Rotation

#### Step 1: Run the rotation script
```bash
# Example: Rotate server and all peers
./wg-key-rotate.sh --server --all-peers
```

The script will:
- Back up existing keys to `/etc/wireguard/backup/[timestamp]/`
- Generate new keypairs
- Update UCI configuration
- Create new peer .conf files
- Generate QR codes (if qrencode is installed)
- Optionally restart the WireGuard interface

#### Step 2: Verify the rotation
```bash
# Check WireGuard status
wg show wg0

# Verify new keys are loaded
uci show network.wg0.private_key

# List new peer configs
ls -la /etc/wireguard/peers/*.conf
```

### After Rotation

#### Step 1: Distribute new configurations
For each rotated peer, share the new configuration file located in:
```
/etc/wireguard/peers/[peer-name].conf
```

Methods to share:
- **QR Code**: Display with `qrencode -t ansiutf8 < /etc/wireguard/peers/[peer-name].conf`
- **Secure file transfer**: SCP, encrypted email, or secure messaging
- **In person**: For maximum security

#### Step 2: Update peer devices

**On mobile devices (iOS/Android):**
1. Delete the old WireGuard tunnel
2. Scan new QR code or import new .conf file
3. Activate the new tunnel

**On Linux/Mac/Windows:**
1. Replace the old config file
2. Restart WireGuard:
   ```bash
   # Linux
   sudo systemctl restart wg-quick@wg0
   
   # Mac (if using brew services)
   sudo brew services restart wireguard-tools
   
   # Windows
   # Use WireGuard GUI to remove old and import new tunnel
   ```

#### Step 3: Verify connectivity
Test each peer after updating:
```bash
# From the server, check connected peers
wg show wg0

# Look for recent handshakes (should be < 2 minutes for active connections)
wg show wg0 latest-handshakes
```

#### Step 4: Clean up
Once all peers are confirmed working:
```bash
# Remove old key backups
rm -rf /etc/wireguard/backup/[timestamp]/

# Or keep for a week as safety measure
find /etc/wireguard/backup/ -type d -mtime +7 -exec rm -rf {} +
```

## Security Best Practices

### Rotation Frequency
- **Regular rotation**: Every 3-6 months
- **After incidents**: Immediately after any security concern
- **Device changes**: When employees leave or devices are replaced
- **Compliance**: As required by your security policy

### Key Distribution Security
1. **Never send keys over unencrypted channels** (email, SMS, etc.)
2. **Use different channels** for config and password if encrypted
3. **Prefer QR codes** for in-person setup
4. **Delete keys** from temporary locations after distribution

### Automation Tips

#### Scheduled Rotation (Monthly)
Add to crontab:
```bash
# Rotate all peer keys monthly (keep server key stable)
0 3 1 * * /root/wg-key-rotate.sh --all-peers --no-backup
```

#### Notification Script
Create a notification script:
```bash
#!/bin/sh
# notify-rotation.sh
PEERS="laptop phone tablet"
for peer in $PEERS; do
  echo "New WG config generated: $(date)" | \
    mail -s "WireGuard Key Rotation Required" user@example.com
done
```

## Troubleshooting

### Issue: Peers can't connect after rotation
**Check:**
- Server public key in peer configs matches current server key
- Firewall rules still allow WireGuard port
- Interface is actually running: `wg show wg0`

**Fix:**
```bash
# Verify server public key
cat /etc/wireguard/publickey

# Restart services
/etc/init.d/network restart
/etc/init.d/firewall restart

# Check logs
logread | grep -i wireguard
```

### Issue: Lost access to a peer's private key
**Solution:** Must rotate that peer's keys
```bash
./wg-key-rotate.sh --peer=affected_peer
```

### Issue: Rotation script fails mid-way
**Recovery:**
```bash
# Restore from backup
cp /etc/wireguard/backup/[timestamp]/* /etc/wireguard/
uci commit network
/etc/init.d/network restart
```

## Manual Key Rotation (Without Script)

If you prefer manual control:

### 1. Generate new keypair
```bash
cd /etc/wireguard
umask 077
wg genkey | tee privatekey-new | wg pubkey > publickey-new
```

### 2. Update UCI configuration
```bash
# For server
uci set network.wg0.private_key="$(cat privatekey-new)"

# For peer (example)
uci set network.wireguard_wg0_laptop.public_key="[NEW_PEER_PUBLIC_KEY]"

uci commit network
```

### 3. Create new peer config
```bash
cat > /etc/wireguard/peers/laptop.conf <<EOF
[Interface]
PrivateKey = [NEW_PEER_PRIVATE_KEY]
Address = 192.168.20.2/32
DNS = 192.168.20.1

[Peer]
PublicKey = $(cat /etc/wireguard/publickey-new)
Endpoint = your.server.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
```

### 4. Apply changes
```bash
mv privatekey-new privatekey
mv publickey-new publickey
/etc/init.d/network restart
```

## Advanced Features

### Partial Rotation with Grace Period
For zero-downtime rotation, you can temporarily accept both old and new keys:

1. Generate new keys but keep old ones
2. Configure WireGuard to accept both (requires custom scripting)
3. Gradually migrate peers
4. Remove old keys after grace period

### Integration with Configuration Management
For larger deployments, integrate with:
- **Ansible**: Automate key distribution
- **Terraform**: Manage WireGuard infrastructure
- **Vault**: Store keys securely
- **LDAP/AD**: Centralized peer management

## Summary

Key rotation is essential for WireGuard security. The provided script makes it easy:

1. **Use the script** for automated rotation
2. **Always backup** before rotating
3. **Test thoroughly** after rotation
4. **Document** your rotation procedures
5. **Train users** on updating their configs

Regular key rotation combined with good operational security will keep your WireGuard VPN secure and reliable.
