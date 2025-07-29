#!/bin/sh
# wg-openwrt-installer.sh — OpenWrt WireGuard installer (conf + QR + rollback support)
#
# Description:
#   Automates the interactive setup of a WireGuard VPN server on OpenWrt.
#   Generates server and peer keys, applies UCI network and firewall config,
#   outputs peer .conf files with optional QR codes, and supports rollback.
#
# Copyright (C) 2025 C. Brown <dev@coralesoft.nz>
# License: MIT
# Last revised: 2025-07-29
# Version: 2025.7.2 (with auto peer IP + safe uci delete)

set -e
trap 'print_error "Error on line $LINENO"; exit 1' ERR

# ANSI colour helpers
print_info()   { printf "\033[0;32m%s\033[0m\n" "$1"; }
print_error()  { printf "\033[0;31m%s\033[0m\n" "$1"; }
print_prompt() { printf "\033[0;33m%s\033[0m"   "$1"; }

LOGFILE="/tmp/wg-setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

# Ensure required commands
for cmd in wg uci; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print_error "Missing '$cmd'. Run: opkg update && opkg install wireguard-tools luci-app-wireguard"
    exit 1
  fi
done

# Optional QR support
HAS_QR=0
if command -v qrencode >/dev/null 2>&1; then
  HAS_QR=1
fi

ask_var() {
  name=$1; prompt=$2; what=$3; why=$4; default=$5
  print_info ""
  print_info "→ $prompt"
  print_info "     What: $what"
  print_info "     Why : $why"
  print_prompt "   Enter $prompt [$default]: "
  read -r reply
  eval "$name=\"\${reply:-$default}\""
}

print_info "Welcome to the WireGuard auto‑setup for OpenWrt!"

ask_var WG_IFACE "WireGuard interface name" "VPN interface name in UCI" "Used in network & firewall configs" "wg0"
ask_var WG_PORT  "UDP listen port" "Port WireGuard listens on" "Must be open/forwarded" "51820"
ask_var WG_ADDR  "Server VPN address (CIDR)" "IP and subnet for the server" "Defines VPN subnet" "192.168.20.1/24"
ask_var ENDPOINT "Public endpoint (host:port)" "Your OpenWrt’s public hostname or IP" "Used by peers to connect" "your.openwrt.hostname:$WG_PORT"
ask_var LAN_ZONE "LAN zone name" "LAN firewall zone in OpenWrt" "Enables LAN ↔ VPN traffic" "lan"
ask_var WAN_ZONE "WAN zone name" "WAN firewall zone in OpenWrt" "Allows peer connections" "wan"

# Default DNS is server IP
DEFAULT_DNS="$(printf '%s\n' "$WG_ADDR" | cut -d/ -f1)"
ask_var WG_DNS  "DNS server for peers" "DNS IP to suggest to peers" "Avoids DNS leaks / enables local names" "$DEFAULT_DNS"
ask_var NUM_PEERS "Number of peers to add" "How many devices will connect" "Each gets its own config & keypair" "0"

# Validate peer count
if ! printf '%s' "$NUM_PEERS" | grep -qE '^[0-9]+$'; then
  print_error "Invalid number of peers: $NUM_PEERS"
  exit 1
fi

# Backup configs
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
NET_BAK="/etc/config/network.bak.$TIMESTAMP"
FW_BAK="/etc/config/firewall.bak.$TIMESTAMP"

print_info ""
print_info "Creating backups before applying changes…"
cp /etc/config/network "$NET_BAK"
cp /etc/config/firewall "$FW_BAK"
print_info "  • Network config → $NET_BAK"
print_info "  • Firewall config → $FW_BAK"

# Server keypair
KEYDIR="/etc/wireguard"
mkdir -p "$KEYDIR"
if [ ! -f "$KEYDIR/privatekey" ]; then
  print_info "Generating server keypair…"
  umask 077
  wg genkey | tee "$KEYDIR/privatekey" | wg pubkey > "$KEYDIR/publickey"
else
  print_info "Found existing server keypair."
fi
SERVER_PRIV=$(< "$KEYDIR/privatekey")
SERVER_PUB=$(< "$KEYDIR/publickey")

print_info ""
print_info "Server public key: $SERVER_PUB"

# Peer configs
PEERDIR="$KEYDIR/peers"
mkdir -p "$PEERDIR"

# Base subnet for default peer IPs
WG_SUBNET_BASE="$(echo "$WG_ADDR" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')"

PEERS=""
count=0
while [ "$count" -lt "$NUM_PEERS" ]; do
  peer_num=$((count + 1))
  print_info ""
  print_info "Peer #$peer_num details:"

  print_prompt "   Name (no spaces, e.g. phone, laptop): "
  read -r PNAME
  PNAME=${PNAME// /_}
  [ -z "$PNAME" ] && { print_error "Name required; try again."; continue; }

  DEFAULT_PIP="$WG_SUBNET_BASE.$((count + 2))/32"
  print_prompt "   Allowed IP (e.g. 192.168.20.2/32) [$DEFAULT_PIP]: "
  read -r PIP
  PIP="${PIP:-$DEFAULT_PIP}"

  case "$PIP" in
    */32) ;;
    *) print_error "Must include /32 suffix; try again."; continue ;;
  esac

  umask 077
  PPRIV=$(wg genkey)
  PPUB=$(printf '%s' "$PPRIV" | wg pubkey)

  printf '%s' "$PPRIV" > "$PEERDIR/$PNAME-privatekey"
  printf '%s' "$PPUB" > "$PEERDIR/$PNAME-publickey"

  cat > "$PEERDIR/$PNAME.conf" <<EOF
[Interface]
PrivateKey = $PPRIV
Address = $PIP
DNS = $WG_DNS

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  print_info " Config generated: $PEERDIR/$PNAME.conf"
  [ "$HAS_QR" -eq 1 ] && qrencode -t ansiutf8 < "$PEERDIR/$PNAME.conf"

  PEERS="${PEERS}
$PNAME:$PPUB:$PIP"
  count=$((count + 1))
done

# Apply network config
print_info ""
print_info "Applying WireGuard network config…"
uci batch <<EOF
set network.$WG_IFACE=interface
set network.$WG_IFACE.proto='wireguard'
set network.$WG_IFACE.private_key='$SERVER_PRIV'
set network.$WG_IFACE.listen_port='$WG_PORT'
delete network.$WG_IFACE.addresses
add_list network.$WG_IFACE.addresses='$WG_ADDR'
EOF 2>/dev/null || true

# Add peers to UCI
printf '%s\n' "$PEERS" | while IFS=":" read -r NAME PUB IP; do
  [ -z "$NAME" ] && continue
  section="wireguard_${WG_IFACE}_${NAME}"
  uci set "network.$section=wireguard_${WG_IFACE}"
  uci set "network.$section.public_key=$PUB"
  uci set "network.$section.persistent_keepalive=25"
  uci delete "network.$section.allowed_ips" 2>/dev/null || true
  uci add_list "network.$section.allowed_ips=$IP"
done
uci commit network

print_prompt "Restart network now? [y/N]: "
read -r confirm
case "$confirm" in [yY]*) /etc/init.d/network restart ;; esac

# Firewall rules
print_info ""
print_info "Applying firewall rules…"
if ! uci show firewall | grep -q "firewall.@zone.*name='$WG_IFACE'"; then
  uci add firewall zone
  uci set firewall.@zone[-1].name="$WG_IFACE"
  uci set firewall.@zone[-1].input='ACCEPT'
  uci set firewall.@zone[-1].output='ACCEPT'
  uci set firewall.@zone[-1].forward='DROP'
  uci add_list firewall.@zone[-1].network="$WG_IFACE"
fi

uci add firewall forwarding
uci set firewall.@forwarding[-1].src="$WG_IFACE"
uci set firewall.@forwarding[-1].dest="$LAN_ZONE"

uci add firewall forwarding
uci set firewall.@forwarding[-1].src="$LAN_ZONE"
uci set firewall.@forwarding[-1].dest="$WG_IFACE"

uci add firewall rule
uci set firewall.@rule[-1].name="Allow-WG-$WG_IFACE"
uci set firewall.@rule[-1].src="$WAN_ZONE"
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$WG_PORT"
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
/etc/init.d/firewall restart

print_info ""
print_info "WireGuard '$WG_IFACE' setup complete."
print_info "→ Peer configs saved in: $PEERDIR/"
[ "$HAS_QR" -eq 1 ] && print_info "→ QR codes shown above (scan with the WireGuard app)."

# Offer rollback
print_info ""
print_prompt "Do you want to rollback to previous network/firewall config? [y/N]: "
read -r rollback
if [ "$rollback" = "y" ] || [ "$rollback" = "Y" ]; then
  print_info "Rolling back to saved config from $TIMESTAMP…"
  cp "$NET_BAK" /etc/config/network
  cp "$FW_BAK" /etc/config/firewall
  /etc/init.d/network restart
  /etc/init.d/firewall restart
  print_info "Rollback complete. Reverted to previous config."
  exit 0
fi
