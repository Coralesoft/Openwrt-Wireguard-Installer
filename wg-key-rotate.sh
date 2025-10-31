#!/bin/sh
# wg-key-rotate.sh - WireGuard key rotation script for OpenWrt
#
# Description: Safely rotates WireGuard server and/or peer keys with minimal downtime
#
# Version: 2025.9.1
#
# Usage: ./wg-key-rotate.sh [--server] [--peer=NAME] [--all-peers] [--backup]

set -e
trap 'print_error "Error on line $LINENO"; exit 1' ERR

# Colors
print_info()   { printf "\033[0;32m%s\033[0m\n" "$1"; }
print_error()  { printf "\033[0;31m%s\033[0m\n" "$1"; }
print_warn()   { printf "\033[0;33m%s\033[0m\n" "$1"; }
print_prompt() { printf "\033[0;33m%s\033[0m" "$1"; }

# Configuration
WG_IFACE="wg0"
KEYDIR="/etc/wireguard"
PEERDIR="$KEYDIR/peers"
ROTATE_SERVER=0
ROTATE_ALL_PEERS=0
CREATE_BACKUP=1
SPECIFIC_PEERS=""
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --server)
      ROTATE_SERVER=1
      ;;
    --peer=*)
      PEER_NAME="${1#*=}"
      SPECIFIC_PEERS="$SPECIFIC_PEERS $PEER_NAME"
      ;;
    --all-peers)
      ROTATE_ALL_PEERS=1
      ;;
    --no-backup)
      CREATE_BACKUP=0
      ;;
    --interface=*)
      WG_IFACE="${1#*=}"
      ;;
    --help|-h)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --server           Rotate the server's keypair
  --peer=NAME        Rotate a specific peer's keypair (can be used multiple times)
  --all-peers        Rotate all peer keypairs
  --no-backup        Skip creating backups of old keys
  --interface=NAME   Specify WireGuard interface (default: wg0)
  --help            Show this help message

Examples:
  $0 --server                    # Rotate only server keys
  $0 --peer=laptop               # Rotate only laptop peer keys
  $0 --peer=laptop --peer=phone  # Rotate multiple specific peers
  $0 --all-peers                 # Rotate all peer keys
  $0 --server --all-peers        # Rotate everything

Security Notes:
  - After rotation, you must update configurations on all affected devices
  - Old keys are backed up to $KEYDIR/backup/ unless --no-backup is used
  - The script generates new .conf files for all rotated peers
EOF
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      print_info "Use --help for usage information"
      exit 1
      ;;
  esac
  shift
done

# Validate selections
if [ "$ROTATE_SERVER" -eq 0 ] && [ "$ROTATE_ALL_PEERS" -eq 0 ] && [ -z "$SPECIFIC_PEERS" ]; then
  print_error "No rotation target specified!"
  print_info "Use --server, --peer=NAME, or --all-peers"
  print_info "Run with --help for usage information"
  exit 1
fi

# Check requirements
if ! command -v wg >/dev/null 2>&1; then
  print_error "WireGuard tools not found. Install with:"
  print_error "  opkg update && opkg install wireguard-tools"
  exit 1
fi

if ! command -v uci >/dev/null 2>&1; then
  print_error "UCI not found. This script requires OpenWrt."
  exit 1
fi

# Verify interface exists
if ! uci show network."$WG_IFACE" >/dev/null 2>&1; then
  print_error "WireGuard interface '$WG_IFACE' not found in UCI configuration"
  exit 1
fi

# Create backup directory
if [ "$CREATE_BACKUP" -eq 1 ]; then
  BACKUP_DIR="$KEYDIR/backup/$TIMESTAMP"
  mkdir -p "$BACKUP_DIR"
  print_info "Creating key backups in: $BACKUP_DIR"
fi

# Function to backup a file
backup_file() {
  if [ "$CREATE_BACKUP" -eq 1 ] && [ -f "$1" ]; then
    cp "$1" "$BACKUP_DIR/$(basename "$1")"
  fi
}

# Function to generate new keypair
generate_keypair() {
  local prefix="$1"
  umask 077
  wg genkey | tee "${prefix}-privatekey" | wg pubkey > "${prefix}-publickey"
}

#
# ROTATE SERVER KEYS
#
if [ "$ROTATE_SERVER" -eq 1 ]; then
  print_info ""
  print_info "════════════════════════════════════════"
  print_info "ROTATING SERVER KEYS"
  print_info "════════════════════════════════════════"
  
  # Backup old keys
  backup_file "$KEYDIR/privatekey"
  backup_file "$KEYDIR/publickey"
  
  # Generate new server keypair
  print_info "Generating new server keypair..."
  cd "$KEYDIR"
  generate_keypair "$KEYDIR/key"
  mv "$KEYDIR/key-privatekey" "$KEYDIR/privatekey"
  mv "$KEYDIR/key-publickey" "$KEYDIR/publickey"
  
  NEW_SERVER_PRIV=$(cat "$KEYDIR/privatekey")
  NEW_SERVER_PUB=$(cat "$KEYDIR/publickey")
  
  # Update UCI configuration
  print_info "Updating server configuration..."
  uci set network."$WG_IFACE".private_key="$NEW_SERVER_PRIV"
  uci commit network
  
  print_info "New server public key: $NEW_SERVER_PUB"
  print_warn ""
  print_warn "⚠ IMPORTANT: All peers must update their configurations with the new server public key!"
  print_warn ""
  
  # Update all peer config files with new server public key
  if [ -d "$PEERDIR" ]; then
    for conf in "$PEERDIR"/*.conf; do
      [ -f "$conf" ] || continue
      peer_name=$(basename "$conf" .conf)
      print_info "Updating $peer_name.conf with new server public key..."
      
      # Backup original conf
      backup_file "$conf"
      
      # Replace the server's public key in peer config
      sed -i "s|^PublicKey = .*|PublicKey = $NEW_SERVER_PUB|" "$conf"
    done
  fi
else
  # Load existing server public key for peer configs
  if [ -f "$KEYDIR/publickey" ]; then
    NEW_SERVER_PUB=$(cat "$KEYDIR/publickey")
  fi
fi

#
# DETERMINE WHICH PEERS TO ROTATE
#
PEERS_TO_ROTATE=""

if [ "$ROTATE_ALL_PEERS" -eq 1 ]; then
  # Get all peers from UCI config
  print_info ""
  print_info "Identifying all peers..."
  for section in $(uci show network | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
    desc=$(uci get network."$section".description 2>/dev/null || echo "$section")
    PEERS_TO_ROTATE="$PEERS_TO_ROTATE $desc"
  done
elif [ -n "$SPECIFIC_PEERS" ]; then
  PEERS_TO_ROTATE="$SPECIFIC_PEERS"
fi

#
# ROTATE PEER KEYS
#
if [ -n "$PEERS_TO_ROTATE" ]; then
  print_info ""
  print_info "════════════════════════════════════════"
  print_info "ROTATING PEER KEYS"
  print_info "════════════════════════════════════════"
  
  mkdir -p "$PEERDIR"
  
  for peer_name in $PEERS_TO_ROTATE; do
    print_info ""
    print_info "Processing peer: $peer_name"
    
    # Find the UCI section for this peer
    uci_section=""
    for section in $(uci show network | grep "=wireguard_${WG_IFACE}$" | cut -d. -f2 | cut -d= -f1); do
      desc=$(uci get network."$section".description 2>/dev/null || "")
      if [ "$desc" = "$peer_name" ]; then
        uci_section="$section"
        break
      fi
    done
    
    if [ -z "$uci_section" ]; then
      print_error "  Peer '$peer_name' not found in UCI config, skipping..."
      continue
    fi
    
    # Backup old keys
    backup_file "$PEERDIR/${peer_name}-privatekey"
    backup_file "$PEERDIR/${peer_name}-publickey"
    backup_file "$PEERDIR/${peer_name}.conf"
    
    # Generate new peer keypair
    print_info "  Generating new keypair..."
    cd "$PEERDIR"
    generate_keypair "${peer_name}"
    
    NEW_PEER_PRIV=$(cat "${peer_name}-privatekey")
    NEW_PEER_PUB=$(cat "${peer_name}-publickey")
    
    # Update UCI with new public key
    print_info "  Updating UCI configuration..."
    uci set network."$uci_section".public_key="$NEW_PEER_PUB"
    
    # Get peer's allowed IP from UCI
    PEER_IP=$(uci get network."$uci_section".allowed_ips 2>/dev/null | head -n1)
    
    # Get server endpoint and DNS settings
    WG_PORT=$(uci get network."$WG_IFACE".listen_port 2>/dev/null || echo "51820")
    
    # Try to get endpoint from existing conf file
    ENDPOINT=""
    OLD_DNS=""
    if [ -f "${peer_name}.conf" ]; then
      ENDPOINT=$(grep "^Endpoint = " "${peer_name}.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
      OLD_DNS=$(grep "^DNS = " "${peer_name}.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')
    fi
    
    # Use defaults if not found
    if [ -z "$ENDPOINT" ]; then
      print_prompt "  Enter public endpoint for this peer [your.host:$WG_PORT]: "
      read -r endpoint_input
      ENDPOINT="${endpoint_input:-your.host:$WG_PORT}"
    fi
    
    if [ -z "$OLD_DNS" ]; then
      # Extract base IP from server address for DNS default
      SERVER_IP=$(uci get network."$WG_IFACE".addresses 2>/dev/null | head -n1 | cut -d/ -f1)
      OLD_DNS="${SERVER_IP:-192.168.20.1}"
    fi
    
    # Create new peer config file
    print_info "  Generating new config file..."
    cat > "${peer_name}.conf" <<EOF
[Interface]
PrivateKey = $NEW_PEER_PRIV
Address = $PEER_IP
DNS = $OLD_DNS

[Peer]
PublicKey = $NEW_SERVER_PUB
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    print_info "  New public key: $NEW_PEER_PUB"
    print_info "  Config saved to: $PEERDIR/${peer_name}.conf"
    
    # Generate QR code if available
    if command -v qrencode >/dev/null 2>&1; then
      print_info "  Generating QR code..."
      qrencode -t ansiutf8 < "${peer_name}.conf"
      
      # Try to generate PNG
      if qrencode -t png -o "${peer_name}.png" < "${peer_name}.conf" 2>/dev/null; then
        print_info "  QR PNG saved to: $PEERDIR/${peer_name}.png"
      fi
    fi
  done
  
  # Commit all peer changes
  print_info ""
  print_info "Committing peer configuration changes..."
  uci commit network
fi

#
# RESTART WIREGUARD INTERFACE
#
print_info ""
print_info "════════════════════════════════════════"
print_info "APPLYING CHANGES"
print_info "════════════════════════════════════════"

print_prompt "Restart WireGuard interface now? [Y/n]: "
read -r restart_confirm
restart_confirm=${restart_confirm:-y}

if [ "${restart_confirm##[Nn]}" != "" ]; then
  print_info "Restarting WireGuard interface..."
  /etc/init.d/network reload
  
  # Wait a moment and verify interface is up
  sleep 2
  if wg show "$WG_IFACE" >/dev/null 2>&1; then
    print_info "✓ WireGuard interface is running"
  else
    print_error "⚠ WireGuard interface failed to start!"
    print_info "Check logs with: logread | grep -i wireguard"
  fi
else
  print_warn "Interface not restarted. Run manually with:"
  print_warn "  /etc/init.d/network reload"
fi

#
# SUMMARY
#
print_info ""
print_info "════════════════════════════════════════"
print_info "KEY ROTATION COMPLETE"
print_info "════════════════════════════════════════"

if [ "$ROTATE_SERVER" -eq 1 ]; then
  print_info "✓ Server keys rotated"
  print_warn "  → ALL peers need the new server public key!"
fi

if [ -n "$PEERS_TO_ROTATE" ]; then
  peer_count=$(echo "$PEERS_TO_ROTATE" | wc -w)
  print_info "✓ Rotated keys for $peer_count peer(s)"
  print_warn "  → Distribute new .conf files to affected devices"
fi

if [ "$CREATE_BACKUP" -eq 1 ]; then
  print_info ""
  print_info "Old keys backed up to: $BACKUP_DIR"
  print_info "Delete backups after confirming all devices work:"
  print_info "  rm -rf $BACKUP_DIR"
fi

print_info ""
print_info "NEXT STEPS:"
print_info "1. Distribute new configurations to all affected devices"
print_info "2. Test connectivity from each device"
print_info "3. Remove old key backups once everything works"

if [ "$ROTATE_SERVER" -eq 1 ]; then
  print_info ""
  print_warn "Server Public Key for peer configs:"
  print_warn "$NEW_SERVER_PUB"
fi

print_info ""
print_info "Peer configs location: $PEERDIR/"
ls -la "$PEERDIR"/*.conf 2>/dev/null | awk '{print "  • "$NF}'
